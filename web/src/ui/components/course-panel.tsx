import { useEffect, useRef, type CSSProperties } from "react"
import { motion, useReducedMotion } from "motion/react"
import type { CatalogItem } from "../../api/types"
import { panelGeometry, stripHeightFor } from "../../lib/panel"
import { cx } from "../primitives"
import { LessonCard } from "./lesson-card"

export function CoursePanel({
  course,
  lessons,
  downloaded,
  isSelected,
  onToggleLesson,
  onPreview,
  placement,
  height,
  attached,
}: {
  course: CatalogItem
  lessons: CatalogItem[]
  downloaded: Map<string, string>
  isSelected: (id: string) => boolean
  onToggleLesson: (id: string, additive: boolean) => void
  onPreview: (item: CatalogItem) => void
  placement: CSSProperties
  /** The open card's height, so the panel never stretches its grid row. */
  height: number
  attached: boolean
}) {
  const reduce = useReducedMotion()
  const panel = useRef<HTMLElement>(null)

  const stacked = !attached
  // A lesson card is sized from the strip height so its poster is never cropped horizontally.
  const { stripHeight, lessonWidth } = panelGeometry(stripHeightFor(height, attached), lessons.length)

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
        "flex min-w-0 self-start overflow-hidden rounded-[var(--r-md)] border border-brand-line bg-surface-1 p-2 outline-none shadow-[0_0_0_1px_var(--accent-line)]",
        attached && "-ml-2.5 rounded-l-none",
      )}
    >
      <div
        data-strip
        style={stacked ? { height: stripHeight } : undefined}
        className="min-h-0 min-w-0 flex-1 overflow-x-auto overflow-y-hidden [mask-image:linear-gradient(to_right,black_calc(100%_-_26px),transparent)]"
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
    </motion.section>
  )
}
