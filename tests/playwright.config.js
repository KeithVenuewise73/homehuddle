// Playwright config for Venuewise Core smoke tests.
// Read-only suite; safe against production. Override the target with BASE_URL.
const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './smoke',
  timeout: 45000,
  retries: 1,                 // tolerate a single transient network blip before failing
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.BASE_URL || 'https://venuewise.net',
    headless: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile',   use: { ...devices['Pixel 5'] } },   // HomeHuddle is phone-first
  ],
});
