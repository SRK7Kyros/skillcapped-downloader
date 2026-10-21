import { useEffect, useRef, type CSSProperties } from "react"
import { motion, useReducedMotion } from "motion/react"
import type { CatalogItem } from "../../api/types"
import { courseDiskState, missingLessons } from "../../lib/course"
import { formatDate, formatDuration, roleLabel } from "../../lib/format"
import { Icon } from "../icons"
import { Button, Chip, IconButton, ProgressBar, cx } from "../primitives"

export function CoursePanel({
  course,
  lessons,
  downloaded,
  selectedCount,
  isSelected,
  onToggleLesson,
  onSelectAll,
  onClear,
  onPreview,
  onDownload,
  onClose,
  busy,
  placement,
  attached,
}: {
  course: CatalogItem
  lessons: CatalogItem[]
  downloaded: Map<string, string>
  selectedCount: number
  isSelected: (id: string) => boolean
  onToggleLesson: (id: string, additive: boolean) => void
  onSelectAll: () => void
  onClear: () => void
  onPreview: (item: CatalogItem) => void
  onDownload: (ids: string[]) => void
  onClose: () => void
  busy: boolean
  placement: CSSProperties
  attached: boolean
}) {
  const state = courseDiskState(lessons, downloaded)
  const missing = missingLessons(lessons, downloaded)
  const selected = lessons.filter((lesson) => isSelected(lesson.id))
  const queue = (selected.length ? selected : missing).map((lesson) => lesson.id)
  const reduce = useReducedMotion()
  const panel = useRef<HTMLElement>(null)

  useEffect(() => {
    panel.current?.focus({ preventScroll: true })
  }, [course.id])

  return (
    <motion.section
      ref={panel}
      tabIndex={-1}
      data-course-panel={course.id}
      aria-label={`${course.title} lessons`}
      layout={!reduce}
      initial={{ opacity: 0, x: reduce ? 0 : -28 }}
      animate={{ opacity: 1, x: 0 }}
      exit={{ opacity: 0, x: reduce ? 0 : -28 }}
      transition={reduce ? { duration: 0 } : { type: "spring", stiffness: 380, damping: 36, mass: 0.85 }}
      style={placement}
      className={cx(
        "flex min-w-0 flex-col self-start overflow-hidden rounded-[var(--r-md)] border border-brand-line bg-surface-1 outline-none shadow-[0_0_0_1px_var(--accent-line)] @container",
        attached && "-ml-2.5 rounded-l-none",
      )}
    >
      <header className="flex flex-wrap items-start gap-x-3 gap-y-2 border-b border-line px-4 py-3">
        <div className="min-w-0 flex-1 basis-full @[520px]:basis-0">
          <p className="text-[10px] font-semibold tracking-[0.06em] text-ink-faint uppercase">
            {roleLabel(course.role)} · {formatDate(course.date)}
          </p>
          <h2 className="mt-0.5 line-clamp-2 text-[13px] font-semibold text-ink @[520px]:line-clamp-1">
            {course.title}
          </h2>
        </div>
        <div className="flex shrink-0 items-center gap-1.5">
          <Chip onClick={onSelectAll} className="text-ink-muted">
            <Icon name="plus" size={10} />
            Select all
          </Chip>
          <Chip onClick={onClear} className="text-ink-dim">
            <Icon name="minus" size={10} />
            Clear
          </Chip>
          <IconButton icon="x" label="Close lessons" onClick={onClose} />
        </div>
        <div className="basis-full">
          <ProgressBar
            value={state.total ? (state.have / state.total) * 100 : 0}
            tone={state.complete ? "success" : "brand"}
          />
          <div className="mt-1 flex items-center justify-between gap-2 text-[10px] tabular-nums">
            <span className="text-ink-muted">
              {state.have} of {state.total} on disk
            </span>
            {state.complete ? (
              <span className="inline-flex items-center gap-1 font-semibold tracking-[0.04em] text-success uppercase">
                <Icon name="check" size={10} strokeWidth={3} />
                Complete
              </span>
            ) : (
              <span className="text-ink-faint">{missing.length} to go</span>
            )}
          </div>
        </div>
      </header>

      <ol className="grid max-h-[min(52vh,420px)] grid-cols-1 gap-x-3 overflow-y-auto px-2 py-1.5 @[430px]:grid-cols-2 @[900px]:grid-cols-3">
        {lessons.map((lesson, index) => {
          const quality = downloaded.get(lesson.id)
          const active = isSelected(lesson.id)
          return (
            <li
              key={lesson.id}
              className={cx(
                "flex items-center gap-1 border-b border-line/40 px-1 transition-colors duration-[var(--dur-fast)] hover:bg-surface-2",
                active && "bg-brand-dim/25",
              )}
            >
              <button
                type="button"
                onClick={(event) => onToggleLesson(lesson.id, event.shiftKey && !(event.ctrlKey || event.metaKey))}
                aria-pressed={active}
                aria-label={`${active ? "Deselect" : "Select"} ${lesson.title}`}
                className="flex min-w-0 flex-1 items-center gap-2.5 rounded-[var(--r-xs)] px-1 py-1.5 text-left tab-stop"
              >
                <span
                  className={cx(
                    "grid h-4 w-4 shrink-0 place-items-center rounded-[3px] border",
                    active ? "border-brand bg-brand text-brand-ink" : "border-line-strong text-transparent",
                  )}
                >
                  <Icon name="check" size={10} strokeWidth={3} />
                </span>
                <span className="w-4 shrink-0 font-mono text-[10px] text-ink-faint tabular-nums">
                  {String(index + 1).padStart(2, "0")}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="line-clamp-2 block text-[11.5px] leading-snug font-medium text-ink">
                    {lesson.title}
                  </span>
                  <span className="block text-[10px] text-ink-faint tabular-nums">
                    {formatDuration(lesson.durationSec)}
                    {lesson.staff ? ` · ${lesson.staff}` : ""}
                  </span>
                </span>
              </button>
              {quality ? (
                <span className="inline-flex shrink-0 items-center gap-1 rounded-[var(--r-xs)] bg-success-dim px-1.5 py-0.5 text-[9.5px] font-semibold tracking-[0.04em] text-success uppercase">
                  <Icon name="check" size={9} strokeWidth={3} />
                  {quality}
                </span>
              ) : null}
              <IconButton icon="play" label={`Preview ${lesson.title}`} onClick={() => onPreview(lesson)} />
            </li>
          )
        })}
      </ol>

      <footer className="mt-auto flex flex-wrap items-center gap-x-3 gap-y-2 border-t border-line px-4 py-2.5">
        <span className="text-[10.5px] text-ink-faint tabular-nums">{selectedCount} selected</span>
        <span className="hidden text-[10px] text-ink-faint @[560px]:inline">Shift-click a range, Ctrl-click one</span>
        <Button
          variant="primary"
          size="sm"
          className="ml-auto"
          icon="download"
          loading={busy}
          disabled={!queue.length}
          onClick={() => onDownload(queue)}
        >
          {selected.length
            ? `Download ${selected.length} selected`
            : missing.length
              ? `Download ${missing.length} missing`
              : "Every lesson is on disk"}
        </Button>
      </footer>
    </motion.section>
  )
}
