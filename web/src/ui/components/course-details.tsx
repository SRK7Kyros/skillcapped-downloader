import type { CatalogItem } from "../../api/types"
import { courseDiskState, missingLessons } from "../../lib/course"
import { Icon } from "../icons"
import { Button, Chip, ProgressBar } from "../primitives"

/**
 * The open course's own card carries this block: progress, selection and the
 * download button used to live in a duplicate card at the head of the lesson
 * strip, which showed the same poster and title twice side by side.
 */
export function CourseDetails({
  course,
  lessons,
  downloaded,
  selectedIds,
  onSelectAll,
  onClear,
  onDownload,
  busy,
}: {
  course: CatalogItem
  lessons: CatalogItem[]
  downloaded: Map<string, string>
  /** The lesson ids of this course that are currently selected. */
  selectedIds: string[]
  onSelectAll: () => void
  onClear: () => void
  onDownload: (ids: string[]) => void
  busy: boolean
}) {
  const state = courseDiskState(lessons, downloaded)
  const missing = missingLessons(lessons, downloaded)
  const selected = lessons.filter((lesson) => selectedIds.includes(lesson.id))
  const queue = (selected.length ? selected : missing).map((lesson) => lesson.id)

  return (
    <div
      data-course-details={course.id}
      onClick={(event) => event.stopPropagation()}
      className="flex flex-col gap-1.5 border-t border-line px-2.5 pt-2 pb-2.5"
    >
      <ProgressBar
        value={state.total ? (state.have / state.total) * 100 : 0}
        tone={state.complete ? "success" : "brand"}
      />
      <div className="flex items-baseline justify-between gap-2 text-[10px] tabular-nums">
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
      <div className="flex flex-wrap items-center gap-1">
        <Chip onClick={onSelectAll} className="shrink-0 whitespace-nowrap text-ink-muted">
          Select all
        </Chip>
        <Chip onClick={onClear} className="shrink-0 whitespace-nowrap text-ink-dim">
          Clear
        </Chip>
        <span className="ml-auto text-[9.5px] whitespace-nowrap text-ink-faint tabular-nums">
          {selected.length} selected
        </span>
      </div>
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
  )
}
