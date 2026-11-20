import type { HandResult } from "./blackjackTypes";

export const RESULT_LABEL: Record<HandResult, string> = {
	blackjack: "Blackjack",
	win: "Win",
	push: "Push",
	lose: "Lose",
	bust: "Bust",
	surrender: "Surrender",
};

export function totalLabel(total: number, soft: boolean): string {
	if (total > 21) return `${total} (bust)`;
	if (soft && total !== 21) return `${total} (soft)`;
	return String(total);
}
