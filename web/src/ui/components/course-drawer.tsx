import type { CatalogItem } from "../../api/types"
import { courseDiskState, missingLessons } from "../../lib/course"
import { formatDate, formatDuration, roleLabel } from "../../lib/format"
import { Icon } from "../icons"
import { Button, Chip, Drawer, IconButton, ProgressBar, cx } from "../primitives"

export function CourseDrawer({
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
}: {
  course: CatalogItem | null
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
}) {
  const state = courseDiskState(lessons, downloaded)
  const missing = missingLessons(lessons, downloaded)
  const selected = lessons.filter((lesson) => isSelected(lesson.id))
  const queue = (selected.length ? selected : missing).map((lesson) => lesson.id)

  return (
    <Drawer
      open={Boolean(course)}
      onOpenChange={(open) => {
        if (!open) onClose()
      }}
      title={course?.title ?? "Course"}
      description={
        course
          ? `${lessons.length} lesson${lessons.length === 1 ? "" : "s"} · ${roleLabel(course.role)} · ${formatDate(course.date)}`
          : undefined
      }
      width="min(520px, 100vw)"
      footer={
        <Button
          variant="primary"
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
      }
    >
      <div className="-mx-4 -mt-3 border-b border-line px-4 py-3">
        <div className="flex items-center justify-between gap-2">
          <span className="text-[11px] text-ink-muted tabular-nums">
            {state.have} of {state.total} lessons on disk
          </span>
          {state.complete ? (
            <span className="inline-flex items-center gap-1 text-[10px] font-semibold tracking-[0.04em] text-success uppercase">
              <Icon name="check" size={10} strokeWidth={3} />
              Complete
            </span>
          ) : (
            <span className="text-[10px] text-ink-faint tabular-nums">{missing.length} to go</span>
          )}
        </div>
        <ProgressBar
          className="mt-2"
          value={state.total ? (state.have / state.total) * 100 : 0}
          tone={state.complete ? "success" : "brand"}
        />
      </div>

      <div className="-mx-4 flex items-center gap-1.5 border-b border-line px-4 py-2">
        <Chip onClick={onSelectAll} className="text-ink-muted">
          <Icon name="plus" size={10} />
          Select all
        </Chip>
        <Chip onClick={onClear} className="text-ink-dim">
          <Icon name="x" size={10} />
          Clear
        </Chip>
        <span className="ml-auto text-[10px] text-ink-faint tabular-nums">
          {selectedCount} selected
        </span>
      </div>

      <ol className="-mx-4 -mb-3 divide-y divide-line">
        {lessons.map((lesson, index) => {
          const quality = downloaded.get(lesson.id)
          const active = isSelected(lesson.id)
          return (
            <li key={lesson.id} className={cx("flex items-center gap-1 px-3 py-2", active && "bg-brand-dim/25")}>
              <button
                type="button"
                onClick={(event) => onToggleLesson(lesson.id, event.shiftKey)}
                aria-pressed={active}
                aria-label={`${active ? "Deselect" : "Select"} ${lesson.title}`}
                className="flex min-w-0 flex-1 items-center gap-2.5 rounded-[var(--r-xs)] px-1 py-0.5 text-left tab-stop"
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
    </Drawer>
  )
}
