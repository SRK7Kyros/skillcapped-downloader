import { expect, test } from "@playwright/test"
import fs from "node:fs/promises"
import path from "node:path"

const CONTENT = path.join(process.cwd(), ".e2e-content")
const FOLDER = path.join(CONTENT, "Preview Course")
const FILE = path.join(FOLDER, "On disk lesson [pv1ewl0cal] 1080p.mp4")
const UUID = "pv1ewl0cal"
const BYTES = Buffer.from(Array.from({ length: 64 }, (_, index) => index))

test.beforeAll(async () => {
  await fs.mkdir(FOLDER, { recursive: true })
  await fs.writeFile(FILE, BYTES)
})

test.afterAll(async () => {
  await fs.rm(FOLDER, { recursive: true, force: true })
})

test.describe("preview source", () => {
  test("a downloaded video previews from disk, not from the CDN", async ({ request }) => {
    const response = await request.get(`/api/preview/${UUID}?quality=2500&dur=600`)
    expect(response.status()).toBe(200)
    const plan = await response.json()
    expect(plan.mode).toBe("local")
    expect(plan.label).toBe("1080p")
    expect(plan.url).toBe(`/api/media/${UUID}?quality=1080p`)
  })

  test("a video that was never downloaded streams from the CDN", async ({ request }) => {
    const response = await request.get("/api/preview/zzzz999999?quality=1500&dur=600")
    const plan = await response.json()
    expect(plan.mode).toBe("remote")
    expect(plan.url).toBe("/api/stream/zzzz999999.m3u8?quality=1500&dur=600")
  })
})

test.describe("media route", () => {
  test("serves the file with byte ranges so the player can seek", async ({ request }) => {
    const response = await request.get(`/api/media/${UUID}?quality=1080p`, { headers: { range: "bytes=0-9" } })
    expect(response.status()).toBe(206)
    expect(response.headers()["content-range"]).toBe(`bytes 0-9/${BYTES.length}`)
    expect(response.headers()["content-length"]).toBe("10")
    expect(response.headers()["accept-ranges"]).toBe("bytes")
    expect(Buffer.from(await response.body())).toEqual(BYTES.subarray(0, 10))
  })

  test("serves the whole file when no range is asked for", async ({ request }) => {
    const response = await request.get(`/api/media/${UUID}`)
    expect(response.status()).toBe(200)
    expect(response.headers()["content-type"]).toBe("video/mp4")
    expect(Buffer.from(await response.body())).toEqual(BYTES)
  })

  test("answers an unsatisfiable range with 416 and the file size", async ({ request }) => {
    const response = await request.get(`/api/media/${UUID}`, { headers: { range: "bytes=9999-" } })
    expect(response.status()).toBe(416)
    expect(response.headers()["content-range"]).toBe(`bytes */${BYTES.length}`)
  })

  test("refuses a uuid that is not in the library", async ({ request }) => {
    const response = await request.get("/api/media/..%2F..%2Fetc%2Fpasswd")
    expect(response.status()).toBe(404)
  })
})

test.describe("preview player", () => {
  test("plays the card's video from disk once the file is there", async ({ page, request }) => {
    const catalog = (await (await request.get("/api/catalog")).json()) as {
      items: Array<{ id: string; title: string; kind: string }>
    }
    const video = catalog.items.find((item) => item.kind === "video" && /^[\w\s'-]+$/.test(item.title))
    expect(video).toBeTruthy()
    if (!video) return

    const token = video.title
      .split(/\s+/)
      .filter((word) => word.length >= 5)
      .sort((a, b) => b.length - a.length)[0]
    await fs.writeFile(path.join(FOLDER, `${video.title} [${video.id}] 1080p.mp4`), BYTES)

    await page.goto("/")
    await expect(page.locator("article").first()).toBeVisible()
    await page.getByRole("tab", { name: "Videos" }).click()
    await page.getByPlaceholder(/Search/).fill(token)

    const card = page.locator("article").filter({ hasText: video.title }).first()
    await expect(card).toBeVisible()
    await card.getByRole("button", { name: /^Preview / }).click()

    const dialog = page.locator("[role='dialog']")
    await expect(dialog.getByText(/From disk/)).toBeVisible()
    await expect(dialog.getByLabel("Preview quality")).toHaveCount(0)

    await page.keyboard.press("Escape")
    await expect(dialog).toHaveCount(0)
  })
})
