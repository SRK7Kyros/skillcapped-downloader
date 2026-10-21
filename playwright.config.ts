import { defineConfig, devices } from "@playwright/test"

const PORT = 4781

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 60_000,
  expect: { timeout: 20_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [["list"]],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    trace: "off",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
  webServer: {
    command: `bun run src/index.ts --no-open --port ${PORT} --content-dir .e2e-content`,
    url: `http://127.0.0.1:${PORT}/api/meta`,
    reuseExistingServer: true,
    timeout: 30_000,
    stdout: "ignore",
  },
})
