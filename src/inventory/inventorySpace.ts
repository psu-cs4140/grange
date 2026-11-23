import type { InventorySlot } from "./inventoryStore";
import { ITEMS, type ItemId } from "./items";

/** How many more of an item the inventory can hold across all slots. */
export function freeSpaceFor(
	state: { grid: InventorySlot[]; hotbar: InventorySlot[] },
	itemId: ItemId,
): number {
	const max = ITEMS[itemId].maxStack;
	let space = 0;
	for (const slot of [...state.hotbar, ...state.grid]) {
		if (!slot.itemId) space += max;
		else if (slot.itemId === itemId) space += Math.max(0, max - slot.count);
	}
	return space;
}
