/**
 * HTTP API. One handler, a small route table, and a lazily-loaded catalogue
 * shared by every request.
 */

import path from "node:path"
import { QUALITIES, buildPlaylist, qualityById, segmentUrl } from "../core/cdn.ts"
import { loadCatalog } from "../core/catalog.ts"
import { libraryKey, scanLibrary } from "../core/library.ts"
import { SegmentError, resolveSegments } from "../core/probe.ts"
import { planPreview } from "../core/preview.ts"
import { contentRange, parseByteRange } from "../core/range.ts"
import type { DownloadManager, JobRecord, JobSpec } from "../core/queue.ts"
import type { Flags } from "../flags.ts"
import { openFolder } from "../open-browser.ts"
import { appDir, isStandalone, stateDir, tmpDir, type Tool } from "../paths.ts"
import type { Catalog, CatalogItem } from "../types/catalog.ts"
import { VERSION } from "../version.ts"
import { json, rejectForeignRequest } from "./security.ts"
import { appHtml, htmlBytes } from "./web.ts"

export type AppContext = {
  flags: Flags
  root: string
  manager: DownloadManager
  tools: { ffmpeg: Tool | null; ffprobe: Tool | null }
  startedAt: number
}

/** Shared catalogue with in-flight de-duplication. */
class CatalogStore {
  private value: Catalog | null = null
  private inflight: Promise<Catalog> | null = null
  private warned: string | null = null

  constructor(private readonly root: string) {}

  note(): string | null {
    return this.warned
  }

  async get(force = false): Promise<Catalog> {
    if (this.value && !force) return this.value
    if (this.inflight) return this.inflight
    this.inflight = loadCatalog({
      root: this.root,
      force,
      onNote: (message) => {
        this.warned = message
      },
    })
      .then((catalog) => {
        this.value = catalog
        return catalog
      })
      .finally(() => {
        this.inflight = null
      })
    return this.inflight
  }

  index(): Map<string, CatalogItem> {
    const map = new Map<string, CatalogItem>()
    for (const item of this.value?.items ?? []) map.set(item.id, item)
    return map
  }
}

export function createHandler(context: AppContext): (request: Request) => Promise<Response> {
  const store = new CatalogStore(context.root)

  return async function handle(request: Request): Promise<Response> {
    const rejection = rejectForeignRequest(request, context.flags.port)
    if (rejection) return rejection

    const url = new URL(request.url)
    const parts = url.pathname.split("/").filter(Boolean)

    try {
      return await dispatch(request, url, parts, context, store)
    } catch (error) {
      if (error instanceof SegmentError) return json({ error: error.message }, 404)
      console.error(`[api] ${request.method} ${url.pathname} failed:`, error)
      return json({ error: (error as Error).message || "Internal error" }, 500)
    }
  }
}

async function dispatch(
  request: Request,
  url: URL,
  parts: string[],
  context: AppContext,
  store: CatalogStore,
): Promise<Response> {
  const method = request.method.toUpperCase()

  if (!parts.length) return appHtml(request)
  if (parts.length === 1 && parts[0] === "health") return json({ ok: true, app: "skillcapped-downloader" })

  if (parts[0] !== "api") return new Response("Not found", { status: 404 })

  const [, resource, ...rest] = parts

  switch (resource) {
    case "meta":
      return json(metaPayload(context))
    case "catalog":
      return json(await catalogPayload(url, store))
    case "library":
      return json(await libraryPayload(context))
    case "jobs":
      return handleJobs(request, method, rest, context, store)
    case "events":
      return eventsStream(context)
    case "open-folder":
      return handleOpenFolder(method, context)
    case "stream":
      return handleStream(request, url, rest, context, store)
    case "preview":
      return handlePreview(url, rest, context)
    case "media":
      return handleMedia(request, url, rest, context)
    case "segment":
      return handleSegment(request, rest)
    default:
      return json({ error: `Unknown endpoint /api/${resource}` }, 404)
  }
}

