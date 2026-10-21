import { describe, expect, test } from "bun:test"
import { panelGeometry, panelTracks, STACKED_STRIP_HEIGHT } from "../../web/src/lib/panel"

describe("panel geometry", () => {
  test("sizes a lesson card from its 16:9 poster so nothing is cropped sideways", () => {
    const height = 400
    const poster = (height - 8) / 2 - 44
    const geometry = panelGeometry(height, 11)
    expect(geometry.lessonWidth).toBe(Math.ceil(poster * (16 / 9)) + 2)
    expect(geometry.infoWidth).toBeGreaterThanOrEqual(188)
    expect(geometry.infoWidth).toBeLessThanOrEqual(220)
  })

  test("adds one lesson column per two lessons", () => {
    const one = panelGeometry(400, 1)
    const two = panelGeometry(400, 2)
    const three = panelGeometry(400, 3)
    expect(two.contentWidth).toBe(one.contentWidth)
    expect(three.contentWidth).toBe(one.contentWidth + one.lessonWidth + 8)
  })

  test("falls back to a default card before the open card is measured", () => {
    const geometry = panelGeometry(0, 4)
    expect(geometry.lessonWidth).toBe(168)
    expect(geometry.stripHeight).toBe(0)
  })

  test("the stacked strip keeps a readable height of its own", () => {
    expect(panelGeometry(STACKED_STRIP_HEIGHT, 4).stripHeight).toBe(STACKED_STRIP_HEIGHT)
  })
})

describe("panel tracks", () => {
  test("grows with the content, capped by the room left in the row", () => {
    expect(panelTracks(2262, 238, 10, 3, 4)).toBe(4)
    expect(panelTracks(2262, 238, 10, 3, 6)).toBe(6)
  })

  test("never drops below the minimum that shows a whole lesson card", () => {
    expect(panelTracks(300, 238, 10, 3, 5)).toBe(3)
  })

  test("a row with less room than the minimum yields the room, which stacks the panel", () => {
    expect(panelTracks(2262, 238, 10, 3, 2)).toBe(2)
  })

  test("an unmeasured grid falls back to the minimum", () => {
    expect(panelTracks(2262, 0, 0, 3, 5)).toBe(3)
  })
})
