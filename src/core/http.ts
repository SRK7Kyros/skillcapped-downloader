/**
 * Outbound HTTP: one retrying fetch and a concurrency limiter. Segment
 * fetches are the hot path, so they share a single polite budget.
 */

export class Semaphore {
  private inFlight = 0
  private waiting: Array<() => void> = []

  constructor(private readonly limit: number) {}

  async run<T>(task: () => Promise<T>): Promise<T> {
    if (this.inFlight >= this.limit) {
      await new Promise<void>((resolve) => this.waiting.push(resolve))
    }
    this.inFlight++
    try {
      return await task()
    } finally {
      this.inFlight--
      this.waiting.shift()?.()
    }
  }
}

export const sleep = (ms: number, signal?: AbortSignal) =>
  new Promise<void>((resolve, reject) => {
    if (signal?.aborted) return reject(new DOMException("Aborted", "AbortError"))
    const timer = setTimeout(() => {
      signal?.removeEventListener("abort", onAbort)
      resolve()
    }, ms)
    const onAbort = () => {
      clearTimeout(timer)
      reject(new DOMException("Aborted", "AbortError"))
    }
    signal?.addEventListener("abort", onAbort, { once: true })
  })

export type RetryOptions = {
  /** Total attempts, not retries. */
  attempts?: number
  baseDelayMs?: number
  signal?: AbortSignal
  /** Retry on these statuses in addition to 408/429/5xx. */
  retryStatuses?: number[]
}

/**
 * Fetch with bounded exponential backoff + jitter. 404/403 are treated as
 * terminal unless the caller opts them in — for CDN parts a 403 means "past
 * the end of the video", which must not be retried into a stall.
 */
export async function fetchWithRetry(url: string, options: RetryOptions & RequestInit = {}): Promise<Response> {
  const { attempts = 4, baseDelayMs = 350, signal, retryStatuses = [], ...init } = options
  const retriable = new Set([408, 425, 429, 500, 502, 503, 504, ...retryStatuses])

  let lastError: unknown = null
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      const response = await fetch(url, { ...init, signal })
      if (response.ok || !retriable.has(response.status)) return response
      lastError = new Error(`HTTP ${response.status} for ${url}`)
    } catch (error) {
      if ((error as Error)?.name === "AbortError") throw error
      lastError = error
    }
    if (attempt < attempts) {
      const backoff = baseDelayMs * 2 ** (attempt - 1)
      await sleep(backoff + Math.random() * backoff * 0.5, signal)
    }
  }
  throw lastError ?? new Error(`Request failed: ${url}`)
}

/** Cheap availability check — HEAD, falling back to a ranged GET. */
export async function headOk(url: string, signal?: AbortSignal): Promise<boolean> {
  try {
    const head = await fetch(url, { method: "HEAD", signal })
    if (head.status !== 405 && head.status !== 501) return head.ok
  } catch (error) {
    if ((error as Error)?.name === "AbortError") throw error
  }
  try {
    const ranged = await fetch(url, { headers: { Range: "bytes=0-0" }, signal })
    return ranged.ok
  } catch (error) {
    if ((error as Error)?.name === "AbortError") throw error
    return false
  }
}
