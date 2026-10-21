import { useMemo, useState } from "react"
import { api } from "../../api/client"
import type { LibraryResponse, Meta } from "../../api/types"
import { formatBytes, formatRelative } from "../../lib/format"
import { rankItems } from "../../lib/search"
import { Icon } from "../icons"
import { Badge, Button, EmptyState } from "../primitives"

export function LibraryView({
  library,
  meta,
  onNotify,
}: {
  library: LibraryResponse
  meta: Meta
  onNotify: (message: string, tone?: "info" | "success" | "danger") => void
}) {
  const [query, setQuery] = useState("")
  const [sort, setSort] = useState<"newest" | "largest" | "title">("newest")

  const entries = useMemo(() => {
    const scoped = query.trim()
      ? rankItems(library.entries, query, (entry) => `${entry.title} ${entry.relativePath} ${entry.qualityLabel}`)
      : library.entries
    const ordered = [...scoped]
    if (sort === "newest") ordered.sort((a, b) => b.modifiedAt - a.modifiedAt)
    if (sort === "largest") ordered.sort((a, b) => b.sizeBytes - a.sizeBytes)
    if (sort === "title") ordered.sort((a, b) => a.title.localeCompare(b.title))
    return ordered
  }, [library.entries, query, sort])

  const openFolder = async () => {
    try {
      await api.openFolder()
    } catch (error) {
      onNotify((error as Error).message, "danger")
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <label className="relative min-w-0 flex-1 basis-[220px]">
          <span className="sr-only">Search downloaded files</span>
          <Icon name="search" size={14} className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-ink-faint" />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search what is already on disk…"
            className="h-8 w-full rounded-[var(--r-sm)] border border-line bg-surface-1 pr-2.5 pl-8 text-[12px] text-ink outline-none placeholder:text-ink-faint focus:border-line-strong tab-stop"
          />
        </label>

        <label className="relative shrink-0">
          <span className="sr-only">Sort files</span>
          <select
            value={sort}
            onChange={(event) => setSort(event.target.value as typeof sort)}
            className="select-chevron h-8 rounded-[var(--r-sm)] border border-line bg-surface-1 pr-7 pl-2.5 text-[11px] font-medium text-ink-muted outline-none focus:border-line-strong tab-stop"
          >
            <option value="newest">Newest first</option>
            <option value="largest">Largest first</option>
            <option value="title">Title A–Z</option>
          </select>
        </label>

        <Button size="sm" variant="secondary" icon="folder" onClick={() => void openFolder()} className="tab-stop">
          Open content folder
        </Button>
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 rounded-[var(--r-sm)] border border-line bg-surface-1 px-3 py-2 text-[11px] text-ink-dim">
        <span className="inline-flex items-center gap-1.5">
          <Icon name="check" size={11} className="text-success" />
          <span className="font-semibold text-ink tabular-nums">{library.count.toLocaleString()}</span> files
        </span>
        <span className="tabular-nums">{formatBytes(library.totalBytes)} on disk</span>
        <span className="min-w-0 truncate font-mono text-ink-faint" title={library.contentDir}>
          {library.contentDir}
        </span>
        <span className="ml-auto font-mono text-ink-faint">
          {meta.tools.ffmpeg ? "ffmpeg ready" : "ffmpeg missing"}
        </span>
      </div>

      {entries.length === 0 ? (
        <EmptyState
          icon="folder"
          title={library.count === 0 ? "No downloads yet" : "No files match that search"}
          body={
            library.count === 0
              ? "Everything you download lands here — one folder per role and course, so the collection stays browsable outside the app."
              : "Try a different word, or clear the search box."
          }
        />
      ) : (
        <ul className="divide-y divide-line overflow-hidden rounded-[var(--r-md)] border border-line bg-surface-1">
          {entries.map((entry) => (
            <li key={entry.relativePath} className="flex items-center gap-3 px-3 py-2">
              <span className="grid h-8 w-8 shrink-0 place-items-center rounded-[var(--r-sm)] border border-line bg-surface-2 text-ink-dim">
                <Icon name={entry.extension === "ts" ? "film" : "check"} size={13} />
              </span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-[12px] font-medium text-ink">{entry.title}</p>
                <p className="truncate font-mono text-[10px] text-ink-faint">{entry.folder || "."}</p>
              </div>
              <Badge>{entry.qualityLabel || entry.extension}</Badge>
              <span className="hidden w-20 text-right text-[10.5px] text-ink-dim tabular-nums sm:block">
                {formatBytes(entry.sizeBytes)}
              </span>
              <span className="hidden w-24 text-right text-[10.5px] text-ink-faint md:block">
                {formatRelative(entry.modifiedAt)}
              </span>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
