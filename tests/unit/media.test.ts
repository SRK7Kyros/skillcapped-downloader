import { describe, expect, test } from "bun:test"
import { posterRatio } from "../../web/src/lib/media.ts"

describe("posterRatio", () => {
  test("reserves a portrait box for course banners, cropped above the card's dead black foot", () => {
    // The site's card is 576×912 with a ~10% pure-black strip printed along its
    // bottom; the window is that card with the strip cut off, so the art ends
    // where it looks like it ends.
    expect(posterRatio("course")).toBe("576 / 806")
  })

  test("the course window is shorter than the art it holds, so the dead foot is cropped", () => {
    const [width, height] = posterRatio("course").split(" / ").map(Number)
    expect(height).toBe(806)
    expect(width / height, "the window is a crop of the 576×912 card, never the card itself").toBeGreaterThan(576 / 912)
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
