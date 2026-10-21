import { useState } from "react"
import { motion, useReducedMotion } from "motion/react"
import type { CatalogItem } from "../../api/types"
import { formatDuration, roleVar } from "../../lib/format"
import { Icon } from "../icons"
import { cx } from "../primitives"

function isInteractive(target: EventTarget | null): boolean {
  return target instanceof Element && Boolean(target.closest("button, a, input, select, textarea"))
}

/**
 * One lesson inside a course panel. It is a video, so it gets the shape people
 * already read here: a poster with its duration, the on-disk quality in the
 * corner, and the title under it. Everything the old row could do still works —
 * a click toggles the lesson (shift for the range), the checkbox is the tab
 * stop, and the play button previews.
 */
export function LessonCard({
  lesson,
  index,
  width,
  selected,
  quality,
  onToggle,
  onPreview,
}: {
  lesson: CatalogItem
  index: number
  /** The card's width in pixels, derived from the strip height so the poster is not cropped. */
  width?: number
  selected: boolean
  /** The on-disk quality label, e.g. `1080p`; absent means not downloaded. */
  quality?: string
  onToggle: (id: string, additive: boolean) => void
  onPreview: (item: CatalogItem) => void
}) {
  const [brokenThumb, setBrokenThumb] = useState(false)
  const reduce = useReducedMotion()
  const color = roleVar(lesson.role)
  const showPoster = Boolean(lesson.thumb) && !brokenThumb
  const number = String(index + 1).padStart(2, "0")

  return (
    <motion.li
      layout={!reduce}
      transition={reduce ? { duration: 0 } : { type: "spring", stiffness: 420, damping: 40, mass: 0.7 }}
      style={width ? { width } : undefined}
      data-lesson={lesson.id}
      data-selected={selected ? "1" : undefined}
      data-on-disk={quality ? "1" : undefined}
      onClick={(event) => {
        if (isInteractive(event.target)) return
        onToggle(lesson.id, event.shiftKey && !(event.ctrlKey || event.metaKey))
      }}
      className={cx(
        "group relative flex min-h-0 cursor-pointer flex-col overflow-hidden rounded-[var(--r-md)] border bg-surface-1 transition-[border-color,background-color] duration-[var(--dur-fast)]",
        selected
          ? "border-brand-line bg-surface-2 shadow-[0_0_0_1px_var(--accent-line)]"
          : quality
            ? "border-success/45 hover:border-success/70 hover:bg-surface-2"
            : "border-line hover:border-line-strong hover:bg-surface-2",
      )}
    >
      <div
        className="relative min-h-0 w-full flex-1 overflow-hidden bg-surface-2"
        data-poster={showPoster ? "image" : "fallback"}
      >
        {showPoster ? (
          <img
            src={lesson.thumb}
            alt=""
            loading="lazy"
            decoding="async"
            onError={() => setBrokenThumb(true)}
            className="h-full w-full object-cover transition-transform duration-[var(--dur-slow)] ease-out group-hover:scale-[1.04]"
          />
        ) : (
          <div
            className="absolute inset-0 grid place-items-center"
            style={{
              backgroundImage: `radial-gradient(120% 110% at 18% 0%, color-mix(in srgb, ${color} 26%, transparent), transparent 62%), repeating-linear-gradient(135deg, rgba(255,255,255,0.04) 0 1px, transparent 1px 9px)`,
            }}
          >
            <span
              className="font-mono text-[20px] font-bold tracking-[0.18em]"
              style={{ color: `color-mix(in srgb, ${color} 72%, transparent)` }}
            >
              {number}
            </span>
          </div>
        )}

        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-12 bg-gradient-to-t from-black/70 to-transparent" />

        <span className="pointer-events-none absolute top-1.5 left-1.5 rounded-[var(--r-xs)] bg-black/65 px-1.5 py-0.5 font-mono text-[9.5px] font-medium text-white/85 tabular-nums">
          {number}
        </span>

        <button
          type="button"
          aria-pressed={selected}
          aria-label={`${selected ? "Deselect" : "Select"} ${lesson.title}`}
          onClick={(event) => {
            event.stopPropagation()
            onToggle(lesson.id, event.shiftKey && !(event.ctrlKey || event.metaKey))
          }}
          className={cx(
            "absolute top-1.5 right-1.5 grid h-[22px] w-[22px] place-items-center rounded-[var(--r-xs)] border transition-colors duration-[var(--dur-fast)] tab-stop",
            selected
              ? "border-brand bg-brand text-brand-ink"
              : "border-white/25 bg-black/45 text-white/80 backdrop-blur-sm hover:border-white/60 hover:text-white",
          )}
        >
          <Icon name={selected ? "check" : "plus"} size={12} strokeWidth={2.6} />
        </button>

        <span className="pointer-events-none absolute right-1.5 bottom-1.5 rounded-[var(--r-xs)] bg-black/70 px-1.5 py-0.5 font-mono text-[9.5px] font-medium text-white/90 tabular-nums">
          {formatDuration(lesson.durationSec)}
        </span>

        {quality ? (
          <span className="pointer-events-none absolute bottom-1.5 left-1.5 inline-flex items-center gap-1 rounded-[var(--r-xs)] bg-success-dim px-1.5 py-0.5 text-[9px] font-semibold tracking-[0.04em] text-success uppercase">
            <Icon name="check" size={9} strokeWidth={3} />
            {quality}
          </span>
        ) : null}
      </div>

      <div className="flex items-start gap-1 px-2 py-1.5">
        <h3 className="line-clamp-2 min-h-[2.75em] flex-1 text-[11px] leading-snug font-medium text-ink">
          {lesson.title}
        </h3>
        <button
          type="button"
          aria-label={`Preview ${lesson.title}`}
          onClick={(event) => {
            event.stopPropagation()
            onPreview(lesson)
          }}
          className="grid h-6 w-6 shrink-0 place-items-center rounded-[var(--r-xs)] text-ink-faint transition-colors duration-[var(--dur-fast)] hover:bg-surface-3 hover:text-ink tab-stop"
        >
          <Icon name="play" size={11} />
        </button>
      </div>
    </motion.li>
  )
}
