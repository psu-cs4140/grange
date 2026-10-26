import { expect, test, type Page } from "@playwright/test";
import { register, resetServer, uniqueName, waitForWorld } from "./helpers";

/** Where the barn's sprite sits on the farm map (bottom-anchored). */
const BARN = { x: 935, y: 200 };

/** Clicks a world point on the farm canvas, like farm.spec.ts does. */
async function clickWorld(page: Page, worldX: number, worldY: number) {
	const box = await page.locator(".farm-map-canvas").boundingBox();
	expect(box).not.toBeNull();
	await page.mouse.click(
		box!.x + (worldX / 1152) * box!.width,
		box!.y + (worldY / 768) * box!.height,
	);
}

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
	const hint = page.getByTestId("farm-hint");
	await page.keyboard.down("w");
	await page.waitForTimeout(700);
	await page.keyboard.down("d");
	try {
		await expect(hint).toContainText("open the barn", { timeout: 15_000 });
	} finally {
		await page.keyboard.up("w");
		await page.keyboard.up("d");
	}
}

test("the barn stores a stack and returns it to the inventory", async ({
	page,
}) => {
	await resetServer();
	await register(page, uniqueName("Storer"));

	await openBarn(page);
	// The opening hotbar holds 10 seeds; the slot's Store button moves them.
	await page.getByTestId("barn-store-hotbar-1").click();
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-item",
		"seed-bag",
	);
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute(
		"data-count",
		"10",
	);
	await expect(page.getByTestId("barn-message")).toContainText("Stored 10");
	// The stored stack left the player slot, so its Store button is gone.
	await expect(page.getByTestId("barn-store-hotbar-1")).toHaveCount(0);

	// Clicking a storage slot takes the stack back into the inventory.
	await page.getByTestId("barn-slot-0").click();
	await expect(page.getByTestId("barn-slot-0")).toHaveAttribute("data-item", "");
	await expect(page.getByTestId("barn-message")).toContainText("Took 10");
	await expect(page.getByTestId("barn-store-hotbar-1")).toBeVisible();

	// Escape closes the window.
	await page.keyboard.press("Escape");
	await expect(page.getByTestId("barn-window")).toHaveCount(0);
});

test("standing at the barn and pressing E opens storage", async ({ page }) => {
	await resetServer();
	await register(page, uniqueName("Walker"));

	await walkToBarn(page);
	await page.keyboard.press("e");
	await expect(page.getByTestId("barn-window")).toBeVisible();

	// Escape closes it, and the hint returns while still standing at the barn.
	await page.keyboard.press("Escape");
	await expect(page.getByTestId("barn-window")).toHaveCount(0);
	await expect(page.getByTestId("farm-hint")).toContainText("open the barn");
});

test("barn storage survives a reload", async ({ page }) => {
	await resetServer();
	await register(page, uniqueName("Keeper"));

	await openBarn(page);
	await page.getByTestId("barn-store-hotbar-1").click();
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
