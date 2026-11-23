import { beforeEach, describe, expect, it } from "vitest";
import {
	BARN_SLOTS,
	barnEntries,
	isBarnStorable,
	isFarmMirroredItem,
} from "./barnStorage";
import { freeSpaceFor, useInventoryStore } from "./inventoryStore";
import { ITEMS } from "./items";

beforeEach(() => {
	useInventoryStore.getState().resetInventory();
});

describe("barn storage model", () => {
	it("lists stored items sorted, dropping empty entries", () => {
		expect(barnEntries({ tomato: 3, "seed-bag": 0, crate: 1 })).toEqual([
			{ itemId: "crate", count: 1 },
			{ itemId: "tomato", count: 3 },
		]);
	});

	it("caps the list to the number of visible slots", () => {
		const storage = Object.fromEntries(
			Array.from({ length: BARN_SLOTS + 6 }, (_, i) => [`item-${i}`, 1]),
		);
		expect(barnEntries(storage)).toHaveLength(BARN_SLOTS);
	});

	it("reports free space across empty and partial stacks", () => {
		const state = useInventoryStore.getState();
		const slots = [...state.hotbar, ...state.grid];
		const seedStack = ITEMS["seed-bag"].maxStack;
		const heldSeeds = slots
			.filter((slot) => slot.itemId === "seed-bag")
			.reduce((sum, slot) => sum + slot.count, 0);
		const emptySlots = slots.filter((slot) => !slot.itemId).length;
		expect(freeSpaceFor(state, "seed-bag")).toBe(
			seedStack - heldSeeds + emptySlots * seedStack,
		);
	});

	it("tracks the barn window and clears it on reset", () => {
		useInventoryStore.getState().setBarnOpen(true);
		expect(useInventoryStore.getState().barnOpen).toBe(true);
		useInventoryStore.getState().resetInventory();
		expect(useInventoryStore.getState().barnOpen).toBe(false);
	});
});

describe("barn storage item rules", () => {
	it("refuses to store placed buildings and decor", () => {
		expect(isBarnStorable("barn")).toBe(false);
		expect(isBarnStorable("brewery")).toBe(false);
		expect(isBarnStorable("oak-tree")).toBe(false);
	});

	it("stores produce, seeds, materials, fish, and tools", () => {
		for (const id of ["tomato", "seed-bag", "nails", "minnow", "hoe"] as const) {
			expect(isBarnStorable(id)).toBe(true);
		}
	});

	it("knows which items the farm broadcast mirrors into the inventory", () => {
		// Adding these locally after a withdrawal would double the stack.
		expect(isFarmMirroredItem("tomato")).toBe(true);
		expect(isFarmMirroredItem("beer")).toBe(true);
		expect(isFarmMirroredItem("cow")).toBe(true);
		expect(isFarmMirroredItem("fence")).toBe(true);
		// These have no farm mirror, so the barn ack must restore them.
		expect(isFarmMirroredItem("seed-bag")).toBe(false);
		expect(isFarmMirroredItem("minnow")).toBe(false);
		expect(isFarmMirroredItem("hoe")).toBe(false);
	});
});
