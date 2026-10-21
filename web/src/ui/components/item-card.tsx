import { useMemo, useState } from "react"
import type { CatalogItem } from "../../api/types"
import { formatCount, formatDate, formatDuration, roleLabel, roleShort, roleVar } from "../../lib/format"
import { imageRatio, posterRatio } from "../../lib/media"
import { Icon, type IconName } from "../icons"
import { Badge, Tooltip, cx } from "../primitives"

const KIND_META: Record<CatalogItem["kind"], { label: string; icon: IconName }> = {
  video: { label: "Video", icon: "film" },
  commentary: { label: "Smurf", icon: "users" },
  course: { label: "Course", icon: "book" },
}

function isInteractive(target: EventTarget | null): boolean {
  return target instanceof Element && Boolean(target.closest("button, a, input, select, textarea"))
}

/** Four courses in the current dump have no lessons published yet, so the
 *  "can this be queued at all" rule needs one home. */
export function isDownloadable(item: CatalogItem): boolean {
  return item.kind !== "course" || (item.videoCount ?? 0) > 0
}

/**
 * Poster fallback. Two thirds of the library predates the poster migration, so
 * the no-image state is the common case and has to read as designed rather
 * than as a failure.
 */
function PosterFallback({ item }: { item: CatalogItem }) {
  const color = roleVar(item.role)
  const meta = KIND_META[item.kind]
  const style = useMemo(
    () => ({
      backgroundImage: `radial-gradient(120% 110% at 18% 0%, color-mix(in srgb, ${color} 26%, transparent), transparent 62%), repeating-linear-gradient(135deg, rgba(255,255,255,0.04) 0 1px, transparent 1px 9px)`,
    }),
    [color],
  )
  return (
    <div className="absolute inset-0 bg-surface-2" style={style}>
      <div className="absolute inset-0 grid place-items-center">
        <span
          className="font-mono text-[24px] font-bold tracking-[0.18em]"
          style={{ color: `color-mix(in srgb, ${color} 72%, transparent)` }}
        >
          {roleShort(item.role)}
        </span>
      </div>
      <span className="absolute bottom-1.5 left-2 flex items-center gap-1 text-[9px] font-medium tracking-[0.1em] uppercase" style={{ color: `color-mix(in srgb, ${color} 62%, transparent)` }}>
        <Icon name={meta.icon} size={10} />
        {meta.label}
      </span>
    </div>
  )
}

export type DownloadedState = { label: string; complete: boolean }

