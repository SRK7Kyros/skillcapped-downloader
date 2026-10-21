import { describe, expect, test } from "bun:test"
import { fold, matchesQuery, rankItems, tokenize } from "../../web/src/lib/search.ts"

const titles = (query: string, items: string[]) => rankItems(items, query, (item) => item)

describe("fold and tokenize", () => {
  test("folds diacritics, case and apostrophes so accents and punctuation are searchable", () => {
    expect(fold("Café")).toBe("cafe")
    expect(fold("Kai'Sa")).toBe("kaisa")
    expect(fold("Kai\u2019Sa")).toBe("kaisa")
  })

  test("splits a title into alphanumeric words", () => {
    expect(tokenize("Wave Control {top}")).toEqual(["wave", "control", "top"])
    expect(tokenize("Emerald - Zyra w/ Jhin")).toEqual(["emerald", "zyra", "w", "jhin"])
  })
})

describe("rankItems", () => {
  test("returns the list untouched for an empty query", () => {
    const items = ["b", "a", "c"]
    expect(titles("", items)).toEqual(items)
  })

  test("finds a title from the start of a word", () => {
    expect(titles("euro", ["Sky Sports F1", "Eurosport 1"])).toContain("Eurosport 1")
  })

  test("finds a word in the middle of a title", () => {
    expect(titles("zyra", ["Emerald - Zyra w/ Jhin vs Caitlyn", "Random Video"])).toEqual([
      "Emerald - Zyra w/ Jhin vs Caitlyn",
    ])
  })

  test("ranks an exact title above a partial one", () => {
    expect(titles("wave control", ["Wave Control Guide", "Wave Control"])[0]).toBe("Wave Control")
  })

  test("survives one typo", () => {
    expect(titles("skilcaped", ["SkillCapped Guide"])).toContain("SkillCapped Guide")
  })

  test("does not admit everything for garbage input", () => {
    expect(titles("dfdfslfsfs", ["Sky Sports F1", "Eurosport 1", "Wave Control"])).toEqual([])
    expect(titles("zz", ["Sky Sports F1", "Eurosport 1"])).toEqual([])
  })

  test("requires every word of a two-word query rather than leaning on a common one", () => {
    expect(titles("sportklub 2", ["Sportklub 2", "Sportklub 10", "Sky Sport 3 NZ"])).toContain("Sportklub 2")
    expect(titles("sportklub 2", ["Sportklub 2", "Sky Sport 3 NZ"])).not.toContain("Sky Sport 3 NZ")
  })
})

describe("matchesQuery", () => {
  test("accepts a title that answers the query", () => {
    expect(matchesQuery("zyra", "Emerald - Zyra w/ Jhin")).toBe(true)
    expect(matchesQuery("wave control", "Chapter 1: Wave Control (Support)")).toBe(true)
  })

  test("rejects unrelated noise", () => {
    expect(matchesQuery("qq", "Sky Sports F1")).toBe(false)
    expect(matchesQuery("nba", "Sky Sports F1")).toBe(false)
  })
})
