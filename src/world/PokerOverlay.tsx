import { useCallback, useEffect, useRef, useState } from "react";
import { cardCode } from "./cardSlots";
import { Deck } from "./Deck";
import { economy } from "./EconomyManager";
import { PlayingCard } from "./PlayingCard";
import { type HandCategory, CATEGORY_LABEL } from "./pokerHand";
import { PokerTable } from "./pokerGame";
import type { PokerSnapshot } from "./pokerTypes";
import { adminPokerBank, type PokerMove, useCardTableServer } from "./useBlackjackServer";
import "./blackjack.css";
import "./poker.css";

interface PokerOverlayProps {
	onClose: () => void;
}

/** Stable keys for the community-card placeholders not yet dealt. */
const EMPTY_SLOTS = ["slot-0", "slot-1", "slot-2", "slot-3", "slot-4"];

function bestLabel(category: HandCategory | null): string {
	return category ? CATEGORY_LABEL[category] : "—";
}

export function PokerOverlay({ onClose }: PokerOverlayProps) {
	const [table] = useState(() => new PokerTable(adminPokerBank));
	const [localSnapshot, setSnapshot] = useState<PokerSnapshot>(() =>
		table.snapshot(),
	);
	const remote = !economy.isAdmin();
	const server = useCardTableServer<PokerSnapshot>("poker", remote);
	const snapshot = server.snapshot ?? localSnapshot;
	const [raiseTo, setRaiseTo] = useState(0);

	const deckRef = useRef<HTMLDivElement>(null);
	const seen = useRef<Set<string>>(new Set());

	const codes = [
		...snapshot.playerHole.map(cardCode),
		...snapshot.dealerHole.map((card, i) =>
			snapshot.dealerHidden ? `__dealer${i}__` : cardCode(card),
		),
		...snapshot.community.map(cardCode),
	];
	const isNew = (code: string) => !seen.current.has(code);

	// Remember what is already on the felt so only fresh cards animate in.
	useEffect(() => {
		seen.current = new Set(codes);
	});

	const run = (move: PokerMove, amount = 0) => {
		if (remote) {
			void server.act(move, amount);
			return;
		}
		if (move === "deal") table.startHand();
		else if (move === "raise") table.raiseTo(amount);
		else table[move]();
		setSnapshot(table.snapshot());
	};

	// Public hands remain on the server when the player leaves the table.
	const leave = useCallback(() => {
		if (server.busy) return;
		if (!remote && (snapshot.phase === "playerTurn" || snapshot.phase === "dealerTurn")) {
			table.forfeit();
		}
		onClose();
	}, [table, snapshot.phase, onClose, remote, server.busy]);

	useEffect(() => {
		if (snapshot.phase === "playerTurn") setRaiseTo(snapshot.minRaiseTo);
	}, [snapshot.phase, snapshot.minRaiseTo]);

	useEffect(() => {
		const onKey = (event: KeyboardEvent) => {
			if (event.key === "Escape") leave();
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [leave]);

	const clampRaise = (value: number) =>
		Math.min(
			snapshot.maxRaiseTo,
			Math.max(snapshot.minRaiseTo, Math.floor(value)),
		);

	const canBet = snapshot.phase === "playerTurn";

	return (
		<div className="bj-overlay" data-testid="poker-overlay">
			<div
				className="bj-panel poker-panel"
				role="dialog"
				aria-label="Poker table"
			>
				{server.error && <p role="alert">{server.error}</p>}
				<header className="bj-header">
					<h2 className="bj-title">Texas Hold'em</h2>
					<span className="pk-pot" data-testid="poker-pot">
						Pot ${snapshot.pot}
					</span>
					<span className="bj-balance" data-testid="poker-balance">
						${snapshot.balance.toLocaleString()}
					</span>
					<Deck deckRef={deckRef} testId="poker-deck" />
					<button
						type="button"
						className="bj-close"
						data-testid="poker-close"
						onClick={leave}
					>
						Leave
					</button>
				</header>

				<div className="bj-scroll">
					<section className="bj-seat" data-testid="poker-dealer">
						<span className="bj-seat-name">
							Dealer · ${snapshot.dealerStack.toLocaleString()}
						</span>
						<div className="bj-hand">
							{/* Stable slot keys (d0/d1) keep the reveal a flip, not a re-deal. */}
							{snapshot.dealerHole
								.map((card, index) => ({ key: `d${index}`, card, index }))
								.map((slot) => (
									<PlayingCard
										key={slot.key}
										card={snapshot.dealerHidden ? undefined : slot.card}
										faceDown={snapshot.dealerHidden}
										deal={isNew(
											snapshot.dealerHidden
												? `__dealer${slot.index}__`
												: cardCode(slot.card),
										)}
										dealDelay={slot.index * 90}
										deckRef={deckRef}
									/>
								))}
							{snapshot.dealerHole.length === 0 && (
								<p className="bj-empty">No hand yet.</p>
							)}
						</div>
						<span className="bj-total">
							{snapshot.dealerHidden
								? "Hole cards hidden"
								: `Best: ${bestLabel(snapshot.dealerBest)}`}
						</span>
					</section>

					<div className="poker-community" data-testid="poker-community">
						{snapshot.community.map((card, i) => (
							<PlayingCard
								key={cardCode(card)}
								card={card}
								deal={isNew(cardCode(card))}
								dealDelay={i * 80}
								deckRef={deckRef}
							/>
						))}
						{EMPTY_SLOTS.slice(snapshot.community.length).map((key) => (
							<div className="poker-slot" key={key} aria-hidden="true" />
						))}
					</div>

					<section
						className={
							snapshot.winner === "player"
								? "bj-seat poker-player poker-player-win"
								: "bj-seat poker-player"
						}
						data-testid="poker-player"
					>
						<span className="bj-seat-name">You</span>
						<div className="bj-hand" data-testid="poker-player-hand">
							{snapshot.playerHole.map((card, i) => (
								<PlayingCard
									key={cardCode(card)}
									card={card}
									deal={isNew(cardCode(card))}
									dealDelay={i * 90}
									deckRef={deckRef}
								/>
							))}
						</div>
						<span className="bj-total">
							Best: {bestLabel(snapshot.playerBest)}
							{snapshot.playerCommitted > 0
								? ` · committed $${snapshot.playerCommitted}`
								: ""}
						</span>
					</section>
				</div>

				<p className="bj-message" data-testid="poker-message">
					{snapshot.message}
				</p>

				{(snapshot.phase === "idle" || snapshot.phase === "settled") && (
					<div className="bj-actions">
						<button
							type="button"
							className="bj-action bj-primary"
							data-testid="poker-deal"
							disabled={remote && (!server.snapshot || server.busy)}
							onClick={() => run("deal")}
						>
							{snapshot.phase === "settled" ? "Next hand" : "Deal"}
						</button>
						<button
							type="button"
							className="bj-action"
							data-testid="poker-leave"
							onClick={leave}
						>
							Leave table
						</button>
					</div>
				)}

				{canBet && (
					<>
						<div className="bj-actions">
							<button
								type="button"
								className="bj-action"
								data-testid="poker-fold"
								onClick={() => run("fold")}
							>
								Fold
							</button>
							{snapshot.canCheck ? (
								<button
									type="button"
									className="bj-action bj-primary"
									data-testid="poker-check"
									onClick={() => run("check")}
								>
									Check
								</button>
							) : (
								<button
									type="button"
									className="bj-action bj-primary"
									data-testid="poker-call"
									onClick={() => run("call")}
								>
									Call ${snapshot.callAmount}
								</button>
							)}
						</div>
						{snapshot.canRaise && (
							<div className="bj-betting">
								<div className="bj-chips">
									<button
										type="button"
										className="bj-chip"
										onClick={() => setRaiseTo(snapshot.minRaiseTo)}
									>
										Min
									</button>
									<button
										type="button"
										className="bj-chip"
										onClick={() =>
											setRaiseTo(
												clampRaise(snapshot.currentBet + snapshot.pot * 0.5),
											)
										}
									>
										½ Pot
									</button>
									<button
										type="button"
										className="bj-chip"
										onClick={() =>
											setRaiseTo(clampRaise(snapshot.currentBet + snapshot.pot))
										}
									>
										Pot
									</button>
									<button
										type="button"
										className="bj-chip"
										data-testid="poker-all-in"
										onClick={() => setRaiseTo(snapshot.maxRaiseTo)}
									>
										All in
									</button>
								</div>
								<label className="bj-bet-field">
									Raise
									<input
										type="number"
										min={snapshot.minRaiseTo}
										max={snapshot.maxRaiseTo}
										value={raiseTo}
										data-testid="poker-raise-input"
										onChange={(event) => setRaiseTo(Number(event.target.value))}
									/>
								</label>
								<button
									type="button"
									className="bj-action bj-primary"
									data-testid="poker-raise"
									onClick={() => run("raise", raiseTo)}
								>
									Raise to ${raiseTo}
								</button>
							</div>
						)}
					</>
				)}
			</div>
		</div>
	);
}
