import { describe, expect, test } from "bun:test"
import { contentRange, parseByteRange } from "../../src/core/range.ts"

describe("parseByteRange", () => {
  test("serves the whole file when the header is absent", () => {
    expect(parseByteRange(null, 1000)).toBeNull()
  })

  test("answers the ordinary browser range", () => {
    expect(parseByteRange("bytes=0-1023", 4096)).toEqual({ start: 0, end: 1023 })
  })

  test("an open end runs to the last byte", () => {
    expect(parseByteRange("bytes=4000-", 4096)).toEqual({ start: 4000, end: 4095 })
  })

  test("clamps an end past the file instead of failing", () => {
    expect(parseByteRange("bytes=4000-99999", 4096)).toEqual({ start: 4000, end: 4095 })
  })

  test("reads the suffix form as the last N bytes", () => {
    expect(parseByteRange("bytes=-500", 4096)).toEqual({ start: 3596, end: 4095 })
    expect(parseByteRange("bytes=-99999", 4096)).toEqual({ start: 0, end: 4095 })
  })

  test("rejects a start at or past the end", () => {
    expect(parseByteRange("bytes=4096-", 4096)).toBe("unsatisfiable")
    expect(parseByteRange("bytes=9000-9100", 4096)).toBe("unsatisfiable")
  })

  test("rejects a backwards or empty suffix range", () => {
    expect(parseByteRange("bytes=900-100", 4096)).toBe("unsatisfiable")
    expect(parseByteRange("bytes=-0", 4096)).toBe("unsatisfiable")
  })

  test("falls back to the whole file for a multi-range or garbage header", () => {
    expect(parseByteRange("bytes=0-1,5-6", 4096)).toBeNull()
    expect(parseByteRange("items=0-1", 4096)).toBeNull()
    expect(parseByteRange("bytes=-", 4096)).toBeNull()
  })

  test("a zero-length file has nothing to range", () => {
    expect(parseByteRange("bytes=0-10", 0)).toBeNull()
  })
})

describe("contentRange", () => {
  test("reports inclusive bounds against the full size", () => {
    expect(contentRange({ start: 10, end: 19 }, 100)).toBe("bytes 10-19/100")
  })
})
