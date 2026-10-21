import { useMemo } from "react"
import type { JobRecord, JobStatus, Quality, ToolInfo } from "../../api/types"
import { formatBytes, formatEta, formatSpeed, roleVar } from "../../lib/format"
import { courseProgressByGroup, itemPercent, type CourseProgress } from "../../lib/progress"
import { Icon, type IconName } from "../icons"
import { Badge, Button, IconButton, ProgressBar, Tooltip, cx } from "../primitives"

const STATUS_META: Record<JobStatus, { label: string; tone: "neutral" | "brand" | "success" | "danger" | "warning"; icon: IconName }> = {
  queued: { label: "Queued", tone: "neutral", icon: "clock" },
  resolving: { label: "Finding parts", tone: "neutral", icon: "search" },
  downloading: { label: "Downloading", tone: "brand", icon: "download" },
  remuxing: { label: "Remuxing", tone: "warning", icon: "film" },
  done: { label: "Done", tone: "success", icon: "check" },
  failed: { label: "Failed", tone: "danger", icon: "alert" },
  cancelled: { label: "Cancelled", tone: "neutral", icon: "x" },
  interrupted: { label: "Interrupted", tone: "warning", icon: "alert" },
}

const ACTIVE: JobStatus[] = ["queued", "resolving", "downloading", "remuxing"]
const ATTENTION: JobStatus[] = ["failed", "interrupted", "cancelled"]

export const isActive = (status: JobStatus) => ACTIVE.includes(status)

function estimateEta(job: JobRecord): number {
  if (!isActive(job.status) || job.status === "queued") return 0
  if (!job.startedAt || job.segmentsDone <= 0 || job.segmentsTotal <= 0) return 0
  const elapsed = (Date.now() - job.startedAt) / 1000
  const rate = job.segmentsDone / Math.max(elapsed, 0.5)
  return (job.segmentsTotal - job.segmentsDone) / Math.max(rate, 0.001)
}

function JobRow({
  job,
  course,
  onCancel,
  onRetry,
  onRemove,
}: {
  job: JobRecord
  course: CourseProgress | null
  onCancel: (id: string) => void
  onRetry: (id: string) => void
  onRemove: (id: string) => void
}) {
  const meta = STATUS_META[job.status]
  const percent = itemPercent(job)
  const eta = estimateEta(job)
  const active = isActive(job.status)
  const tone = meta.tone
  const toneVar = tone === "neutral" ? "var(--text-dim)" : `var(--${tone})`

  return (
    <div
      className={cx(
        "rounded-[var(--r-md)] border bg-surface-1 p-2.5",
        job.status === "failed" ? "border-danger/40" : job.status === "interrupted" ? "border-warning/40" : "border-line",
      )}
    >
      <div className="flex items-start gap-2">
        <span className="mt-0.5 shrink-0" style={{ color: toneVar }}>
          {active && job.status !== "queued" ? (
            <Icon name={meta.icon} size={13} className="animate-[spin_1.1s_linear_infinite]" />
          ) : (
            <Icon name={meta.icon} size={13} />
          )}
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[11.5px] font-medium text-ink" title={job.title}>
            {job.title}
          </p>
          <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5 text-[10px] text-ink-dim">
            <span className="font-mono uppercase" style={{ color: `color-mix(in srgb, ${roleVar(job.role)} 78%, transparent)` }}>
              {job.role}
            </span>
            <span className="inline-flex items-center gap-1">
              <Icon name="film" size={9} />
              {job.qualityLabel}
            </span>
            {job.actualQuality !== null && job.actualQuality !== job.quality ? (
              <Tooltip label={`Requested ${job.qualityLabel} but only the lower rendition was published.`}>
                <span className="inline-flex items-center gap-1 text-warning">
                  <Icon name="alert" size={9} />
                  fell back
                </span>
              </Tooltip>
            ) : null}
            {job.groupTitle ? (
              <span className="truncate text-ink-faint">· {job.groupTitle}</span>
            ) : null}
          </div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <Badge color={tone === "neutral" ? undefined : `var(--${tone})`} subtle>
            {meta.label}
          </Badge>
          {active ? (
            <IconButton icon="x" label={`Cancel ${job.title}`} onClick={() => onCancel(job.id)} />
          ) : (
            <>
              {job.status !== "done" ? (
                <IconButton icon="retry" label={`Retry ${job.title}`} onClick={() => onRetry(job.id)} />
              ) : null}
              <IconButton icon="trash" label={`Remove ${job.title} from the list`} onClick={() => onRemove(job.id)} />
            </>
          )}
        </div>
      </div>

      {active && job.status !== "queued" ? (
        <div className="mt-2 space-y-1">
          <ProgressBar value={percent} tone={tone === "neutral" ? "brand" : tone} />
          <div className="flex flex-wrap items-center gap-x-3 text-[10px] text-ink-dim tabular-nums">
            <span className="font-medium text-ink">{Math.round(percent)}%</span>
            <span>
              part {Math.min(job.segmentsDone, job.segmentsTotal || job.segmentsDone)}/{job.segmentsTotal || "?"}
            </span>
            <span>{formatBytes(job.bytes)}</span>
            {job.status === "downloading" ? <span>{formatSpeed(job.speedBps)}</span> : null}
            {eta > 0 ? <span>ETA {formatEta(eta)}</span> : null}
          </div>
        </div>
      ) : null}

      {job.status === "done" ? (
        <div className="mt-1.5 flex flex-wrap items-center gap-x-3 text-[10px] text-ink-dim">
          <span className="inline-flex items-center gap-1 text-success">
            <Icon name="check" size={10} />
            {job.remuxed ? "MP4 written" : "Transport stream kept"}
          </span>
          <span className="truncate" title={job.relativePath ?? ""}>
            {job.relativePath}
          </span>
          {job.sizeBytes ? <span className="tabular-nums">{formatBytes(job.sizeBytes)}</span> : null}
        </div>
      ) : null}

      {course ? (
        <div className="mt-2 space-y-0.5">
          <ProgressBar value={course.percent} tone="muted" height={3} />
          <div className="flex items-center justify-between gap-2 text-[9.5px] text-ink-faint tabular-nums">
            <span className="truncate">course · {course.done}/{course.total} lessons</span>
            <span>{Math.round(course.percent)}%</span>
          </div>
        </div>
      ) : null}

      {job.error ? <p className="mt-1.5 text-[10.5px] leading-relaxed text-danger">{job.error}</p> : null}
      {job.note ? <p className="mt-1 text-[10px] leading-relaxed text-warning">{job.note}</p> : null}
    </div>
  )
}

