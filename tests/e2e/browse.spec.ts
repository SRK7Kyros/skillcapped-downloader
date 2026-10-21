import { expect, test } from "@playwright/test"

const PAGE_SIZE = 60

test.describe("browse", () => {
  test("renders the catalogue without console errors", async ({ page }) => {
    const errors: string[] = []
    page.on("console", (message) => {
      if (message.type() === "error") errors.push(message.text())
    })
    page.on("pageerror", (error) => errors.push(String(error)))

    await page.goto("/")
    await expect(page.getByText("SkillCapped Downloader").first()).toBeVisible()

    await expect.poll(async () => page.locator("article").count()).toBeGreaterThanOrEqual(PAGE_SIZE)

    const titles = await page.locator("article h3").allInnerTexts()
    expect(titles.length).toBeGreaterThan(0)
    expect(titles.filter((title) => /[{}]/.test(title))).toEqual([])

    await expect(page.getByText(/\d+ items/).first()).toBeVisible()
    expect(errors).toEqual([])
  })

  test("ranks the obvious match first", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    await page.getByPlaceholder(/Search/).fill("wave control")
    await expect(page.locator("article").first()).toContainText(/wave control/i)

    await page.getByPlaceholder(/Search/).fill("gankng mechanics")
    await expect(page.locator("article").first()).toContainText(/ganking mechanics/i)

    await page.getByPlaceholder(/Search/).fill("zzzqqq")
    await expect(page.locator("article")).toHaveCount(0)
  })

  test("selects with the checkbox and toggles from the card body", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    const card = page.locator("article").first()
    await card.locator("button[aria-pressed]").click()
    await expect(page.getByText(/1 selected/).first()).toBeVisible()
    await expect(card).toHaveAttribute("data-selected", "1")

    await card.locator("h3").click()
    await expect(page.getByText(/\d+ selected/)).toHaveCount(0)
  })

  test("shift-click extends the selection over the visible page", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    const cards = page.locator("article")
    await cards.nth(0).locator("button[aria-pressed]").click()
    await cards.nth(3).locator("h3").click({ modifiers: ["Shift"] })
    await expect(page.getByText(/4 selected/).first()).toBeVisible()
  })

  test("opens a preview player for a video", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    await page.getByRole("button", { name: /^Preview / }).first().click()
    const dialog = page.locator("[role='dialog']")
    await expect(dialog.locator("video")).toBeVisible()
    await page.keyboard.press("Escape")
    await expect(dialog).toHaveCount(0)
  })

  test("a course with no lessons cannot be selected", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    await page.getByPlaceholder(/Search/).fill("Master SETTINGS")
    const card = page.locator("article").first()
    await expect(card).toContainText(/no lessons yet/i)
    await expect(card.locator("button[aria-pressed]")).toBeDisabled()

    await card.locator("h3").click()
    await expect(page.getByText(/\d+ selected/)).toHaveCount(0)
  })

  test("fits the viewport at 375 and 768 without overflow", async ({ page }) => {
    for (const width of [375, 768]) {
      await page.setViewportSize({ width, height: 800 })
      await page.goto("/")
      await expect(page.locator("article").first()).toBeVisible()
      // A string expression, so the server tsconfig can stay DOM-free.
      const overflow = (await page.evaluate(
        "document.documentElement.scrollWidth - window.innerWidth",
      )) as number
      expect(overflow, `horizontal overflow at ${width}px`).toBeLessThanOrEqual(2)
    }
  })
})
