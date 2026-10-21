import { useEffect, useMemo, useRef, useState } from "react"
import type { CatalogItem, CatalogResponse, LibraryResponse, Meta } from "../../api/types"
import { useStartDownloads } from "../../api/hooks"
import { rankItems } from "../../lib/search"
import { ItemCard, isDownloadable } from "../components/item-card"
import { BrowseToolbar, type KindFilter, type SortMode } from "../components/browse-toolbar"
import { PreviewPlayer } from "../components/player"
import { SelectionBar } from "../components/selection-bar"
import { Button, EmptyState, Spinner } from "../primitives"
import { useSelection } from "../store"

const PAGE_SIZE = 60
const QUALITY_RANK: Record<string, number> = { "720p": 1, "1080p": 2, "4K": 3 }

function searchText(item: CatalogItem): string {
  return [item.title, item.category, item.role, item.staff, item.champions, item.courseTitle, ...(item.tags ?? [])]
    .filter(Boolean)
    .join(" ")
}

export function BrowseView({
  catalog,
  library,
  meta,
  onOpenDownloads,
  onRefresh,
  refreshing,
}: {
  catalog: CatalogResponse
  library: LibraryResponse
  meta: Meta
  onOpenDownloads: () => void
  onRefresh: () => void
  refreshing: boolean
}) {
  const { prefs, setPrefs, selection, isSelected, toggle, selectMany, clearSelection, notify } = useSelection()

  const [query, setQuery] = useState("")
  const [role, setRole] = useState("all")
  const [kind, setKind] = useState<KindFilter>("all")
  const [sort, setSort] = useState<SortMode>("newest")
  const [categories, setCategories] = useState<string[]>([])
  const [downloadState, setDownloadState] = useState<"any" | "missing" | "have">("any")
  const [preview, setPreview] = useState<CatalogItem | null>(null)
  const [limit, setLimit] = useState(PAGE_SIZE)
  const lastIndexRef = useRef<number | null>(null)

  const downloadedByUuid = useMemo(() => {
    const map = new Map<string, string>()
    for (const entry of library.entries) {
      const current = map.get(entry.uuid)
      if (!current || (QUALITY_RANK[entry.qualityLabel] ?? 0) > (QUALITY_RANK[current] ?? 0)) {
        map.set(entry.uuid, entry.qualityLabel)
      }
    }
    return map
  }, [library.entries])

  const downloadedLabel = useMemo(() => {
    const cache = new Map<string, string | null>()
    return (item: CatalogItem): string | null => {
      const cached = cache.get(item.id)
      if (cached !== undefined) return cached
      let label: string | null = null
      if (item.kind === "course") {
        const lessons = item.lessonIds ?? []
        const have = lessons.filter((id) => downloadedByUuid.has(id)).length
        label = have === 0 ? null : have === lessons.length ? "Complete" : `${have}/${lessons.length}`
      } else {
        label = downloadedByUuid.get(item.id) ?? null
      }
      cache.set(item.id, label)
      return label
    }
  }, [downloadedByUuid])

  const filtered = useMemo(() => {
    const inRole = role === "all"
    const categorySet = categories.length ? new Set(categories) : null

    const scoped = catalog.items.filter((item) => {
      if (!inRole && item.role !== role) return false
      if (kind !== "all" && item.kind !== kind) return false
      if (categorySet && !categorySet.has(item.category) && !(item.tags ?? []).some((tag) => categorySet.has(tag))) {
        return false
      }
      if (downloadState !== "any") {
        const label = downloadedLabel(item)
        if (downloadState === "missing" && label) return false
        if (downloadState === "have" && !label) return false
      }
      return true
    })

    const ordered = [...scoped]
    if (sort === "newest") ordered.sort((a, b) => b.date - a.date)
    if (sort === "oldest") ordered.sort((a, b) => a.date - b.date)
    if (sort === "longest") ordered.sort((a, b) => b.durationSec - a.durationSec)
    if (sort === "title") ordered.sort((a, b) => a.title.localeCompare(b.title))

    if (!query.trim()) return ordered
    // Ranking already produces the best order, so the sort choice only applies
    // to an unfiltered browse.
    return rankItems(ordered, query, searchText)
  }, [catalog.items, role, kind, categories, downloadState, sort, query, downloadedLabel])

  const visible = useMemo(() => filtered.slice(0, limit), [filtered, limit])
  const filterKey = `${query}|${role}|${kind}|${sort}|${downloadState}|${categories.join(",")}`

  useEffect(() => {
    setLimit(PAGE_SIZE)
    lastIndexRef.current = null
  }, [filterKey])

  const sentinelRef = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const node = sentinelRef.current
    if (!node || limit >= filtered.length) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) setLimit((value) => value + PAGE_SIZE)
      },
      { rootMargin: "700px 0px" },
    )
    observer.observe(node)
    return () => observer.disconnect()
  }, [limit, filtered.length])

  const startDownloads = useStartDownloads((summary) => {
    const parts: string[] = []
    if (summary.created) parts.push(`${summary.created} download${summary.created === 1 ? "" : "s"} queued`)
    if (summary.skipped) parts.push(`${summary.skipped} already on disk`)
    if (summary.missing) parts.push(`${summary.missing} no longer in the catalogue`)
    notify(parts.length ? parts.join(" · ") : "Nothing to download", summary.created ? "success" : "info")
    if (summary.created) {
      clearSelection()
      onOpenDownloads()
    }
  })

  const handleToggle = (id: string, additive: boolean) => {
    const index = filtered.findIndex((item) => item.id === id)
    if (additive && lastIndexRef.current !== null && index >= 0) {
      const from = Math.min(lastIndexRef.current, index)
      const to = Math.max(lastIndexRef.current, index)
      const range = filtered.slice(from, to + 1).filter(isDownloadable).map((item) => item.id)
      selectMany(range, isSelected(id) ? "remove" : "add")
    } else {
      toggle(id)
    }
    lastIndexRef.current = index >= 0 ? index : null
  }

  const queueSelection = (ids: string[]) => {
    if (!ids.length) return
    startDownloads.mutate({ ids, quality: prefs.quality, remux: prefs.remux, skipExisting: prefs.skipExisting })
  }

  const selectedIds = useMemo(() => Array.from(selection), [selection])

  return (
    <div>
      <BrowseToolbar
        query={query}
        onQueryChange={setQuery}
        role={role}
        onRoleChange={setRole}
        kind={kind}
        onKindChange={setKind}
        sort={sort}
        onSortChange={setSort}
        categories={catalog.categories}
        selectedCategories={categories}
        onCategoriesChange={setCategories}
        resultCount={filtered.length}
        totalCount={catalog.items.length}
        onRefresh={onRefresh}
        refreshing={refreshing}
        downloadState={downloadState}
        onDownloadStateChange={setDownloadState}
        downloadedCount={downloadedByUuid.size}
      />

      {catalog.note ? (
        <p className="mb-3 rounded-[var(--r-sm)] border border-warning/40 bg-warning-dim px-3 py-2 text-[11px] text-warning">
          {catalog.note}
        </p>
      ) : null}

      {filtered.length === 0 ? (
        <EmptyState
          title="Nothing matches those filters"
          body="Try a different role, clear the category filter, or search for a champion or course name."
          action={
            <Button
              size="sm"
              variant="ghost"
              onClick={() => {
                setQuery("")
                setRole("all")
                setKind("all")
                setCategories([])
                setDownloadState("any")
              }}
            >
              Reset filters
            </Button>
          }
        />
      ) : (
        <>
          <div className="grid grid-cols-2 items-start gap-2.5 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
            {visible.map((item) => (
              <ItemCard
                key={item.id}
                item={item}
                selected={isSelected(item.id)}
                downloaded={downloadedLabel(item)}
                onToggle={handleToggle}
                onPreview={setPreview}
              />
            ))}
          </div>

          <div ref={sentinelRef} className="flex items-center justify-center py-6">
            {limit < filtered.length ? (
              <Button size="sm" variant="ghost" onClick={() => setLimit((value) => value + PAGE_SIZE)}>
                <Spinner size={12} />
                Loading more — {filtered.length - limit} to go
              </Button>
            ) : (
              <p className="text-[10.5px] text-ink-faint">Showing all {filtered.length.toLocaleString()} matches.</p>
            )}
          </div>
        </>
      )}

      <SelectionBar
        count={selection.size}
        visibleCount={filtered.length}
        qualities={meta.qualities}
        quality={prefs.quality}
        onQualityChange={(quality) => setPrefs({ quality })}
        remux={prefs.remux}
        onRemuxChange={(remux) => setPrefs({ remux })}
        skipExisting={prefs.skipExisting}
        onSkipExistingChange={(skipExisting) => setPrefs({ skipExisting })}
        onDownload={() => queueSelection(selectedIds)}
        onSelectAll={() => selectMany(filtered.filter(isDownloadable).map((item) => item.id))}
        onClear={clearSelection}
        busy={startDownloads.isPending}
      />

      <PreviewPlayer
        item={preview}
        qualities={meta.qualities}
        quality={prefs.quality}
        onQualityChange={(quality) => setPrefs({ quality })}
        onDownload={(item) => {
          setPreview(null)
          queueSelection([item.id])
        }}
        onClose={() => setPreview(null)}
      />
    </div>
  )
}
