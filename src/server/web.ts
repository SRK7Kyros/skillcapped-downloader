/**
 * Serving the built single-file web app. The bundle is compiled into the
 * executable, so there is no static directory to read at runtime — the whole
 * UI arrives as one embedded HTML string, gzipped once at startup.
 */

import htmlSource from "./web.html" with { type: "text" }

// Bun resolves a `type: "text"` import to the raw file contents; the ambient
// `*.html` module declaration types it as an HTMLBundle, so the string view is
// asserted here once instead of at every use.
const html = htmlSource as unknown as string

const encoded = new TextEncoder().encode(html)
const gzipped = Bun.gzipSync(encoded)
const etag = `"${Bun.hash(html).toString(36)}"`

export function appHtml(request: Request): Response {
  const headers: Record<string, string> = {
    "content-type": "text/html; charset=utf-8",
    "cache-control": "no-cache",
    etag,
  }

  if (request.headers.get("if-none-match") === etag) {
    return new Response(null, { status: 304, headers })
  }

  if (request.headers.get("accept-encoding")?.includes("gzip")) {
    return new Response(gzipped, { headers: { ...headers, "content-encoding": "gzip" } })
  }
  return new Response(html, { headers })
}

export const htmlBytes = encoded.byteLength