function metaPayload(context: AppContext) {
  return {
    app: "skillcapped-downloader",
    version: VERSION,
    standalone: isStandalone(),
    contentDir: context.root,
    stateDir: stateDir(context.root),
    tmpDir: tmpDir(context.root),
    appDir: appDir(),
    execPath: process.execPath,
    port: context.flags.port,
    startedAt: context.startedAt,
    uiBytes: htmlBytes,
    qualities: QUALITIES,
    defaults: {
      quality: context.flags.quality,
      remux: context.flags.remux,
      concurrency: context.flags.concurrency,
    },
    tools: {
      ffmpeg: context.tools.ffmpeg,
      ffprobe: context.tools.ffprobe,
    },
  }
}

async function catalogPayload(url: URL, store: CatalogStore) {
  const force = url.searchParams.get("refresh") === "1"
  const catalog = await store.get(force)
  return {
    season: catalog.season,
    patch: catalog.patch,
    generatedAt: catalog.generatedAt,
    dumpUrl: catalog.dumpUrl,
    roles: catalog.roles,
    categories: catalog.categories,
    items: catalog.items,
    note: store.note(),
  }
}

async function libraryPayload(context: AppContext) {
  const library = await scanLibrary(context.root)
  return {
    count: library.entries.length,
    totalBytes: library.totalBytes,
    contentDir: context.root,
    entries: library.entries,
  }
}

async function handleJobs(
  request: Request,
  method: string,
  rest: string[],
  context: AppContext,
  store: CatalogStore,
): Promise<Response> {
  if (!rest.length) {
    if (method === "GET") return json({ jobs: context.manager.list() })
    if (method === "POST") return createJobs(request, context, store)
    return json({ error: "Method not allowed" }, 405)
  }

  if (rest[0] === "clear" && method === "POST") {
    context.manager.clearSettled()
    return json({ jobs: context.manager.list() })
  }

  const [id, action] = rest
  if (!id) return json({ error: "Job id is required" }, 400)

  if (method === "DELETE") {
    const removed = context.manager.remove(id)
    return removed ? json({ ok: true }) : json({ error: "Job not found" }, 404)
  }

  if (method === "POST" && action === "cancel") {
    const cancelled = context.manager.cancel(id)
    return cancelled ? json({ ok: true }) : json({ error: "Job is not running" }, 409)
  }

  if (method === "POST" && action === "retry") {
    const retried = context.manager.retry(id)
    return retried ? json({ ok: true }) : json({ error: "Job cannot be retried" }, 409)
  }

  return json({ error: "Unknown job action" }, 404)
}

type CreateBody = {
  ids?: unknown
  quality?: unknown
  remux?: unknown
  skipExisting?: unknown
}

async function createJobs(request: Request, context: AppContext, store: CatalogStore): Promise<Response> {
  let body: CreateBody
  try {
    body = (await request.json()) as CreateBody
  } catch {
    return json({ error: "Request body must be JSON" }, 400)
  }

  const ids = Array.isArray(body.ids) ? body.ids.filter((id): id is string => typeof id === "string") : []
  if (!ids.length) return json({ error: "No items were selected" }, 400)

  const quality = qualityById(Number(body.quality))?.id ?? context.flags.quality
  const remux = body.remux === undefined ? context.flags.remux : Boolean(body.remux)
  const skipExisting = body.skipExisting !== false

  const catalog = await store.get()
  const index = store.index()
  const library = skipExisting ? await scanLibrary(context.root) : null

  const specs: JobSpec[] = []
  const skipped: Array<{ id: string; title: string }> = []
  const missing: string[] = []

  for (const id of new Set(ids)) {
    const item = index.get(id)
    if (!item) {
      missing.push(id)
      continue
    }
    for (const spec of expand(item, index)) {
      if (library && library.keys.has(libraryKey(spec.uuid, qualityLabel(catalog, spec, quality)))) {
        skipped.push({ id: spec.uuid, title: spec.title })
        continue
      }
      specs.push(spec)
    }
  }

  if (!specs.length) {
    return json({ created: [], skipped, missing, expanded: 0 })
  }

  const created = context.manager.add(specs, quality, remux)
  return json({ created, skipped, missing, expanded: created.length })
}

