import { useEffect, useRef, type CSSProperties } from "react"
import { motion, useReducedMotion } from "motion/react"
import type { CatalogItem } from "../../api/types"
import { courseDiskState, missingLessons } from "../../lib/course"
import { formatDate, roleLabel } from "../../lib/format"
import { Icon } from "../icons"
import { Button, Chip, IconButton, ProgressBar, cx } from "../primitives"
import { panelGeometry, STACKED_STRIP_HEIGHT } from "../../lib/panel"
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

  const stacked = !attached
  // A lesson card is sized from the strip height so its poster is never cropped horizontally.
  const { stripHeight, lessonWidth, infoWidth } = panelGeometry(
    stacked ? STACKED_STRIP_HEIGHT : height,
    lessons.length,
  )

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
      style={{ ...placement, height: stacked ? undefined : height || undefined }}
      className={cx(
        "flex min-w-0 self-start overflow-hidden rounded-[var(--r-md)] border border-brand-line bg-surface-1 outline-none shadow-[0_0_0_1px_var(--accent-line)]",
        attached && "-ml-2.5 rounded-l-none",
      )}
    >
      <div className={cx("flex min-w-0 flex-1 gap-2 p-2", stacked ? "flex-col" : "items-stretch")}>
        <div
          data-course-info={course.id}
          style={stacked ? undefined : { width: infoWidth }}
          className={cx(
            "flex shrink-0 flex-col overflow-hidden rounded-[var(--r-md)] border border-line bg-surface-2",
            stacked && "relative w-full",
          )}
        >
          {stacked ? null : (
            <div className="relative h-2/5 min-h-[88px] shrink-0 overflow-hidden bg-surface-3">
              {course.thumb ? (
                <img
                  src={course.thumb}
                  alt=""
                  loading="lazy"
                  decoding="async"
                  className="h-full w-full object-cover"
                />
              ) : null}
              <div className="pointer-events-none absolute inset-0 bg-gradient-to-t from-surface-2 via-surface-2/25 to-transparent" />
              <span className="absolute top-1.5 left-1.5 rounded-[var(--r-xs)] bg-black/60 px-1.5 py-0.5 text-[9px] font-semibold tracking-[0.06em] text-white/85 uppercase">
                {roleLabel(course.role)}
              </span>
              <span className="absolute top-1 right-1">
                <IconButton icon="x" label="Close lessons" onClick={onClose} />
              </span>
            </div>
          )}

          <div
            className={cx(
              "flex min-h-0 flex-1 flex-col p-2.5",
              stacked && "gap-2 sm:flex-row sm:items-end sm:gap-4 sm:pr-10",
            )}
          >
            <div className="min-w-0 flex-1">
              <p className="flex items-center gap-1.5 text-[9.5px] font-semibold tracking-[0.06em] text-ink-faint uppercase">
                {stacked ? (
                  <span className="rounded-[var(--r-xs)] bg-surface-3 px-1.5 py-0.5 text-ink-muted">
                    {roleLabel(course.role)}
                  </span>
                ) : null}
                {formatDate(course.date)}
              </p>
              <h2 className="mt-0.5 line-clamp-3 text-[12px] font-semibold leading-snug text-ink">{course.title}</h2>

              <div className="mt-2">
                <ProgressBar
                  value={state.total ? (state.have / state.total) * 100 : 0}
                  tone={state.complete ? "success" : "brand"}
                />
                <div className="mt-1 flex items-baseline justify-between gap-2 text-[10px] tabular-nums">
                  <span className="text-ink-muted">
                    {state.have} of {state.total} on disk
                  </span>
                  {state.complete ? (
                    <span className="inline-flex items-center gap-1 text-[9.5px] font-semibold tracking-[0.04em] text-success uppercase">
                      <Icon name="check" size={9} strokeWidth={3} />
                      Complete
                    </span>
                  ) : (
                    <span className="text-ink-faint">{missing.length} to go</span>
                  )}
                </div>
              </div>
            </div>

            <div className={cx("flex flex-col gap-1.5", stacked ? "sm:w-56 sm:shrink-0" : "mt-auto pt-2")}>
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
          </div>

          {stacked ? (
            <span className="absolute top-1 right-1">
              <IconButton icon="x" label="Close lessons" onClick={onClose} />
            </span>
          ) : null}
        </div>

        <div
          style={stacked ? { height: stripHeight } : undefined}
          className={cx(
            "min-h-0 min-w-0 overflow-x-auto overflow-y-hidden [mask-image:linear-gradient(to_right,black_calc(100%_-_26px),transparent)]",
            stacked ? "shrink-0" : "flex-1",
          )}
        >
          <ol className="grid h-full grid-flow-col grid-rows-2 auto-cols-max gap-2">
            {lessons.map((lesson, index) => (
              <LessonCard
                key={lesson.id}
                lesson={lesson}
                index={index}
                width={lessonWidth}
                selected={isSelected(lesson.id)}
                quality={downloaded.get(lesson.id)}
                onToggle={onToggleLesson}
                onPreview={onPreview}
              />
            ))}
          </ol>
        </div>
      </div>
    </motion.section>
  )
}
