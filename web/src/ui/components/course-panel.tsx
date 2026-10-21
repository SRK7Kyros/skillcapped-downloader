import { useEffect, useRef, type CSSProperties } from "react"
import { motion, useReducedMotion } from "motion/react"
import type { CatalogItem } from "../../api/types"
import { courseDiskState, missingLessons } from "../../lib/course"
import { formatDate, roleLabel } from "../../lib/format"
import { Icon } from "../icons"
import { Button, Chip, IconButton, ProgressBar, cx } from "../primitives"
import { LessonCard } from "./lesson-card"

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
  height,
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
  /** The open card's height, so the panel never stretches its grid row. */
  height: number
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
      style={{ ...placement, height: height || undefined }}
      className={cx(
        "flex min-w-0 self-start overflow-hidden rounded-[var(--r-md)] border border-brand-line bg-surface-1 outline-none shadow-[0_0_0_1px_var(--accent-line)] @container",
        attached && "-ml-2.5 rounded-l-none",
      )}
    >
      <aside className="flex w-[136px] shrink-0 flex-col gap-2 overflow-hidden border-r border-line p-2.5 @[440px]:w-[168px] @[640px]:w-[196px]">
        <div className="flex items-start gap-1">
          <div className="min-w-0 flex-1">
            <p className="text-[9.5px] font-semibold tracking-[0.06em] text-ink-faint uppercase">
              {roleLabel(course.role)} · {formatDate(course.date)}
            </p>
            <h2 className="mt-1 line-clamp-3 text-[12px] font-semibold leading-snug text-ink">{course.title}</h2>
          </div>
          <IconButton icon="x" label="Close lessons" onClick={onClose} />
        </div>

        <div>
          <ProgressBar
            value={state.total ? (state.have / state.total) * 100 : 0}
            tone={state.complete ? "success" : "brand"}
          />
          <p className="mt-1 text-[10px] text-ink-muted tabular-nums">
            {state.have} of {state.total} on disk
          </p>
          {state.complete ? (
            <p className="mt-0.5 inline-flex items-center gap-1 text-[9.5px] font-semibold tracking-[0.04em] text-success uppercase">
              <Icon name="check" size={9} strokeWidth={3} />
              Complete
            </p>
          ) : (
            <p className="mt-0.5 text-[10px] text-ink-faint tabular-nums">{missing.length} to go</p>
          )}
        </div>

        <div className="mt-auto flex flex-col gap-1.5">
          <p className="text-[9.5px] leading-snug text-ink-faint">Shift-click a range, Ctrl-click one.</p>
          <div className="flex flex-wrap gap-1">
            <Chip onClick={onSelectAll} className="text-ink-muted">
              <Icon name="plus" size={10} />
              Select all
            </Chip>
            <Chip onClick={onClear} className="text-ink-dim">
              <Icon name="minus" size={10} />
              Clear
            </Chip>
          </div>
          <span className="text-[10px] text-ink-faint tabular-nums">{selectedCount} selected</span>
          <Button
            variant="primary"
            size="sm"
            className="w-full"
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
        </div>
      </aside>

      <div className="min-w-0 flex-1 overflow-x-auto overflow-y-hidden p-2 [mask-image:linear-gradient(to_right,black_calc(100%_-_26px),transparent)]">
        <ol className="grid h-full grid-flow-col grid-rows-2 auto-cols-[minmax(148px,1fr)] gap-2 @[560px]:auto-cols-[minmax(168px,1fr)]">
          {lessons.map((lesson, index) => (
            <LessonCard
              key={lesson.id}
              lesson={lesson}
              index={index}
              selected={isSelected(lesson.id)}
              quality={downloaded.get(lesson.id)}
              onToggle={onToggleLesson}
              onPreview={onPreview}
            />
          ))}
        </ol>
      </div>
    </motion.section>
  )
}
