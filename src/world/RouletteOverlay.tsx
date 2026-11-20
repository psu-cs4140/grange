import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { economy } from "./EconomyManager";
import { MIN_BET, pocketColor, ROULETTE_LEGEND } from "./roulette";
import { RouletteBetGrid } from "./RouletteBetGrid";
import { RouletteChip } from "./RouletteChip";
import { RouletteTable } from "./rouletteGame";
import { BET_SPOT_BY_ID } from "./rouletteLayout";
import { requestRouletteSpin, RouletteSpinError, type RouletteSpinRequest } from "./rouletteSpin";
import type { Bank, BetSpot, RouletteSnapshot } from "./rouletteTypes";
import { RouletteWheel } from "./RouletteWheel";
import "./roulette.css";

const CHIPS = [5, 25, 100];


interface RouletteOverlayProps {
	onClose: () => void;
}

export function RouletteOverlay({ onClose }: RouletteOverlayProps) {
	const bank = useMemo<Bank>(
		() => ({
			getBalance: () => economy.getBalance(),
			withdraw: (amount) => economy.buy(amount).success,
			deposit: (amount) => {
				economy.sell(amount);
			},
		}),
		[],
	);
	const [table] = useState(() => new RouletteTable(bank));
	const [snapshot, setSnapshot] = useState<RouletteSnapshot>(() =>
		table.snapshot(),
	);
	const [dialogSpot, setDialogSpot] = useState<BetSpot | null>(null);
	const [amountInput, setAmountInput] = useState(String(MIN_BET));
	const trayRef = useRef<HTMLDivElement>(null);
	const pendingSpin = useRef<RouletteSpinRequest | null>(null);
	const requestInFlight = useRef(false);
	const [sending, setSending] = useState(false);
	const [spinError, setSpinError] = useState("");

	const refresh = useCallback(() => setSnapshot(table.snapshot()), [table]);

	const betting = snapshot.phase === "betting" && !sending;
	const spinning = snapshot.phase === "spinning";
	const settled = snapshot.phase === "settled";

	useEffect(() => {
		const onKey = (event: KeyboardEvent) => {
			if (event.key === "Escape" && !spinning && !requestInFlight.current) onClose();
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [onClose, spinning]);

	const amountError = (): string | null => {
		const amount = Number(amountInput);
		if (amountInput.trim() === "" || !Number.isFinite(amount)) {
			return "Enter a bet.";
		}
		if (amount < MIN_BET) return `Minimum bet is ${MIN_BET}.`;
		if (amount > snapshot.available) return "Not enough Grangecoin.";
		return null;
	};

	const onSpotClick = (spot: BetSpot) => {
		if (!betting || pendingSpin.current) return;
		if (snapshot.bets.some((bet) => bet.spotId === spot.id)) {
			table.removeBet(spot.id);
			refresh();
			return;
		}
		setAmountInput(String(MIN_BET));
		setDialogSpot(spot);
	};

	const confirmBet = () => {
		if (!dialogSpot || pendingSpin.current || amountError() !== null) return;
		const ok = table.placeBet(dialogSpot, Number(amountInput));
		refresh();
		if (ok) setDialogSpot(null);
	};

	const spin = async () => {
		if (!betting || requestInFlight.current || snapshot.bets.length === 0) return;
		if (economy.isAdmin()) {
			table.spin();
			refresh();
			return;
		}

		const request = pendingSpin.current ?? {
			spin_id: crypto.randomUUID(),
			bets: Object.fromEntries(snapshot.bets.map(({ spotId, amount }) => [spotId, amount])),
		};
		pendingSpin.current = request;
		requestInFlight.current = true;
		setSending(true);
		setSpinError("");
		try {
			const result = await requestRouletteSpin(request);
			economy.setBalance(result.balance);
			table.showServerSpin(result.pocket);
			pendingSpin.current = null;
			refresh();
		} catch (error) {
			if (error instanceof RouletteSpinError && !error.retryable) pendingSpin.current = null;
			setSpinError(error instanceof Error ? error.message : "The spin could not be confirmed.");
		} finally {
			requestInFlight.current = false;
			setSending(false);
		}
	};

	const onLanded = useCallback(() => setSnapshot(table.settle()), [table]);

	const playAgain = () => {
		table.newRound();
		refresh();
	};

	const resultLabel =
		settled && snapshot.result
			? `${snapshot.result} ${pocketColor(snapshot.result)}`
			: "—";

	return (
		<div className="rl-overlay" data-testid="roulette-overlay">
			<div className="rl-panel" role="dialog" aria-label="Roulette table">
				{spinError && <p role="alert">{spinError}</p>}
				<header className="rl-header">
					<h2 className="rl-title">Roulette</h2>
					<span className="rl-balance" data-testid="roulette-balance">
						${snapshot.balance.toLocaleString()}
					</span>
					<span className="rl-staked" data-testid="roulette-staked">
						On table: ${snapshot.totalStaked}
					</span>
					{betting && (
						<span className="rl-available" data-testid="roulette-available">
							Available: ${snapshot.available}
						</span>
					)}
					<div className="rl-tray" ref={trayRef} aria-hidden="true">
						<span className="rl-tray-chip">$</span>
					</div>
					<button
						type="button"
						className="rl-close"
						data-testid="roulette-close"
						disabled={spinning || sending}
						onClick={onClose}
					>
						Leave
					</button>
				</header>

				<div className="rl-body">
					<div className="rl-wheel-col">
						<RouletteWheel
							phase={snapshot.phase}
							result={snapshot.result}
							onLanded={onLanded}
						/>
						<div className="rl-result" data-testid="roulette-result">
							{resultLabel}
						</div>
						<button
							type="button"
							className="rl-spin"
							data-testid="roulette-spin"
							disabled={!betting || snapshot.bets.length === 0}
							onClick={spin}
						>
							Spin
						</button>
					</div>

					<div className="rl-felt-col">
						<div className="rl-felt">
							<RouletteBetGrid
								bets={snapshot.bets}
								disabled={!betting || pendingSpin.current !== null}
								result={settled ? snapshot.result : null}
								onSpotClick={onSpotClick}
							/>
							<div className="rl-chip-layer">
								{snapshot.bets.map((bet) => {
									const spot = BET_SPOT_BY_ID.get(bet.spotId);
									if (!spot) return null;
									return (
										<RouletteChip
											key={bet.spotId}
											bet={bet}
											spot={spot}
											trayRef={trayRef}
											settled={settled}
										/>
									);
								})}
							</div>
						</div>
						<p className="rl-message" data-testid="roulette-message">
							{snapshot.message}
						</p>
						{settled && (
							<div className="rl-actions">
								<button
									type="button"
									className="rl-action rl-primary"
									data-testid="roulette-play-again"
									onClick={playAgain}
								>
									Play again
								</button>
								<button
									type="button"
									className="rl-action"
									data-testid="roulette-leave"
									onClick={onClose}
								>
									Leave table
								</button>
							</div>
						)}
					</div>
				</div>

				<details className="rl-legend" data-testid="roulette-legend">
					<summary>Payouts</summary>
					<ul>
						{ROULETTE_LEGEND.map(([label, odds]) => (
							<li key={label}>
								<span>{label}</span>
								<span>{odds}</span>
							</li>
						))}
					</ul>
				</details>

				{dialogSpot && (
					<div className="rl-dialog-backdrop">
						<div
							className="rl-dialog"
							role="dialog"
							data-testid="roulette-bet-dialog"
						>
							<h3>Bet on {dialogSpot.label}</h3>
							<p className="rl-dialog-hint">
								Pays {dialogSpot.payout}:1 — win ${dialogSpot.payout + 1} per
								$1.
							</p>
							<div className="rl-dialog-chips">
								{CHIPS.map((chip) => (
									<button
										key={chip}
										type="button"
										className="rl-chip-button"
										data-testid={`roulette-dialog-chip-${chip}`}
										disabled={chip > snapshot.available}
										onClick={() => setAmountInput(String(chip))}
									>
										${chip}
									</button>
								))}
								<button
									type="button"
									className="rl-chip-button"
									data-testid="roulette-dialog-chip-all"
									disabled={snapshot.available < MIN_BET}
									onClick={() => setAmountInput(String(snapshot.available))}
								>
									All-in
								</button>
							</div>
							<label className="rl-amount-field">
								Amount
								<input
									type="number"
									min={MIN_BET}
									value={amountInput}
									data-testid="roulette-amount"
									onChange={(event) => setAmountInput(event.target.value)}
								/>
							</label>
							{amountError() !== null && (
								<span className="rl-error" data-testid="roulette-amount-error">
									{amountError()}
								</span>
							)}
							<div className="rl-dialog-actions">
								<button
									type="button"
									className="rl-action rl-primary"
									data-testid="roulette-confirm"
									disabled={amountError() !== null}
									onClick={confirmBet}
								>
									Place bet
								</button>
								<button
									type="button"
									className="rl-action"
									data-testid="roulette-cancel"
									onClick={() => setDialogSpot(null)}
								>
									Cancel
								</button>
							</div>
						</div>
					</div>
				)}
			</div>
		</div>
	);
}
