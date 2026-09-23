import { defineConfig } from "@playwright/test";

export default defineConfig({
	testDir: "e2e",
	fullyParallel: false,
	workers: 1,
	timeout: 60_000,
	// Retry transient CI failures instead of letting one wedged test burn the
	// whole job's timeout.
	retries: process.env.CI ? 2 : 0,
	use: {
		baseURL: "http://localhost:3000",
		// Bound every navigation/action so a stalled browser request fails the
		// test in seconds rather than hanging until the job timeout.
		navigationTimeout: 30_000,
		actionTimeout: 15_000,
		launchOptions: {
			// GitHub runners have a small /dev/shm; Chromium can hang without
			// this.
			args: process.env.CI ? ["--disable-dev-shm-usage"] : [],
		},
	},
	webServer: {
		command: "pnpm dev",
		url: "http://localhost:3000",
		reuseExistingServer: true,
		env: { PORT: "3000" },
	},
});