export function ItemCard({
  item,
  selected,
  open,
  downloaded,
  onToggle,
  onPreview,
  onOpen,
}: {
  item: CatalogItem
  selected: boolean
  open: boolean
  downloaded: DownloadedState | null
  onToggle: (id: string, additive: boolean) => void
  onPreview: (item: CatalogItem) => void
  onOpen: (item: CatalogItem) => void
}) {
  const [brokenThumb, setBrokenThumb] = useState(false)
  const [ratio, setRatio] = useState<string | null>(null)
  const color = roleVar(item.role)
  const showPoster = Boolean(item.thumb) && !brokenThumb
  const playable = item.kind !== "course"
  const downloadable = isDownloadable(item)
  const expandable = item.kind === "course" && downloadable

  return (
    <article
      data-selected={selected ? "1" : undefined}
      data-open={open ? "1" : undefined}
      data-on-disk={downloaded?.complete ? "1" : downloaded ? "partial" : undefined}
      onClick={(event) => {
        if (isInteractive(event.target)) return
        if (expandable && !event.shiftKey) {
          onOpen(item)
          return
        }
        if (!downloadable) return
        onToggle(item.id, event.shiftKey)
      }}
      className={cx(
        "group relative flex flex-col overflow-hidden rounded-[var(--r-md)] border bg-surface-1 transition-[border-color,background-color,transform] duration-[var(--dur-fast)]",
        downloadable ? "cursor-pointer" : "cursor-default",
        selected || open
          ? "border-brand-line bg-surface-2 shadow-[0_0_0_1px_var(--accent-line)]"
          : downloaded?.complete
            ? "border-success/70 shadow-[0_0_0_1px_rgba(63,185,80,0.18)] hover:border-success hover:bg-surface-2"
            : downloaded
              ? "border-success/45 hover:border-success/70 hover:bg-surface-2"
              : "border-line hover:border-line-strong hover:bg-surface-2",
      )}
    >
      <div
        className="relative w-full overflow-hidden bg-surface-2"
        style={{ aspectRatio: ratio ?? posterRatio(item.kind) }}
      >
        {showPoster ? (
          <img
            src={item.thumb}
            alt=""
            loading="lazy"
            decoding="async"
            onError={() => setBrokenThumb(true)}
            onLoad={(event) => setRatio(imageRatio(event.currentTarget.naturalWidth, event.currentTarget.naturalHeight))}
            className="h-full w-full object-cover transition-transform duration-[var(--dur-slow)] ease-out group-hover:scale-[1.03]"
          />
        ) : (
          <PosterFallback item={item} />
        )}

        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-14 bg-gradient-to-t from-black/72 to-transparent" />

        <div className="absolute top-1.5 left-1.5 flex items-center gap-1">
          <Badge color={color} subtle>
            {roleShort(item.role)}
          </Badge>
          {item.kind === "course" && !downloadable ? <Badge>No lessons yet</Badge> : null}
        </div>

        <button
          type="button"
          aria-label={
            downloadable
              ? selected
                ? `Deselect ${item.title}`
                : `Select ${item.title}`
              : `${item.title} — no lessons published yet`
          }
          aria-pressed={selected}
          aria-disabled={downloadable ? undefined : true}
          disabled={!downloadable}
          title={downloadable ? undefined : "This course has no lessons published yet."}
          onClick={(event) => {
            event.stopPropagation()
            onToggle(item.id, event.shiftKey)
          }}
          className={cx(
            "absolute top-1.5 right-1.5 grid h-[22px] w-[22px] place-items-center rounded-[var(--r-xs)] border transition-colors duration-[var(--dur-fast)] tab-stop",
            selected
              ? "border-brand bg-brand text-brand-ink"
              : "border-white/25 bg-black/45 text-white/80 backdrop-blur-sm hover:border-white/60 hover:text-white",
            !downloadable &&
              "cursor-default border-white/15 bg-black/30 text-white/30 hover:border-white/15 hover:text-white/30",
          )}
        >
          <Icon name={selected ? "check" : "plus"} size={12} strokeWidth={2.6} />
        </button>

        {playable ? (
          <button
            type="button"
            aria-label={`Preview ${item.title}`}
            onClick={(event) => {
              event.stopPropagation()
              onPreview(item)
            }}
            className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 opacity-75 transition-opacity duration-[var(--dur-fast)] hover:opacity-100 focus-visible:opacity-100 tab-stop"
          >
            <span className="grid h-9 w-9 place-items-center rounded-full border border-white/30 bg-black/55 text-white backdrop-blur-sm transition-transform duration-[var(--dur-fast)] hover:scale-110">
              <Icon name="play" size={13} className="translate-x-[1px]" />
            </span>
          </button>
        ) : null}

        <span className="pointer-events-none absolute right-1.5 bottom-1.5 rounded-[var(--r-xs)] bg-black/70 px-1.5 py-0.5 font-mono text-[10px] font-medium text-white/90 tabular-nums">
          {item.kind === "course"
            ? downloadable
              ? `${item.videoCount} lessons`
              : "Not published"
            : formatDuration(item.durationSec)}
        </span>

        {downloaded ? (
          <span className="pointer-events-none absolute bottom-1.5 left-1.5 inline-flex items-center gap-1 rounded-[var(--r-xs)] bg-success-dim px-1.5 py-0.5 text-[9.5px] font-semibold tracking-[0.04em] text-success uppercase">
            <Icon name="check" size={9} strokeWidth={3} />
            {downloaded.label}
          </span>
        ) : null}
      </div>

      <div className="flex min-h-0 flex-1 flex-col gap-1 px-2.5 py-2">
        <h3 className="line-clamp-2 min-h-[2.75em] text-[12px] leading-snug font-semibold text-ink">
          {expandable ? (
            <button
              type="button"
              onClick={(event) => {
                event.stopPropagation()
                if (event.shiftKey) onToggle(item.id, true)
                else onOpen(item)
              }}
              className="text-left tab-stop"
            >
              {item.title}
            </button>
          ) : (
            item.title
          )}
        </h3>
        <p className="truncate text-[10px] text-ink-dim">
          {item.category || roleLabel(item.role)}
          {item.kind === "commentary" && item.champions ? ` · ${item.champions}` : ""}
        </p>
        <div className="mt-auto flex items-center justify-between gap-2 pt-1 text-[9.5px] text-ink-faint">
          <span className="truncate">{formatDate(item.date)}</span>
          {item.kind === "commentary" && item.kda ? (
            <span className="font-mono tabular-nums text-ink-dim">{item.kda}</span>
          ) : item.kind === "video" && item.courseTitle ? (
            <Tooltip label={item.courseTitle}>
              <span className="flex max-w-[9rem] items-center gap-1 truncate">
                <Icon name="layers" size={9} />
                <span className="truncate">{item.courseTitle}</span>
              </span>
            </Tooltip>
          ) : item.kind === "video" ? (
            <span className="font-mono tabular-nums">{formatCount(item.durationSec)}s</span>
          ) : expandable ? (
            <span className="flex items-center gap-0.5 text-ink-dim">
              Lessons
              <Icon name="chevron-right" size={10} />
            </span>
          ) : null}
        </div>
      </div>
    </article>
  )
}
