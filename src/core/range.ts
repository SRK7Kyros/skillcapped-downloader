/**
 * Byte ranges for the media route. A preview scrubs, so the server has to
 * answer `Range:` with a 206 or the browser refuses to seek — and iOS Safari
 * refuses to play a file at all without it.
 */

export type ByteRange = { start: number; end: number }

/**
 * - `null` — serve the whole file (no header, or something we do not parse)
 * - `"unsatisfiable"` — a syntactically valid range outside the file (416)
 * - `{start, end}` — inclusive bounds, already clamped to the file
 *
 * Multi-range requests (`bytes=0-1,5-6`) are deliberately answered in full:
 * the browser only ever asks for one range here, and a full 200 is always a
 * correct response to a range request.
 */
export function parseByteRange(header: string | null, size: number): ByteRange | "unsatisfiable" | null {
  if (!header || size <= 0) return null

  const match = /^bytes=(\d*)-(\d*)$/.exec(header.trim())
  if (!match) return null

  const [, rawStart, rawEnd] = match
  if (!rawStart && !rawEnd) return null

  if (!rawStart) {
    // Suffix form: the last N bytes.
    const length = Number(rawEnd)
    if (!Number.isFinite(length) || length <= 0) return "unsatisfiable"
    return { start: Math.max(0, size - length), end: size - 1 }
  }

  const start = Number(rawStart)
  if (!Number.isFinite(start) || start >= size) return "unsatisfiable"

  const end = rawEnd ? Number(rawEnd) : size - 1
  if (!Number.isFinite(end) || end < start) return "unsatisfiable"

  return { start, end: Math.min(end, size - 1) }
}

/** `Content-Range` value for a 206. */
export function contentRange(range: ByteRange, size: number): string {
  return `bytes ${range.start}-${range.end}/${size}`
}
