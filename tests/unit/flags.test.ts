import { describe, expect, test } from "bun:test"
import { DEFAULT_PORT, isQualityId, parseFlags } from "../../src/flags.ts"

describe("parseFlags", () => {
  test("defaults to loopback, the preferred rendition and browser launch", () => {
    const flags = parseFlags([], {})
    expect(flags.port).toBe(DEFAULT_PORT)
    expect(flags.port).toBe(4780)
    expect(flags.host).toBe("127.0.0.1")
    expect(flags.quality).toBe(2500)
    expect(flags.remux).toBe(true)
    expect(flags.openBrowser).toBe(true)
    expect(flags.concurrency).toBe(3)
    expect(flags.contentDir).toBeUndefined()
  })

  test("reads the long and short forms of each option", () => {
    expect(parseFlags(["--port", "9000"], {}).port).toBe(9000)
    expect(parseFlags(["-p", "9001"], {}).port).toBe(9001)
    expect(parseFlags(["-q", "4500"], {}).quality).toBe(4500)
    expect(parseFlags(["--quality", "1500"], {}).quality).toBe(1500)
    expect(parseFlags(["--concurrency", "2"], {}).concurrency).toBe(2)
    expect(parseFlags(["--content-dir", "/tmp/here"], {}).contentDir).toBe("/tmp/here")
    expect(parseFlags(["--host", "0.0.0.0"], {}).host).toBe("0.0.0.0")
  })

  test("turns remuxing and browser launch off", () => {
    expect(parseFlags(["--no-remux"], {}).remux).toBe(false)
    expect(parseFlags(["--no-open"], {}).openBrowser).toBe(false)
    expect(parseFlags(["--remux"], {}).remux).toBe(true)
  })

  test("falls back to the environment when there is no argument", () => {
    expect(parseFlags([], { PORT: "8123" }).port).toBe(8123)
    expect(parseFlags([], { SKILLCAPPED_QUALITY: "4500" }).quality).toBe(4500)
    expect(parseFlags([], { SKILLCAPPED_CONCURRENCY: "5" }).concurrency).toBe(5)
    expect(parseFlags([], { SKILLCAPPED_CONTENT_DIR: "/env/dir" }).contentDir).toBe("/env/dir")
    expect(parseFlags([], { SKILLCAPPED_REMUX: "0" }).remux).toBe(false)
    expect(parseFlags([], { SKILLCAPPED_NO_OPEN: "1" }).openBrowser).toBe(false)
  })

  test("lets an argument beat the environment", () => {
    expect(parseFlags(["--quality", "1500"], { SKILLCAPPED_QUALITY: "4500" }).quality).toBe(1500)
    expect(parseFlags(["--port", "9000"], { PORT: "8123" }).port).toBe(9000)
  })

  test("ignores junk instead of failing, because a double-click passes nothing", () => {
    const flags = parseFlags(["--nonsense", "value", "--port"], {})
    expect(flags.port).toBe(DEFAULT_PORT)
    expect(parseFlags(["--port", "not-a-number"], {}).port).toBe(DEFAULT_PORT)
    expect(parseFlags(["--port", "-5"], {}).port).toBe(DEFAULT_PORT)
    expect(parseFlags([], { PORT: "0" }).port).toBe(DEFAULT_PORT)
  })

  test("recognises only the three published renditions", () => {
    expect(isQualityId(1500)).toBe(true)
    expect(isQualityId(2500)).toBe(true)
    expect(isQualityId(4500)).toBe(true)
    expect(isQualityId(720)).toBe(false)
    expect(isQualityId(0)).toBe(false)
  })
})
