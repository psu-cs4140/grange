import type { Page } from "@playwright/test";

export const BASE = process.env.E2E_BASE_URL ?? "http://localhost:3201";

/** Unique suffix so tests don't collide with each other or prior runs. */
export function uniqueName(base: string): string {
	return `${base}-${Math.floor(Math.random() * 1e9)}`;
}

/** Resets the server's in-memory state so each test starts clean. */
export async function resetServer(): Promise<void> {
	await fetch(`${BASE}/api/reset`, { method: "POST" });
}

/**
 * Waits until the world route is actually interactive. The route renders
 * behind a session check, so the canvas/hotkeys come up a beat after the URL
 * changes.
 */
export async function waitForWorld(page: Page): Promise<void> {
	await page.locator("canvas.farm-map-canvas").waitFor({ state: "visible" });
	await page.waitForLoadState("networkidle");
}

/** Continues from the main menu into the farm and waits for it to be live. */
export async function enterFarm(page: Page): Promise<void> {
	await page.getByRole("button", { name: /Continue \/ Load Farm/i }).click();
	await page.waitForURL("**/world");
	await waitForWorld(page);
}

/**
 * Registers a fresh account and leaves the page on the main menu, signed in.
 * `/api/reset` wipes accounts too, so the username only has to be unique
 * within a test.
 */
export async function registerAccount(
	page: Page,
	username: string,
	password = "harvest-please",
): Promise<string> {
	await page.goto(`${BASE}/login`);
	await page.getByTestId("toggle-mode").click();
	await page.getByTestId("username").fill(username);
	await page.getByTestId("email").fill(`${username}@example.test`);
	await page.getByTestId("password").fill(password);
	await page.getByRole("button", { name: /Create Account/i }).click();
	await page.waitForURL(`${BASE}/`);
	await page.getByTestId("menu-user").waitFor();
	return username;
}

/**
 * Registers a fresh account and continues into the farm, leaving the page on
 * the farm map. Most tests start here.
 */
export async function register(
	page: Page,
	username: string,
	password = "harvest-please",
): Promise<string> {
	await registerAccount(page, username, password);
	await enterFarm(page);
	return username;
}

/** Registers an account then signs in, leaving the page on the farm map. */
export async function login(
	page: Page,
	username: string,
	password = "harvest-please",
): Promise<void> {
	await registerAccount(page, username, password);
	// Sign out from the menu, then sign back in from the login screen.
	await page.getByTestId("menu-logout").click();
	await page.getByTestId("menu-login").click();
	await page.waitForURL("**/login");
	await page.getByTestId("username").fill(username);
	await page.getByTestId("password").fill(password);
	await page.getByRole("button", { name: /Sign In/i }).click();
	await page.waitForURL(`${BASE}/`);
	await page.getByTestId("menu-user").waitFor();
	await enterFarm(page);
}