export function DownloadsPanel({
  jobs,
  qualities,
  defaults,
  tools,
  onCancel,
  onRetry,
  onRemove,
  onClearFinished,
  onOpenFolder,
  onClose,
}: {
  jobs: JobRecord[]
  qualities: Quality[]
  defaults: { quality: number; concurrency: number }
  tools: { ffmpeg: ToolInfo }
  onCancel: (id: string) => void
  onRetry: (id: string) => void
  onRemove: (id: string) => void
  onClearFinished: () => void
  onOpenFolder: () => void
  onClose: () => void
}) {
  const running = jobs.filter((job) => isActive(job.status))
  const attention = jobs.filter((job) => ATTENTION.includes(job.status))
  const finished = jobs.filter((job) => job.status === "done")
  const bytes = jobs.reduce((total, job) => total + (job.sizeBytes ?? 0), 0)
  const qualityLabel = qualities.find((option) => option.id === defaults.quality)?.label ?? "—"
  const courses = useMemo(() => courseProgressByGroup(jobs), [jobs])

  if (!jobs.length) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-2 rounded-[var(--r-md)] border border-dashed border-line px-6 py-12 text-center">
        <Icon name="download" size={20} className="text-ink-faint" />
        <p className="text-[12px] font-medium text-ink">Nothing queued yet</p>
        <p className="max-w-[16rem] text-[11px] leading-relaxed text-ink-muted">
          Pick items in Browse and press Download. Progress shows up here, and finished files land in the content folder.
        </p>
        <Button size="sm" variant="ghost" icon="folder" onClick={onOpenFolder} className="mt-1">
          Open content folder
        </Button>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-[var(--r-sm)] border border-line bg-canvas px-2.5 py-2 text-[10.5px] text-ink-dim">
        <span className="inline-flex items-center gap-1">
          <span className={cx("h-1.5 w-1.5 rounded-full", running.length ? "animate-[pulse_1.4s_ease-in-out_infinite] bg-brand" : "bg-ink-faint")} />
          {running.length} active
        </span>
        <span>{finished.length} done</span>
        {attention.length ? <span className="text-warning">{attention.length} need attention</span> : null}
        <span className="tabular-nums">{formatBytes(bytes)} on disk</span>
        <span className="ml-auto font-mono">{qualityLabel} · {defaults.concurrency} at a time</span>
      </div>

      {!tools.ffmpeg ? (
        <p className="flex items-start gap-1.5 rounded-[var(--r-sm)] border border-warning/40 bg-warning-dim px-2.5 py-2 text-[10.5px] leading-relaxed text-warning">
          <Icon name="alert" size={11} className="mt-0.5 shrink-0" />
          No ffmpeg was found, so downloads are being saved as .ts transport streams. Drop an ffmpeg binary in the app's
          bin folder to get MP4 output.
        </p>
      ) : null}

      {running.length ? (
        <section className="space-y-2">
          <h3 className="text-[10px] font-semibold tracking-[0.08em] text-ink-dim uppercase">In progress</h3>
          {running.map((job) => (
            <JobRow
              key={job.id}
              job={job}
              course={job.groupId ? (courses.get(job.groupId) ?? null) : null}
              onCancel={onCancel}
              onRetry={onRetry}
              onRemove={onRemove}
            />
          ))}
        </section>
      ) : null}

      {attention.length ? (
        <section className="space-y-2">
          <h3 className="text-[10px] font-semibold tracking-[0.08em] text-ink-dim uppercase">Needs attention</h3>
          {attention.map((job) => (
            <JobRow
              key={job.id}
              job={job}
              course={job.groupId ? (courses.get(job.groupId) ?? null) : null}
              onCancel={onCancel}
              onRetry={onRetry}
              onRemove={onRemove}
            />
          ))}
        </section>
      ) : null}

      {finished.length ? (
        <section className="space-y-2">
          <h3 className="text-[10px] font-semibold tracking-[0.08em] text-ink-dim uppercase">Finished</h3>
          {finished.map((job) => (
            <JobRow
              key={job.id}
              job={job}
              course={job.groupId ? (courses.get(job.groupId) ?? null) : null}
              onCancel={onCancel}
              onRetry={onRetry}
              onRemove={onRemove}
            />
          ))}
        </section>
      ) : null}

      <div className="flex flex-wrap items-center gap-2 pt-1">
        <Button size="sm" icon="folder" variant="secondary" onClick={onOpenFolder} className="flex-1">
          Open content folder
        </Button>
        <Button
          size="sm"
          icon="trash"
          variant="ghost"
          disabled={!finished.length && !attention.length}
          onClick={onClearFinished}
        >
          Clear finished
        </Button>
        <Button size="sm" variant="ghost" onClick={onClose}>
          Close
        </Button>
      </div>
    </div>
  )
}
