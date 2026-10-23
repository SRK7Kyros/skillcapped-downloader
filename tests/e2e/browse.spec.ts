import { expect, test } from "@playwright/test"

const PAGE_SIZE = 60

const showVideos = async (page: import("@playwright/test").Page) => {
  await page.getByRole("tab", { name: "Videos" }).click()
  await expect(page.getByRole("tab", { name: "Videos" })).toHaveAttribute("aria-selected", "true")
}

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

    await expect(page.getByText(/\d+ of [\d,]+/).first()).toBeVisible()
    expect(errors).toEqual([])
  })

  test("opens on courses, with no catch-all tab", async ({ page }) => {
    await page.goto("/")
    await expect(page.getByRole("tab", { name: "Courses" })).toHaveAttribute("aria-selected", "true")
    await expect(page.getByRole("tab", { name: /^All$/ })).toHaveCount(0)
    await expect(page.locator("article").first()).toBeVisible()
    await expect(page.locator("article").first()).toContainText(/lessons|not published/i)
  })

  test("ranks the obvious match first", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    await page.getByPlaceholder(/Search/).fill("wave control")
    await expect(page.locator("article").first()).toContainText(/wave control/i)

    await showVideos(page)
    await page.getByPlaceholder(/Search/).fill("gankng mechanics")
    await expect(page.locator("article").first()).toContainText(/ganking mechanics/i)

    await page.getByPlaceholder(/Search/).fill("zzzqqq")
    await expect(page.locator("article")).toHaveCount(0)
  })

  test("selects with the checkbox and toggles from the card body", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()
    await showVideos(page)

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
    await showVideos(page)

    const cards = page.locator("article")
    await cards.nth(0).locator("button[aria-pressed]").click()
    await cards.nth(3).locator("h3").click({ modifiers: ["Shift"] })
    await expect(page.getByText(/4 selected/).first()).toBeVisible()
  })

  test("opens a preview player for a video", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()
    await showVideos(page)

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

  test("a course card shows its banner, title and release date", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    await page.getByRole("tab", { name: "Courses" }).click()
    const card = page.locator("article").first()
    await expect(card.locator("h3")).not.toBeEmpty()
    await expect(card.locator("img")).toHaveAttribute("src", /skill-capped/)

    const footer = card.locator("div").last()
    await expect(footer).toContainText(/\d{4}/)
    await expect(footer).toContainText(/\b(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)/)
    await expect(footer).not.toContainText(/tags/i)
    await expect(card.getByText(/^\d+ lessons$/)).toHaveCount(1)

    // The banner is portrait art (576×912, title baked into the top). A 16:9 box with
    // object-cover threw the title and two thirds of the picture away; the card must
    // now take the poster's own shape.
    const shapeOf = `(() => {
      const img = document.querySelectorAll("article img")[0]
      const rect = img.getBoundingClientRect()
      return {
        naturalWidth: img.naturalWidth,
        naturalHeight: img.naturalHeight,
        width: rect.width,
        height: rect.height,
      }
    })()`

    await expect
      .poll(
        async () => {
          const shape = (await page.evaluate(shapeOf)) as { width: number; height: number; naturalWidth: number; naturalHeight: number }
          return Number(Math.abs(shape.height / shape.width - shape.naturalHeight / shape.naturalWidth).toFixed(4))
        },
        { timeout: 5000, message: "the card must keep the poster's own shape" },
      )
      .toBeLessThan(0.02)
  })

  test("gives every card in a row the same height", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()

    const unevenRows = () =>
      page.evaluate(`(() => {
        const rows = new Map()
        for (const card of [...document.querySelectorAll("article")].slice(0, 24)) {
          const rect = card.getBoundingClientRect()
          const key = Math.round(rect.top)
          if (!rows.has(key)) rows.set(key, new Set())
          rows.get(key).add(Math.round(rect.height))
        }
        return [...rows.values()].filter((heights) => heights.size > 1).length
      })()`) as Promise<number>

    await expect.poll(unevenRows, { timeout: 10_000 }).toBe(0)
    await showVideos(page)
    await expect.poll(unevenRows, { timeout: 10_000 }).toBe(0)
  })

  test("a poster that is taller than the window loses its bottom, not its row", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()
    await page.waitForTimeout(600)

    const taller = await page.evaluate(`(() => {
      const canvas = document.createElement("canvas")
      canvas.width = 576
      canvas.height = 1000
      const paint = canvas.getContext("2d")
      paint.fillStyle = "#202027"
      paint.fillRect(0, 0, 576, 1000)
      paint.fillStyle = "#e8412c"
      paint.fillRect(0, 0, 576, 40)
      paint.fillStyle = "#2b6cff"
      paint.fillRect(0, 960, 576, 40)
      return canvas.toDataURL("image/png")
    })()`) as string

    await page.evaluate(`(() => {
      const card = document.querySelector("article")
      const img = card.querySelector("img")
      if (img) img.src = ${JSON.stringify(taller)}
    })()`)

    const shape = (await page.evaluate(`(() => {
      const cards = [...document.querySelectorAll("article")].slice(0, 6)
      const rect = cards[0].getBoundingClientRect()
      const art = cards[0].firstElementChild.getBoundingClientRect()
      const neighbours = cards.slice(1).map((card) => Math.round(card.getBoundingClientRect().height))
      return { card: Math.round(rect.height), art: Math.round(art.height), width: Math.round(art.width), neighbours }
    })()`)) as { card: number; art: number; width: number; neighbours: number[] }

    expect(shape.neighbours.every((height) => height === shape.card), "the taller poster must not make its card taller").toBe(true)
    expect(shape.art / shape.width, "the box keeps the window's 576:912 shape").toBeCloseTo(912 / 576, 1)
  })

  test("the taller poster keeps the top of the art and crops the bottom", async ({ page }) => {
    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()
    await page.waitForTimeout(600)

    const band = await page.evaluate(`(() => {
      const canvas = document.createElement("canvas")
      canvas.width = 576
      canvas.height = 1000
      const paint = canvas.getContext("2d")
      paint.fillStyle = "#202027"
      paint.fillRect(0, 0, 576, 1000)
      paint.fillStyle = "#e8412c"
      paint.fillRect(0, 0, 576, 40)
      paint.fillStyle = "#2b6cff"
      paint.fillRect(0, 960, 576, 40)
      return canvas.toDataURL("image/png")
    })()`) as string

    await page.evaluate(`(() => {
      const img = document.querySelector("article img")
      if (img) img.src = ${JSON.stringify(band)}
    })()`)
    await page.mouse.move(1278, 700)
    await expect
      .poll(
        async () =>
          (await page.evaluate("(() => document.querySelector('article img').naturalWidth)()")) as number,
        { timeout: 5000 },
      )
      .toBe(576)
    await page.waitForTimeout(300)

    const shot = (await page.locator("article").first().screenshot()).toString("base64")
    const sample = (await page.evaluate(`(async () => {
      const art = document.querySelector("article").firstElementChild.getBoundingClientRect()
      const picture = new Image()
      picture.src = "data:image/png;base64," + ${JSON.stringify(shot)}
      await picture.decode()
      const canvas = document.createElement("canvas")
      canvas.width = picture.width
      canvas.height = picture.height
      const paint = canvas.getContext("2d")
      paint.drawImage(picture, 0, 0)
      const read = (y) => [...paint.getImageData(Math.round(art.width / 2), Math.round(y), 1, 1).data].slice(0, 3)
      return { top: read(6), lower: read(art.height - 70) }
    })()`)) as { top: number[]; lower: number[] }

    expect(sample.top[0], "the red band at the top of the art is still shown").toBeGreaterThan(150)
    expect(sample.lower[2], "the art's own bottom band never reaches the box").toBeLessThan(120)
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
