/**
 * Token-anchored ranking for the local filter box.
 *
 * The catalogue is 6,000+ titles, so a plain substring test is not enough:
 * "euro" should find "Eurosport", "zyra" should find titles where the word
 * appears mid-string, and a single typo should not empty the list. Every query
 * word is scored against every haystack word, and a result must answer *all*
 * query words — unless nothing does, in which case the best partial matches are
 * shown rather than a blank page.
 */

const LOOKALIKE: Record<string, string> = { "1": "l", l: "1", "0": "o", o: "0", "|": "l", i: "1" }

export function fold(input: string): string {
  return input
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[’'`]/g, "")
}

export function tokenize(input: string): string[] {
  return fold(input)
    .split(/[^a-z0-9]+/)
    .filter(Boolean)
}

function foldLookalikes(token: string): string {
  let out = ""
  for (const char of token) out += LOOKALIKE[char] ?? char
  return out
}

/** Damerau-Levenshtein with an early exit once the budget is exceeded. */
export function editDistance(a: string, b: string, max: number): number {
  if (a === b) return 0
  if (Math.abs(a.length - b.length) > max) return max + 1
  const previous: number[] = []
  const current: number[] = []
  for (let i = 0; i <= b.length; i += 1) previous[i] = i
  for (let i = 1; i <= a.length; i += 1) {
    current[0] = i
    let best = current[0]
    for (let j = 1; j <= b.length; j += 1) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      current[j] = Math.min(current[j - 1] + 1, previous[j] + 1, previous[j - 1] + cost)
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        current[j] = Math.min(current[j], previous[j - 2] + 1)
      }
      best = Math.min(best, current[j])
    }
    if (best > max) return max + 1
    for (let j = 0; j <= b.length; j += 1) previous[j] = current[j]
  }
  return previous[b.length]
}

function budgetFor(length: number): number {
  if (length <= 2) return 0
  if (length <= 5) return 1
  return 2
}

/** How well one query word matches one haystack word: 0 (no relation) → 1 (identical). */
function wordRelation(query: string, word: string): number {
  if (query === word) return 1
  if (word.startsWith(query)) return 0.9 + 0.1 * (query.length / word.length)
  if (query.length >= 3 && word.includes(query)) return 0.6 + 0.4 * (query.length / word.length)

  const folded = foldLookalikes(query)
  if (folded !== query && word === folded) return 0.95

  const budget = budgetFor(query.length)
  if (budget === 0) return 0
  const distance = editDistance(query, word, budget)
  if (distance > budget) return 0
  return 0.9 * (1 - distance / Math.max(query.length, word.length))
}

function scoreTokens(queryWords: string[], haystackWords: string[]): { matched: number; score: number } {
  let matched = 0
  let total = 0
  for (const query of queryWords) {
    let best = 0
    for (const word of haystackWords) {
      const relation = wordRelation(query, word)
      if (relation > best) best = relation
      if (best === 1) break
    }
    if (best > 0) matched += 1
    total += best
  }
  return { matched, score: queryWords.length ? total / queryWords.length : 0 }
}

export type RankedCounts = { matched: number; score: number }

/**
 * Ranking order: how many query words were answered, then the mean relation,
 * then the shorter title, then original order.
 */
export function rankItems<T>(items: T[], query: string, toText: (item: T) => string): T[] {
  const queryWords = tokenize(query)
  if (!queryWords.length) return items

  type Scored = { item: T; matched: number; score: number; length: number; index: number }
  const scored: Scored[] = []

  items.forEach((item, index) => {
    const text = toText(item)
    const haystackWords = tokenize(text)
    const { matched, score } = scoreTokens(queryWords, haystackWords)
    if (matched > 0) scored.push({ item, matched, score, length: text.length, index })
  })

  const complete = scored.filter((candidate) => candidate.matched === queryWords.length)
  const pool = complete.length ? complete : scored

  return pool
    .sort((left, right) => right.score - left.score || left.length - right.length || left.index - right.index)
    .map((candidate) => candidate.item)
}

export function matchesQuery(query: string, text: string): boolean {
  const queryWords = tokenize(query)
  if (!queryWords.length) return true
  const haystackWords = tokenize(text)
  return queryWords.every((word) => haystackWords.some((candidate) => wordRelation(word, candidate) > 0))
}
