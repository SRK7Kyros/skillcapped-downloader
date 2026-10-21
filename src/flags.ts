/**
 * Command line + environment surface. Everything configurable lives here so
 * nothing else has to know how a value was supplied.
 */

export const QUALITY_IDS = [1500, 2500, 4500] as const
export type QualityId = (typeof QUALITY_IDS)[number]

export type Flags = {
  /** TCP port for the local server. */
  port: number
  /** Bind address — loopback only by default (this app writes files). */
  host: string
  /** Override the download root; defaults to `content/` beside the executable. */
  contentDir?: string
  /** Preferred stream rendition, one of QUALITY_IDS. */
  quality: QualityId
  /** Remux the concatenated transport stream to mp4 with ffmpeg. */
  remux: boolean
  /** Open the browser once the server is listening. */
  openBrowser: boolean
  /** How many downloads (and how many segments inside each) run at once. */
  concurrency: number
}

export const DEFAULT_PORT = 4780

export function isQualityId(value: number): value is QualityId {
  return (QUALITY_IDS as readonly number[]).includes(value)
}

function intFrom(value: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(value ?? "", 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
}

/**
 * Parse `process.argv` plus the environment. CLI wins over env; env wins over
 * the built-in default. Unknown arguments are ignored rather than fatal — a
 * double-clicked executable is often launched with an empty argument list.
 */
export function parseFlags(argv: string[] = process.argv.slice(2), env: Record<string, string | undefined> = process.env): Flags {
  const flags: Flags = {
    port: intFrom(env.PORT, DEFAULT_PORT),
    host: env.HOST ?? "127.0.0.1",
    contentDir: env.SKILLCAPPED_CONTENT_DIR,
    quality: isQualityId(Number(env.SKILLCAPPED_QUALITY)) ? (Number(env.SKILLCAPPED_QUALITY) as QualityId) : 2500,
    remux: env.SKILLCAPPED_REMUX !== "0",
    openBrowser: env.SKILLCAPPED_NO_OPEN !== "1",
    concurrency: intFrom(env.SKILLCAPPED_CONCURRENCY, 3),
  }

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    const next = () => argv[++i]
    switch (arg) {
      case "--port":
      case "-p":
        flags.port = intFrom(next(), flags.port)
        break
      case "--host":
        flags.host = next() ?? flags.host
        break
      case "--content-dir":
        flags.contentDir = next() ?? flags.contentDir
        break
      case "--quality":
      case "-q": {
        const value = Number(next())
        if (isQualityId(value)) flags.quality = value
        break
      }
      case "--concurrency":
        flags.concurrency = intFrom(next(), flags.concurrency)
        break
      case "--no-remux":
        flags.remux = false
        break
      case "--remux":
        flags.remux = true
        break
      case "--no-open":
        flags.openBrowser = false
        break
      case "--open":
        flags.openBrowser = true
        break
      case "--help":
      case "-h":
        printHelp()
        process.exit(0)
        break
      default:
        break
    }
  }

  return flags
}

export function printHelp(): void {
  const lines = [
    "skillcapped-downloader — offline browser + bulk downloader",
    "",
    "  --port, -p <n>        port for the local server (default 4780)",
    "  --host <addr>         bind address (default 127.0.0.1)",
    "  --content-dir <path>  where downloads land (default: content/ beside the exe)",
    "  --quality, -q <id>    1500 (720p) | 2500 (1080p) | 4500 (2160p)",
    "  --concurrency <n>     simultaneous downloads (default 3)",
    "  --no-remux            keep the merged transport stream (.ts), skip ffmpeg",
    "  --no-open             do not open the browser automatically",
    "  --help, -h            this text",
  ]
  console.log(lines.join("\n"))
}
