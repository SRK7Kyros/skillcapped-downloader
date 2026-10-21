import { describe, expect, test } from "bun:test"
import { isEmbeddedDir } from "../../src/paths.ts"

describe("isEmbeddedDir", () => {
  test("recognises Bun's POSIX embedded root", () => {
    expect(isEmbeddedDir("/$bunfs/root")).toBe(true)
    expect(isEmbeddedDir("/$bunfs")).toBe(true)
  })

  test("recognises Bun's Windows embedded drive, which a POSIX-only check missed", () => {
    expect(isEmbeddedDir("B:\\~BUN\\root")).toBe(true)
    expect(isEmbeddedDir("b:/~bun")).toBe(true)
  })

  test("leaves real folders alone", () => {
    expect(isEmbeddedDir("/home/opc/everything/kyros/code/skillcapped-downloader/src")).toBe(false)
    expect(isEmbeddedDir("D:\\Code\\skillcapped-downloader")).toBe(false)
    expect(isEmbeddedDir("C:/Users/Giulio")).toBe(false)
    expect(isEmbeddedDir("")).toBe(false)
  })
})
