import { describe, expect, test } from "bun:test"
import { imageRatio, posterRatio } from "../../web/src/lib/media.ts"

describe("posterRatio", () => {
  test("reserves a portrait box for course banners, which ship as 576×912 cards", () => {
    expect(posterRatio("course")).toBe("2 / 3")
  })

  test("reserves a 16:9 box for video and smurf stills", () => {
    expect(posterRatio("video")).toBe("16 / 9")
    expect(posterRatio("commentary")).toBe("16 / 9")
  })
})

describe("imageRatio", () => {
  test("returns the poster's own shape so nothing is cropped away", () => {
    expect(imageRatio(576, 912)).toBe("576 / 912")
    expect(imageRatio(1280, 720)).toBe("1280 / 720")
  })

  test("refuses a shape it cannot use, leaving the caller's fallback in place", () => {
    expect(imageRatio(0, 912)).toBeNull()
    expect(imageRatio(576, 0)).toBeNull()
    expect(imageRatio(Number.NaN, 912)).toBeNull()
    expect(imageRatio(576, Number.POSITIVE_INFINITY)).toBeNull()
  })
})
