/**
 * Local-server hardening. The app writes files to disk, so it binds loopback
 * and refuses to act on requests that did not come from the page it served.
 */

const ALLOWED_HOSTNAMES = new Set(["localhost", "127.0.0.1", "[::1]", "::1"])

/** Block DNS-rebinding: a foreign name resolving to 127.0.0.1 must not pass. */
export function hostAllowed(hostHeader: string | null, port: number): boolean {
  if (!hostHeader) return true
  const host = hostHeader.trim().toLowerCase()
  const withoutPort = host.startsWith("[")
    ? host.slice(0, host.indexOf("]") + 1)
    : host.replace(/:\d+$/, "")
  if (!ALLOWED_HOSTNAMES.has(withoutPort)) return false
  const declaredPort = host.match(/:(\d+)$/)?.[1]
  return declaredPort === undefined || Number(declaredPort) === port
}

/**
 * Returns a response when the request must be rejected, otherwise null.
 * Cross-site initiations are refused for anything that mutates state.
 */
export function rejectForeignRequest(request: Request, port: number): Response | null {
  if (!hostAllowed(request.headers.get("host"), port)) {
    return json({ error: "Request host is not allowed." }, 403)
  }

  const method = request.method.toUpperCase()
  if (method === "GET" || method === "HEAD" || method === "OPTIONS") return null

  const site = request.headers.get("sec-fetch-site")
  if (site && site !== "same-origin" && site !== "none") {
    return json({ error: "Cross-site requests are not accepted." }, 403)
  }
  return null
}

export function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  })
}
