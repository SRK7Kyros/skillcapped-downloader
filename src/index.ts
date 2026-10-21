/**
 * Entry point. Starts the local server, opens the browser, and — when the port
 * is already taken by another copy of this app — hands off to it instead of
 * running a second queue against the same content folder.
 */

import { mkdir } from "node:fs/promises"
import { loadJobs } from "./core/jobs-store.ts"
import { DownloadManager } from "./core/queue.ts"
import { parseFlags } from "./flags.ts"
import { openBrowser } from "./open-browser.ts"
import { appDir, contentDir, isStandalone, resolveTool, tmpDir } from "./paths.ts"
import { createHandler } from "./server/app.ts"
import { VERSION } from "./version.ts"

const flags = parseFlags()
const root = contentDir(flags)

await mkdir(tmpDir(root), { recursive: true })

const ffmpeg = resolveTool("ffmpeg")
const ffprobe = resolveTool("ffprobe")

const manager = new DownloadManager({
  contentDir: root,
  ffmpeg,
  concurrency: flags.concurrency,
  segmentConcurrency: 4,
  highQualityConcurrency: 1,
})
await manager.restore(await loadJobs(root))

const handler = createHandler({
  flags,
  root,
  manager,
  tools: { ffmpeg, ffprobe },
  startedAt: Date.now(),
})

const address = `http://${flags.host}:${flags.port}`

let server: ReturnType<typeof Bun.serve>
try {
  server = Bun.serve({
    port: flags.port,
    hostname: flags.host,
    fetch: handler,
    // SSE connections are long-lived; keep the socket alive well past the
    // 20 s heartbeat so a quiet queue is not disconnected.
    idleTimeout: 120,
  })
} catch (error) {
  if (await handedOffToExistingInstance(flags)) {
    console.log(`Another instance is already running — opened ${address}`)
    process.exit(0)
  }
  console.error(`Could not bind ${address}: ${(error as Error).message}`)
  console.error("Pick a different port with --port <n>.")
  process.exit(1)
}

report()

if (flags.openBrowser) openBrowser(address)

let shuttingDown = false
const shutdown = async (signal: string) => {
  if (shuttingDown) return
  shuttingDown = true
  console.log(`\n${signal} — stopping downloads…`)
  await manager.shutdown()
  server.stop(true)
  process.exit(0)
}

process.on("SIGINT", () => void shutdown("SIGINT"))
process.on("SIGTERM", () => void shutdown("SIGTERM"))

function report(): void {
  const rows: Array<[string, string]> = [
    ["version", VERSION],
    ["server", address],
    ["content", root],
    ["ffmpeg", ffmpeg ? `${ffmpeg.path} (${ffmpeg.source})` : "not found — files will be kept as .ts"],
  ]
  if (!ffmpeg) {
    console.log("\n  Note: no ffmpeg found. Downloads are saved as .ts transport streams.")
    console.log("  Drop an ffmpeg binary into bin/ next to the executable to get .mp4 output.\n")
  }
  console.log(`\nskillcapped-downloader (${isStandalone() ? "standalone" : "development"})`)
  for (const [key, value] of rows) console.log(`  ${key.padEnd(9)} ${value}`)
  if (!flags.openBrowser) console.log("\n  (browser launch disabled — open the server URL above)")
  console.log(`  app dir   ${appDir()}`)
  console.log("\nPress Ctrl+C to stop.\n")
}

/** Was the port taken by us rather than by something else? */
async function handedOffToExistingInstance(flags: ReturnType<typeof parseFlags>): Promise<boolean> {
  try {
    const response = await fetch(`${address}/api/meta`, { signal: AbortSignal.timeout(1500) })
    if (!response.ok) return false
    const meta = (await response.json()) as { app?: string }
    if (meta.app !== "skillcapped-downloader") return false
    if (flags.openBrowser) openBrowser(address)
    return true
  } catch {
    return false
  }
}
