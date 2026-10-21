import { useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties } from "react"
import { AnimatePresence } from "motion/react"
import type { CatalogItem, CatalogResponse, LibraryResponse, Meta } from "../../api/types"
import { useStartDownloads } from "../../api/hooks"
import { courseLessons } from "../../lib/course"
import { panelGeometry, panelTracks } from "../../lib/panel"
import { rankItems } from "../../lib/search"
import { ItemCard, isDownloadable, type DownloadedState } from "../components/item-card"
import { BrowseToolbar, type KindFilter, type SortMode } from "../components/browse-toolbar"
import { CoursePanel } from "../components/course-panel"
import { PreviewPlayer } from "../components/player"
import { SelectionBar } from "../components/selection-bar"
import { useGridMetrics } from "../grid"
import { Button, EmptyState, Spinner } from "../primitives"
import { useEscape, useSelection } from "../store"

const PAGE_SIZE = 60
const QUALITY_RANK: Record<string, number> = { "720p": 1, "1080p": 2, "4K": 3 }
/** Tracks the panel needs to show its own card plus one full lesson card beside the open one. */
const PANEL_MIN_TRACKS = 3

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
  const [kind, setKind] = useState<KindFilter>("course")
  const [sort, setSort] = useState<SortMode>("newest")
  const [categories, setCategories] = useState<string[]>([])
  const [downloadState, setDownloadState] = useState<"any" | "missing" | "have">("any")
  const [preview, setPreview] = useState<CatalogItem | null>(null)
  const [openCourseId, setOpenCourseId] = useState<string | null>(null)
  const [limit, setLimit] = useState(PAGE_SIZE)
  const lastIndexRef = useRef<number | null>(null)
  const lessonIndexRef = useRef<number | null>(null)
  const gridRef = useRef<HTMLDivElement>(null)
  const { columns, track, gap } = useGridMetrics(gridRef)
  const [openCardHeight, setOpenCardHeight] = useState(0)

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
    const cache = new Map<string, DownloadedState | null>()
    return (item: CatalogItem): DownloadedState | null => {
      const cached = cache.get(item.id)
      if (cached !== undefined) return cached
      let state: DownloadedState | null = null
      if (item.kind === "course") {
        const lessons = item.lessonIds ?? []
        const have = lessons.filter((id) => downloadedByUuid.has(id)).length
        state =
          have === 0
            ? null
            : { label: have === lessons.length ? "Complete" : `${have}/${lessons.length}`, complete: have === lessons.length }
      } else {
        const quality = downloadedByUuid.get(item.id)
        state = quality ? { label: quality, complete: true } : null
      }
      cache.set(item.id, state)
      return state
    }
  }, [downloadedByUuid])

  const filtered = useMemo(() => {
    const inRole = role === "all"
    const categorySet = categories.length ? new Set(categories) : null

    const scoped = catalog.items.filter((item) => {
      if (!inRole && item.role !== role) return false
      if (item.kind !== kind) return false
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

  const openCourse = useMemo(
    () => catalog.items.find((item) => item.id === openCourseId) ?? null,
    [catalog.items, openCourseId],
  )
  const openLessons = useMemo(
    () => (openCourse ? courseLessons(catalog.items, openCourse) : []),
    [catalog.items, openCourse],
  )

  const handleOpenCourse = (item: CatalogItem) => {
    setOpenCourseId(item.id)
    lessonIndexRef.current = null
    const index = filtered.findIndex((entry) => entry.id === item.id)
    lastIndexRef.current = index >= 0 ? index : null
  }

  const handleToggleLesson = (id: string, additive: boolean) => {
    const index = openLessons.findIndex((lesson) => lesson.id === id)
    if (additive && lessonIndexRef.current !== null && index >= 0) {
      const from = Math.min(lessonIndexRef.current, index)
      const to = Math.max(lessonIndexRef.current, index)
      const range = openLessons.slice(from, to + 1).filter(isDownloadable).map((lesson) => lesson.id)
      selectMany(range, isSelected(id) ? "remove" : "add")
    } else {
      toggle(id)
    }
    lessonIndexRef.current = index >= 0 ? index : null
  }

  const queueSelection = (ids: string[]) => {
    if (!ids.length) return
    startDownloads.mutate({ ids, quality: prefs.quality, remux: prefs.remux, skipExisting: prefs.skipExisting })
  }

  const selectedIds = useMemo(() => Array.from(selection), [selection])

  const openIndex = openCourse ? visible.findIndex((item) => item.id === openCourse.id) : -1
  const openColumn = openIndex >= 0 ? (openIndex % columns) + 1 : 0
  const openRow = openIndex >= 0 ? Math.floor(openIndex / columns) + 1 : 0
  const room = openColumn > 0 ? columns - openColumn : 0
  // The panel is as wide as its cards ask for, never wider than the room left in
  // the row — a long course takes the rest of the row and scrolls inside it.
  const openGeometry = panelGeometry(openCardHeight, openLessons.length)
  const panelSpan = panelTracks(openGeometry.contentWidth, track, gap, PANEL_MIN_TRACKS, room)
  const beside = panelSpan >= PANEL_MIN_TRACKS
  const placement: CSSProperties | null =
    openIndex < 0
      ? null
      : beside
        ? { gridColumn: `${openColumn + 1} / span ${panelSpan}`, gridRow: `${openRow}` }
        : { gridColumn: "1 / -1", gridRow: `${openRow + 1}` }

  useLayoutEffect(() => {
    const card = gridRef.current?.querySelector<HTMLElement>('article[data-open="1"]')
    if (!card) {
      setOpenCardHeight(0)
      return
    }
    const read = () => setOpenCardHeight(card.offsetHeight)
    read()
    const observer = new ResizeObserver(read)
    observer.observe(card)
    return () => observer.disconnect()
  }, [openCourseId, columns, visible.length])

  useEscape(() => setOpenCourseId(null), Boolean(openCourseId) && !preview)

  useEffect(() => {
    if (openCourseId && !visible.some((item) => item.id === openCourseId)) setOpenCourseId(null)
  }, [openCourseId, visible])

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
                setKind("course")
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
          <div
            ref={gridRef}
            className="grid grid-cols-2 items-start gap-2.5 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6"
          >
            {visible.map((item) => (
              <ItemCard
                key={item.id}
                item={item}
                selected={isSelected(item.id)}
                open={item.id === openCourseId}
                attached={item.id === openCourseId && beside}
                downloaded={downloadedLabel(item)}
                onToggle={handleToggle}
                onPreview={setPreview}
                onOpen={handleOpenCourse}
              />
            ))}

            <AnimatePresence initial={false}>
              {openCourse && placement ? (
                <CoursePanel
                  key={openCourse.id}
                  course={openCourse}
                  lessons={openLessons}
                  downloaded={downloadedByUuid}
                  selectedCount={openLessons.filter((lesson) => isSelected(lesson.id)).length}
                  isSelected={isSelected}
                  onToggleLesson={handleToggleLesson}
                  onSelectAll={() => selectMany(openLessons.filter(isDownloadable).map((lesson) => lesson.id))}
                  onClear={() => selectMany(openLessons.map((lesson) => lesson.id), "remove")}
                  onPreview={setPreview}
                  onDownload={(ids) => {
                    setOpenCourseId(null)
                    queueSelection(ids)
                  }}
                  onClose={() => setOpenCourseId(null)}
                  busy={startDownloads.isPending}
                  placement={placement}
                  height={openCardHeight}
                  attached={beside}
                />
              ) : null}
            </AnimatePresence>
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
