import type * as ex from "excalibur";
import { useInventoryStore } from "../inventory/inventoryStore";
import type { ItemId } from "../inventory/items";
import { useGameStore } from "../store";
import { opensBarn } from "./barnActions";
import type { FarmPropLayer } from "./farmPropLayer";
import { TOOL_HINTS } from "./farmTools";
import type { InputManager } from "./InputManager";

const PROMPT = "Press E to open the barn";

/**
 * The barn's interaction: the owner sees a prompt while standing at the barn
 * and opens storage with E. A plain click on the barn opens it too, for mouse
 * players. Mirrors FarmTravel so FarmMapScene only wires it up.
 */
export class FarmBarn {
	private activePrompt: string | null = null;

	constructor(
		private readonly isOwner: boolean,
		private readonly onMessage: (message: string) => void,
	) {}

	deactivate(): void {
		this.setPrompt(null);
	}

	/** Re-shows the prompt after another system replaced the HUD message. */
	refresh(): void {
		this.activePrompt = null;
	}

	/** E-key interact; run each frame while the farm is live. */
	update(player: ex.Actor, input: InputManager, props: FarmPropLayer): void {
		const near =
			this.isOwner && props.barnNear(player.pos.x, player.pos.y) !== null;
		this.setPrompt(near ? PROMPT : null);
		// Consume every press even out of reach, so one made while walking in
		// doesn't fire the moment the player arrives.
		if (!input.consumePress("KeyE") || !near) return;
		this.open();
	}

	/** Swallow interact presses while a modal owns input, so closing one does
	 * not immediately reopen the barn. */
	suspend(input: InputManager): void {
		input.consumePress("KeyE", "Enter");
		this.setPrompt(null);
	}

	/** Opens on a click that lands on the barn; true when it handled the click. */
	handleClick(
		worldPos: ex.Vector,
		item: ItemId | null,
		props: FarmPropLayer,
	): boolean {
		const target = props.pick(worldPos.x, worldPos.y);
		if (!opensBarn(this.isOwner, item, target?.asset)) return false;
		this.open();
		return true;
	}

	private open(): void {
		useInventoryStore.getState().setBarnOpen(true);
		this.onMessage("Barn storage.");
	}

	private setPrompt(prompt: string | null): void {
		if (this.activePrompt === prompt) return;
		this.activePrompt = prompt;
		this.onMessage(prompt ?? TOOL_HINTS[useGameStore.getState().tool]);
	}
}