function qualityLabel(_catalog: Catalog, _spec: JobSpec, quality: number): string {
  return qualityById(quality)?.label ?? `${quality}p`
}

/**
 * A course is a container: selecting it queues each of its lessons, tagged
 * with a shared group so the queue reads as one bulk run.
 */
function expand(item: CatalogItem, index: Map<string, CatalogItem>): JobSpec[] {
  if (item.kind !== "course") {
    return [
      {
        uuid: item.id,
        kind: item.kind,
        title: item.title,
        role: item.role,
        durationSec: item.durationSec,
        category: item.category,
        courseTitle: item.courseTitle,
      },
    ]
  }

  const lessons = item.lessonIds ?? []
  return lessons.map((lessonId, position) => {
    const lesson = index.get(lessonId)
    return {
      uuid: lessonId,
      kind: "video" as const,
      title: lesson ? lesson.title : `${item.title} — Lesson ${position + 1}`,
      role: lesson?.role ?? item.role,
      durationSec: lesson?.durationSec ?? 0,
      category: lesson?.category ?? item.category,
      courseTitle: item.title,
      groupId: item.id,
      groupTitle: item.title,
    }
  })
}

async function handleOpenFolder(method: string, context: AppContext): Promise<Response> {
  if (method !== "POST") return json({ error: "Method not allowed" }, 405)
  const opened = openFolder(context.root)
  return json({ ok: opened, contentDir: context.root })
}

async function handleStream(
  request: Request,
  url: URL,
  rest: string[],
  context: AppContext,
  store: CatalogStore,
): Promise<Response> {
  const file = rest.join("/")
  const uuid = file.replace(/\.m3u8$/, "")
  if (!uuid) return json({ error: "A video id is required" }, 400)

  const quality = qualityById(Number(url.searchParams.get("quality")))?.id ?? context.flags.quality
  const catalog = store.index().get(uuid)
  const durationSec = Number(url.searchParams.get("dur")) || catalog?.durationSec || 0

  const plan = await resolveSegments(uuid, quality, durationSec, request.signal)
  const playlist = buildPlaylist(
    uuid,
    quality,
    plan.count,
    plan.duration || durationSec || plan.count * 10,
    plan.durations,
  )

  return new Response(playlist, {
    headers: {
      "content-type": "application/vnd.apple.mpegurl",
      "cache-control": "public, max-age=600",
      "content-length": String(Buffer.byteLength(playlist)),
    },
  })
}

async function handlePreview(url: URL, rest: string[], context: AppContext): Promise<Response> {
  const uuid = (rest[0] ?? "").replace(/\.(m3u8|mp4)$/i, "")
  if (!uuid) return json({ error: "A video id is required" }, 400)

  const quality = qualityById(Number(url.searchParams.get("quality")))?.id ?? context.flags.quality
  const durationSec = Number(url.searchParams.get("dur")) || 0
  const library = await scanLibrary(context.root)

  return json({ uuid, durationSec, ...planPreview(uuid, quality, durationSec, library.entries) })
}

const MEDIA_TYPES: Record<string, string> = {
  mp4: "video/mp4",
  ts: "video/mp2t",
  m4v: "video/x-m4v",
}

/**
 * A finished download, with byte ranges so the preview can seek. Only paths the
 * library scan produced are served — the uuid is looked up in that index rather
 * than joined into a path, so a request cannot walk out of the content folder.
 */
