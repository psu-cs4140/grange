import { describe, expect, it } from "vitest";
import type { ActiveFarm } from "../../shared/types";
import { BlockRegistry } from "./blocking";
import { fencePlacementReason } from "./fenceActions";
import { terrainAt } from "./mapData";

const farm: ActiveFarm = {
	owner: "tester",
	tiles: [],
	tomatoes: 0,
	barn: {},
	animals: {},
	fences: [],
	fence_count: 1,
	gates: [],
	gate_count: 1,
	prop_overrides: [],
	prop_inventory: {},
};
const player = { x: 800, y: 600 };

describe("fence placement after gate integration", () => {
	it("permits a clear owned grass tile", () => {
		expect(terrainAt(5, 5)).toBe("grass");
		expect(fencePlacementReason(farm, 5, 5, new BlockRegistry(), player)).toBeNull();
	});

	it("rejects a gate post even if collision data has not refreshed", () => {
		const withGate = { ...farm, gates: [{ x: 5, y: 5, direction: "horizontal" as const, open: true }] };
		expect(fencePlacementReason(withGate, 5, 5, new BlockRegistry(), player))
			.toBe("That tile is occupied.");
	});

	it("rejects a depleted supply or occupied player tile", () => {
		expect(fencePlacementReason({ ...farm, fence_count: 0 }, 5, 5,
			new BlockRegistry(), player)).toBe("No fences left in inventory.");
		expect(fencePlacementReason(farm, 5, 5, new BlockRegistry(),
			{ x: 5 * 64 + 32, y: 5 * 64 + 32 })).toBe("That tile is occupied.");
	});
});
