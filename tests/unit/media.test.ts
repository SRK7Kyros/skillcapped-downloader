import { describe, expect, test } from "bun:test"
import { posterRatio } from "../../web/src/lib/media.ts"

describe("posterRatio", () => {
  test("reserves a portrait box for course banners, which ship as 576×912 cards", () => {
    expect(posterRatio("course")).toBe("576 / 912")
  })

  test("reserves a 16:9 box for video and smurf stills", () => {
    expect(posterRatio("video")).toBe("16 / 9")
    expect(posterRatio("commentary")).toBe("16 / 9")
  })

  test("every kind names one window a grid can rely on", () => {
    const shape = (kind: Parameters<typeof posterRatio>[0]) => {
      const [width, height] = posterRatio(kind).split(" / ").map(Number)
      return width / height
    }
    expect(shape("course")).toBeLessThan(1)
    expect(shape("video")).toBeGreaterThan(1)
    expect(shape("commentary")).toBeGreaterThan(1)
  })
})
