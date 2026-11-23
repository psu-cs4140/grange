import { expect, test, type Page } from "@playwright/test";
import {
	BASE,
	clickWorld,
	registerFast,
	uniqueName,
	waitForWorld,
} from "./helpers";

/** Where the barn's sprite sits on the farm map (bottom-anchored). */
const BARN = { x: 935, y: 200 };

/** Clicks the barn on the map and waits for the storage window. */
async function openBarn(page: Page) {
	await clickWorld(page, BARN.x, BARN.y);
	await expect(page.getByTestId("barn-window")).toBeVisible();
}

/**
 * Walks from the farm spawn to the barn's front. A short north leg clears the
 * barrels beside the barn, then the up-right diagonal reaches its base.
 */
async function walkToBarn(page: Page) {
	const prompt = page.getByTestId("travel-prompt");
	await page.keyboard.down("w");
	await page.waitForTimeout(700);
	await page.keyboard.down("d");
	try {
		await expect(prompt).toContainText("open the barn", { timeout: 15_000 });
	} finally {
		await page.keyboard.up("w");
		await page.keyboard.up("d");
	}
}

test("the barn stores a stack and returns it to the inventory", async ({
	page,
}) => {
	await registerFast(page, uniqueName("Storer"));

	await openBarn(page);
	const barnHotbar = page.getByTestId("barn-player-hotbar");
	// Shift-click any inventory stack to store it.
	await barnHotbar
		.getByTestId("slot-hotbar-1")
		.click({ modifiers: ["Shift"] });
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"seed-bag",
	);
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-count",
		"10",
	);
	await expect(page.getByTestId("barn-message")).toContainText("Stored 10");
	// The stored stack left the player's hotbar slot.
	await expect(barnHotbar.getByTestId("slot-hotbar-1")).toHaveAttribute(
		"data-item",
		"",
	);

	// Clicking a storage slot takes the stack back into the inventory.
	await page.getByTestId("barn-slot-0").click();
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute("data-item", "");
	await expect(page.getByTestId("barn-message")).toContainText("Took 10");
	await expect(barnHotbar.getByTestId("slot-hotbar-1")).toHaveAttribute(
		"data-item",
		"seed-bag",
	);

	// Escape closes the window.
	await page.keyboard.press("Escape");
	await expect(page.getByTestId("barn-window")).toHaveCount(0);
});

test("standing at the barn and pressing E opens storage", async ({ page }) => {
	await registerFast(page, uniqueName("Walker"));

	await walkToBarn(page);
	await page.keyboard.press("e");
	await expect(page.getByTestId("barn-window")).toBeVisible();

	// Escape closes it, and the prompt remains while still at the barn.
	await page.keyboard.press("Escape");
	await expect(page.getByTestId("barn-window")).toHaveCount(0);
	await expect(page.getByTestId("travel-prompt")).toContainText("open the barn");
});

test("barn storage survives a reload", async ({ page }) => {
	await registerFast(page, uniqueName("Keeper"));

	await openBarn(page);
	await page
		.getByTestId("barn-player-hotbar")
		.getByTestId("slot-hotbar-1")
		.click({ modifiers: ["Shift"] });
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"seed-bag",
	);

	// A fresh client still shows the server-held storage.
	await page.reload();
	await waitForWorld(page);
	await openBarn(page);
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"seed-bag",
	);
});

test("shift-click moves a stack from the grid and back out of storage", async ({
	page,
}) => {
	await registerFast(page, uniqueName("Shifter"));
	await openBarn(page);

	const playerGrid = page.getByTestId("barn-player-grid");
	const playerHotbar = page.getByTestId("barn-player-hotbar");
	const gridSlot = playerGrid.getByTestId("slot-grid-0");

	// Split half the seed stack into the first grid slot.
	await playerHotbar
		.getByTestId("slot-hotbar-1")
		.click({ button: "right" });
	await expect(gridSlot).toHaveAttribute("data-item", "seed-bag");
	await expect(gridSlot).toHaveAttribute("data-count", "5");

	// A grid stack shift-clicks into storage just like a hotbar stack.
	await gridSlot.click({ modifiers: ["Shift"] });
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"seed-bag",
	);
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-count",
		"5",
	);
	await expect(gridSlot).toHaveAttribute("data-item", "");

	// Shift-clicking storage takes it back (and tops up the existing pile).
	await page.getByTestId("barn-slot-0").click({ modifiers: ["Shift"] });
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"",
	);
	await expect(playerHotbar.getByTestId("slot-hotbar-1")).toHaveAttribute(
		"data-count",
		"10",
	);
});

test("deposited produce is not mirrored back into the inventory", async ({
	page,
}) => {
	await registerFast(page, uniqueName("Harvester"));

	// Stock the barn through the dev hook; the owner's inventory mirrors it.
	const seeded = await page.request.post(`${BASE}/api/dev/npc`, {
		data: { barn: { tomato: 5 } },
	});
	expect(seeded.ok(), await seeded.text()).toBe(true);

	// The produce lands in the first free hotbar slot (index 8, key 9).
	const hudTomato = page.getByTestId("slot-hotbar-8");
	await expect(hudTomato).toHaveAttribute("data-item", "tomato");
	await expect(hudTomato).toHaveAttribute("data-count", "5");

	await openBarn(page);
	await page
		.getByTestId("barn-player-hotbar")
		.getByTestId("slot-hotbar-8")
		.click({ modifiers: ["Shift"] });

	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"tomato",
	);
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-count",
		"5",
	);

	// The farm broadcast used to re-add the deposited stack to the hotbar.
	await page.waitForTimeout(500);
	const playerHotbar = page.getByTestId("barn-player-hotbar");
	await expect(playerHotbar.getByTestId("slot-hotbar-8")).toHaveAttribute(
		"data-item",
		"",
	);

	// A reload must not resurrect it from the barn ledger either.
	await page.reload();
	await waitForWorld(page);
	await openBarn(page);
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"tomato",
	);
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-count",
		"5",
	);
	await expect(playerHotbar.getByTestId("slot-hotbar-8")).toHaveAttribute(
		"data-item",
		"",
	);

	// Taking it back restores exactly one stack, not two.
	await page.getByTestId("barn-slot-0").click();
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"",
	);
	await expect(playerHotbar.getByTestId("slot-hotbar-8")).toHaveAttribute(
		"data-item",
		"tomato",
	);
	await expect(playerHotbar.getByTestId("slot-hotbar-8")).toHaveAttribute(
		"data-count",
		"5",
	);
});
