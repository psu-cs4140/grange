import type { PocketId } from "./roulette";

export interface RouletteSpinRequest {
	spin_id: string;
	bets: Record<string, number>;
}

export class RouletteSpinError extends Error {
	constructor(message: string, readonly retryable: boolean) {
		super(message);
	}
}

export async function requestRouletteSpin(
	request: RouletteSpinRequest,
): Promise<{ pocket: PocketId; balance: number }> {
	const response = await fetch("/api/casino/roulette/spin", {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(request),
	});
	if (!response.ok) {
		const failure = await response.json();
		throw new RouletteSpinError(
			failure.error ?? "The spin could not be confirmed.",
			response.status >= 500,
		);
	}
	return response.json();
}
