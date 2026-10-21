import { useMemo, useRef, useState } from "react"
import { Icon } from "../icons"
import { Button, Chip, IconButton, Popover, Segmented, cx } from "../primitives"
import { roleLabel, roleShort, roleVar } from "../../lib/format"

export type KindFilter = "video" | "commentary" | "course"
export type SortMode = "newest" | "oldest" | "longest" | "title"

export const SORT_OPTIONS: Array<{ value: SortMode; label: string }> = [
  { value: "newest", label: "Newest first" },
  { value: "oldest", label: "Oldest first" },
  { value: "longest", label: "Longest first" },
  { value: "title", label: "Title A–Z" },
]

const ROLES = ["all", "top", "jungle", "mid", "adc", "support"] as const

function RoleTabs({ role, onChange }: { role: string; onChange: (role: string) => void }) {
  return (
    <div role="tablist" aria-label="Filter by role" className="flex flex-wrap items-center gap-1">
      {ROLES.map((value) => {
        const active = role === value
        const color = roleVar(value)
        return (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange(value)}
            style={active ? { color, borderColor: `color-mix(in srgb, ${color} 46%, transparent)`, backgroundColor: `color-mix(in srgb, ${color} 13%, transparent)` } : undefined}
            className={cx(
              "inline-flex h-7 items-center gap-1.5 rounded-[var(--r-sm)] border px-2.5 text-[11px] font-medium transition-colors duration-[var(--dur-fast)] tab-stop",
              active ? "" : "border-line bg-surface-1 text-ink-muted hover:border-line-strong hover:text-ink",
            )}
          >
            <span
              aria-hidden="true"
              className="h-1.5 w-1.5 rounded-full"
              style={{ backgroundColor: active ? color : `color-mix(in srgb, ${color} 60%, transparent)` }}
            />
            {roleLabel(value)}
          </button>
        )
      })}
    </div>
  )
}

function CategoryPicker({
  categories,
  selected,
  onChange,
}: {
  categories: string[]
  selected: string[]
  onChange: (next: string[]) => void
}) {
  const [open, setOpen] = useState(false)
  const [query, setQuery] = useState("")
  const inputRef = useRef<HTMLInputElement>(null)

  const filtered = useMemo(() => {
    const needle = query.trim().toLowerCase()
    if (!needle) return categories
    return categories.filter((category) => category.toLowerCase().includes(needle))
  }, [categories, query])

  const toggle = (category: string) => {
    onChange(selected.includes(category) ? selected.filter((value) => value !== category) : [...selected, category])
  }

  return (
    <Popover
      open={open}
      onOpenChange={(next) => {
        setOpen(next)
        if (!next) setQuery("")
        else window.setTimeout(() => inputRef.current?.focus(), 40)
      }}
      trigger={
        <Button variant={selected.length ? "secondary" : "ghost"} size="sm" icon="filter" className="tab-stop">
          {selected.length ? `Category · ${selected.length}` : "Category"}
          <Icon name="chevron-down" size={12} className="text-ink-faint" />
        </Button>
      }
      contentClassName="w-[min(340px,90vw)] p-2"
    >
      <input
        ref={inputRef}
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        placeholder={`Search ${categories.length} categories…`}
        className="h-8 w-full rounded-[var(--r-sm)] border border-line bg-surface-1 px-2.5 text-[11.5px] text-ink outline-none placeholder:text-ink-faint focus:border-line-strong"
      />
      <div className="mt-2 max-h-[min(46vh,320px)] overflow-y-auto">
        {selected.length ? (
          <button
            type="button"
            onClick={() => onChange([])}
            className="mb-1 flex w-full items-center gap-1.5 rounded-[var(--r-xs)] px-2 py-1.5 text-left text-[11px] text-ink-muted hover:bg-surface-2 hover:text-ink tab-stop"
          >
            <Icon name="x" size={11} />
            Clear {selected.length} selected
          </button>
        ) : null}
        {filtered.length === 0 ? (
          <p className="px-2 py-3 text-center text-[11px] text-ink-faint">No category matches.</p>
        ) : (
          filtered.map((category) => {
            const active = selected.includes(category)
            return (
              <button
                key={category}
                type="button"
                onClick={() => toggle(category)}
                aria-pressed={active}
                className={cx(
                  "flex w-full items-center gap-2 rounded-[var(--r-xs)] px-2 py-1.5 text-left text-[11.5px] transition-colors duration-[var(--dur-fast)] tab-stop",
                  active ? "bg-brand-dim text-brand" : "text-ink-muted hover:bg-surface-2 hover:text-ink",
                )}
              >
                <span
                  className={cx(
                    "grid h-3.5 w-3.5 shrink-0 place-items-center rounded-[2px] border",
                    active ? "border-brand bg-brand text-brand-ink" : "border-line-strong",
                  )}
                >
                  {active ? <Icon name="check" size={9} strokeWidth={3} /> : null}
                </span>
                <span className="truncate">{category}</span>
              </button>
            )
          })
        )}
      </div>
    </Popover>
  )
}

