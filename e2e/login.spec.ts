import { expect, test } from "@playwright/test";

test("entering a username opens the farm map", async ({ page }) => {
	await page.goto("/");

	await page
		.getByRole("textbox", { name: "Username" })
		.fill(`farmer-${Date.now()}`);
	await page.getByRole("button", { name: "Enter Farm" }).click();

	await expect(page).toHaveURL(/\/world$/);
	await expect(page.locator("canvas[aria-label^='Farm map']")).toBeVisible();
});

test("an empty username stays on the login screen", async ({ page }) => {
	await page.goto("/");

	await page.getByRole("button", { name: "Enter Farm" }).click();

	await expect(page).toHaveURL(/\/$/);
	await expect(page.getByRole("textbox", { name: "Username" })).toBeVisible();
});
