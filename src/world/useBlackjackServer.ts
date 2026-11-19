import { useCallback, useEffect, useRef, useState } from "react";
import { economy } from "./EconomyManager";
import type { Bank } from "./blackjackTypes";

export const adminPokerBank: Bank = {
	getBalance: () => economy.getBalance(),
	withdraw: (amount) => economy.withdrawChips(amount),
	deposit: (amount) => economy.depositChips(amount),
};

type Reply<Snapshot> = {
	hand: Omit<Snapshot, "balance">;
	balance: number;
	version: number;
};
export type BlackjackMove = "deal" | "hit" | "stand" | "double" | "split" | "surrender";
export type PokerMove = "deal" | "check" | "call" | "raise" | "fold";
type Move = BlackjackMove | PokerMove;

export function useCardTableServer<Snapshot extends { balance: number }>(
	game: "blackjack" | "poker",
	enabled: boolean,
) {
	const path = `/api/casino/${game}`;
	const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
	const [busy, setBusy] = useState(enabled);
	const [error, setError] = useState("");
	const version = useRef(0);
	const sending = useRef(false);
	const pending = useRef<{ action_id: string; version: number; move: Move; bet?: number; amount?: number } | null>(null);

	const accept = useCallback((result: Reply<Snapshot>) => {
		version.current = result.version;
		economy.setBalance(result.balance);
		setSnapshot({ ...result.hand, balance: result.balance } as Snapshot);
	}, []);

	useEffect(() => {
		if (!enabled) return;
		const abort = new AbortController();
		fetch(path, { signal: abort.signal })
			.then(async (response) => {
				if (!response.ok) throw new Error("Could not load table.");
				const result: Reply<Snapshot> = await response.json();
				if (!abort.signal.aborted) accept(result);
			})
			.catch(() => {
				if (!abort.signal.aborted) setError("Could not load the table. Reopen it to try again.");
			})
			.finally(() => {
				if (!abort.signal.aborted) setBusy(false);
			});
		return () => abort.abort();
	}, [enabled, accept, path]);

	async function act(move: Move, bet?: number) {
		if (sending.current || !snapshot) return;
		const action = pending.current ?? {
			action_id: crypto.randomUUID(), version: version.current, move,
			...(move === "raise" ? { amount: bet } : { bet }),
		};
		if (action.move !== move) {
			setError(`Retry ${action.move} to confirm your previous action.`);
			return;
		}
		pending.current = action;
		sending.current = true;
		setBusy(true);
		setError("");
		try {
			const response = await fetch(path, {
				method: "POST",
				headers: { "Content-Type": "application/json" },
				body: JSON.stringify(action),
			});
			if (!response.ok) {
				if (response.status < 500) pending.current = null;
				const failure = await response.json();
				throw new Error(failure.error ?? "Could not confirm the action.");
			}
			accept(await response.json());
			pending.current = null;
			return true;
		} catch (failure) {
			setError(failure instanceof Error ? failure.message : "Could not confirm the action.");
		} finally {
			sending.current = false;
			setBusy(false);
		}
	}

	return { snapshot, busy, error, act };
}