export function BrowseToolbar({
  query,
  onQueryChange,
  role,
  onRoleChange,
  kind,
  onKindChange,
  sort,
  onSortChange,
  categories,
  selectedCategories,
  onCategoriesChange,
  resultCount,
  totalCount,
  onRefresh,
  refreshing,
  downloadState,
  onDownloadStateChange,
  downloadedCount,
}: {
  query: string
  onQueryChange: (value: string) => void
  role: string
  onRoleChange: (value: string) => void
  kind: KindFilter
  onKindChange: (value: KindFilter) => void
  sort: SortMode
  onSortChange: (value: SortMode) => void
  categories: string[]
  selectedCategories: string[]
  onCategoriesChange: (next: string[]) => void
  resultCount: number
  totalCount: number
  onRefresh: () => void
  refreshing: boolean
  downloadState: "any" | "missing" | "have"
  onDownloadStateChange: (value: "any" | "missing" | "have") => void
  downloadedCount: number
}) {
  const filtersActive = Boolean(query.trim()) || role !== "all" || kind !== "course" || selectedCategories.length > 0

  return (
    <div className="sticky top-[var(--topbar-h)] z-[var(--z-sticky)] -mx-4 mb-4 border-b border-line bg-canvas/92 px-4 pt-3 pb-2.5 backdrop-blur-md sm:-mx-6 sm:px-6">
      <div className="flex flex-wrap items-center gap-2">
        <label className="relative min-w-0 flex-1 basis-[220px]">
          <span className="sr-only">Search the catalogue</span>
          <Icon name="search" size={14} className="pointer-events-none absolute top-1/2 left-2.5 -translate-y-1/2 text-ink-faint" />
          <input
            value={query}
            onChange={(event) => onQueryChange(event.target.value)}
            placeholder="Search 6,000+ videos, courses and commentaries…"
            className="h-8 w-full rounded-[var(--r-sm)] border border-line bg-surface-1 pr-8 pl-8 text-[12px] text-ink outline-none placeholder:text-ink-faint focus:border-line-strong tab-stop"
          />
          {query ? (
            <button
              type="button"
              aria-label="Clear search"
              onClick={() => onQueryChange("")}
              className="absolute top-1/2 right-1.5 grid h-5 w-5 -translate-y-1/2 place-items-center rounded-[var(--r-xs)] text-ink-dim hover:bg-surface-2 hover:text-ink tab-stop"
            >
              <Icon name="x" size={11} />
            </button>
          ) : null}
        </label>

        <Segmented
          ariaLabel="Content type"
          value={kind}
          onChange={onKindChange}
          options={[
            { value: "course", label: "Courses", icon: "book" },
            { value: "video", label: "Videos", icon: "film" },
            { value: "commentary", label: "Smurfs", icon: "users" },
          ]}
        />

        <label className="relative shrink-0">
          <span className="sr-only">Sort order</span>
          <select
            value={sort}
            onChange={(event) => onSortChange(event.target.value as SortMode)}
            className="select-chevron h-8 rounded-[var(--r-sm)] border border-line bg-surface-1 pr-7 pl-2.5 text-[11px] font-medium text-ink-muted outline-none hover:text-ink focus:border-line-strong tab-stop"
          >
            {SORT_OPTIONS.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </select>
        </label>

        <IconButton
          icon="retry"
          label="Refresh catalogue from source"
          onClick={onRefresh}
          disabled={refreshing}
          className={cx(refreshing && "animate-[spin_1s_linear_infinite]")}
        />
      </div>

      <div className="mt-2 flex flex-wrap items-center gap-2">
        <RoleTabs role={role} onChange={onRoleChange} />
        <span aria-hidden="true" className="hidden h-4 w-px bg-line sm:block" />
        <CategoryPicker categories={categories} selected={selectedCategories} onChange={onCategoriesChange} />
        <Segmented
          ariaLabel="Download state"
          value={downloadState}
          onChange={onDownloadStateChange}
          options={[
            { value: "any", label: "Any" },
            { value: "missing", label: "New", icon: "download" },
            { value: "have", label: "On disk", icon: "check" },
          ]}
        />
        {downloadState === "any" && downloadedCount > 0 ? (
          <span className="text-[10px] text-ink-faint tabular-nums">{downloadedCount.toLocaleString()} on disk</span>
        ) : null}
        {filtersActive ? (
          <Chip
            onClick={() => {
              onQueryChange("")
              onRoleChange("all")
              onKindChange("course")
              onCategoriesChange([])
            }}
            className="text-ink-dim"
          >
            <Icon name="x" size={10} />
            Clear filters
          </Chip>
        ) : null}
        <p className="ml-auto text-[10.5px] text-ink-dim tabular-nums">
          <span className="font-semibold text-ink">{resultCount.toLocaleString()}</span>
          {resultCount === totalCount ? " items" : ` of ${totalCount.toLocaleString()}`}
        </p>
      </div>

      {selectedCategories.length ? (
        <div className="mt-1.5 flex flex-wrap items-center gap-1">
          {selectedCategories.slice(0, 8).map((category) => (
            <button
              key={category}
              type="button"
              onClick={() => onCategoriesChange(selectedCategories.filter((value) => value !== category))}
              className="inline-flex h-5 items-center gap-1 rounded-full border border-brand-line bg-brand-dim px-2 text-[10px] font-medium text-brand tab-stop"
            >
              {category}
              <Icon name="x" size={9} />
            </button>
          ))}
          {selectedCategories.length > 8 ? (
            <span className="text-[10px] text-ink-dim">+{selectedCategories.length - 8} more</span>
          ) : null}
        </div>
      ) : null}
    </div>
  )
}

export { roleShort }