async function handleMedia(request: Request, url: URL, rest: string[], context: AppContext): Promise<Response> {
  const uuid = (rest[0] ?? "").replace(/\.[a-z0-9]+$/i, "")
  if (!uuid) return json({ error: "A video id is required" }, 400)

  const wanted = url.searchParams.get("quality") ?? ""
  const library = await scanLibrary(context.root)
  const candidates = library.entries.filter((entry) => entry.uuid === uuid)
  const entry = (wanted ? candidates.find((candidate) => candidate.qualityLabel === wanted) : undefined) ?? candidates[0]
  if (!entry) return json({ error: "That video is not on disk." }, 404)

  const root = path.resolve(context.root)
  const absolute = path.resolve(root, entry.relativePath)
  if (absolute !== root && !absolute.startsWith(root + path.sep)) {
    return json({ error: "That file is outside the content folder." }, 400)
  }

  const file = Bun.file(absolute)
  const stat = await file.stat().catch(() => null)
  if (!stat) return json({ error: "That file is no longer there." }, 404)

  const headers: Record<string, string> = {
    "content-type": MEDIA_TYPES[entry.extension.toLowerCase()] ?? "application/octet-stream",
    "accept-ranges": "bytes",
    "cache-control": "private, max-age=0, must-revalidate",
    etag: `"${stat.size.toString(36)}-${Math.round(stat.mtimeMs).toString(36)}"`,
  }

  const range = parseByteRange(request.headers.get("range"), stat.size)
  if (range === "unsatisfiable") {
    return new Response(null, { status: 416, headers: { ...headers, "content-range": `bytes */${stat.size}` } })
  }
  if (range) {
    return new Response(file.slice(range.start, range.end + 1), {
      status: 206,
      headers: {
        ...headers,
        "content-range": contentRange(range, stat.size),
        "content-length": String(range.end - range.start + 1),
      },
    })
  }
  return new Response(file, { headers: { ...headers, "content-length": String(stat.size) } })
}

/**
 * One CDN part, relayed. Playlists point here so the browser stays on this
 * origin — the CDN's CORS policy, and its S3 error documents, never reach us.
 */
async function handleSegment(request: Request, rest: string[]): Promise<Response> {
  const [uuid, qualityRaw, fileName] = rest
  const index = Number((fileName ?? "").replace(/\.ts$/i, ""))
  const quality = qualityById(Number(qualityRaw))?.id

  if (!uuid || !quality || !Number.isInteger(index) || index < 1) {
    return json({ error: "Malformed segment address." }, 400)
  }

  let upstream: Response
  try {
    upstream = await fetch(segmentUrl(uuid, quality, index), { signal: request.signal })
  } catch (error) {
    if (request.signal.aborted) return new Response(null, { status: 499 })
    throw error
  }

  // Past the tail, or a video the CDN no longer publishes.
  if (!upstream.ok || !upstream.body) {
    return json({ error: `Part ${index} is not available.` }, 404)
  }

  const headers: Record<string, string> = {
    "content-type": "video/mp2t",
    "cache-control": "public, max-age=3600",
  }
  const length = upstream.headers.get("content-length")
  if (length) headers["content-length"] = length

  return new Response(upstream.body, { status: 200, headers })
}

function eventsStream(context: AppContext): Response {
  const encoder = new TextEncoder()
  let cleanup = () => {}

  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      const send = (event: string, data: unknown) => {
        try {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`))
          return true
        } catch {
          cleanup()
          return false
        }
      }

      controller.enqueue(encoder.encode("retry: 3000\n\n"))
      send("hello", { version: VERSION, at: Date.now() })
      for (const job of context.manager.list()) send("job", job)

      const unsubscribers = [
        context.manager.events.on("changed", (job: JobRecord) => send("job", job)),
        context.manager.events.on("removed", (payload) => send("removed", payload)),
        context.manager.events.on("settled", () => send("library", { at: Date.now() })),
      ]
      const heartbeat = setInterval(() => send("ping", { at: Date.now() }), 20_000)

      cleanup = () => {
        clearInterval(heartbeat)
        for (const unsubscribe of unsubscribers) unsubscribe()
      }
    },
    cancel() {
      cleanup()
    },
  })

  return new Response(stream, {
    headers: {
      "content-type": "text/event-stream; charset=utf-8",
      "cache-control": "no-cache, no-transform",
      connection: "keep-alive",
      "x-accel-buffering": "no",
    },
  })
}
