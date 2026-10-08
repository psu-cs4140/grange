import { expect, test } from "@playwright/test";
import { BASE, register, resetServer, uniqueName, waitForWorld } from "./helpers";

test("registering an account opens the farm map", async ({ page }) => {
	await resetServer();
	await register(page, uniqueName("Sprout"));

	await expect(page).toHaveURL(/\/world$/);
	await expect(page.locator("canvas[aria-label^='Farm map']")).toBeVisible();
});

test("signing in opens the farm map", async ({ page }) => {
	await resetServer();
	const name = uniqueName("Sprout");

	await page.goto(`${BASE}/login`);
	await page.getByTestId("toggle-mode").click();
	await page.getByTestId("username").fill(name);
	await page.getByTestId("email").fill(`${name}@example.test`);
	await page.getByTestId("password").fill("harvest-please");
	await page.getByRole("button", { name: /Create Account/i }).click();
	await page.waitForURL("**/world");
	await waitForWorld(page);

	await page.keyboard.press("Escape");
	await page.getByTestId("logout").click();
	await page.waitForURL("/");

	await page.getByTestId("menu-login").click();
	await page.waitForURL("**/login");
	await page.getByTestId("username").fill(name);
	await page.getByTestId("password").fill("harvest-please");
	await page.getByRole("button", { name: /Sign In/i }).click();

	await expect(page).toHaveURL(/\/world$/);
	await expect(page.locator("canvas[aria-label^='Farm map']")).toBeVisible();
});
