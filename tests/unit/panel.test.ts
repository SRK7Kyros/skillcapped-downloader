import { describe, expect, test } from "bun:test"
import { panelGeometry, panelTracks, stripHeightFor, STACKED_STRIP_HEIGHT } from "../../web/src/lib/panel"

describe("panel geometry", () => {
  test("sizes a lesson card from its 16:9 poster so nothing is cropped sideways", () => {
    const strip = 400
    const poster = (strip - 8) / 2 - 44
    expect(panelGeometry(strip, 11).lessonWidth).toBe(Math.ceil(poster * (16 / 9)) + 2)
  })

  test("adds one lesson column per two lessons", () => {
    const one = panelGeometry(400, 1)
    const two = panelGeometry(400, 2)
    const three = panelGeometry(400, 3)
    expect(two.contentWidth).toBe(one.contentWidth)
    expect(three.contentWidth).toBe(one.contentWidth + one.lessonWidth + 8)
  })

  test("the panel's own padding is part of the width it needs", () => {
    const geometry = panelGeometry(400, 1)
    expect(geometry.contentWidth).toBe(16 + geometry.lessonWidth)
  })

  test("falls back to a default card width before the open card is measured", () => {
    expect(panelGeometry(0, 4).lessonWidth).toBe(168)
    expect(panelGeometry(0, 4).stripHeight).toBe(0)
  })
})

describe("strip height", () => {
  test("an attached panel gives its padding back", () => {
    expect(stripHeightFor(400, true)).toBe(384)
  })

  test("an unmeasured card and a stacked panel both take the fixed height", () => {
    expect(stripHeightFor(0, true)).toBe(STACKED_STRIP_HEIGHT)
    expect(stripHeightFor(400, false)).toBe(STACKED_STRIP_HEIGHT)
  })
})

describe("panel tracks", () => {
  test("grows with the content, capped by the room left in the row", () => {
    expect(panelTracks(2262, 238, 10, 2, 4)).toBe(4)
    expect(panelTracks(2262, 238, 10, 2, 6)).toBe(6)
  })

  test("never drops below the minimum that shows a whole lesson card", () => {
    expect(panelTracks(300, 238, 10, 2, 5)).toBe(2)
  })

  test("a row with less room than the minimum yields the room, which stacks the panel", () => {
    expect(panelTracks(2262, 238, 10, 2, 1)).toBe(1)
  })

  test("an unmeasured grid falls back to the minimum", () => {
    expect(panelTracks(2262, 0, 0, 2, 5)).toBe(2)
  })
})
