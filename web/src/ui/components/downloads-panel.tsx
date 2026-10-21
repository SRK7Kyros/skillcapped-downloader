import { useMemo, useState } from "react"
import type { JobRecord, JobStatus, Quality, ToolInfo } from "../../api/types"
import { formatBytes, formatEta, formatSpeed, roleVar } from "../../lib/format"
import { groupQueue, itemPercent, queueProgress, type QueueGroup } from "../../lib/progress"
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
  onCancel,
  onRetry,
  onRemove,
}: {
  job: JobRecord
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

      {job.error ? <p className="mt-1.5 text-[10.5px] leading-relaxed text-danger">{job.error}</p> : null}
      {job.note ? <p className="mt-1 text-[10px] leading-relaxed text-warning">{job.note}</p> : null}
    </div>
  )
}

const STATE_TONE: Record<QueueGroup["state"], "brand" | "warning" | "success"> = {
  active: "brand",
  attention: "warning",
  finished: "success",
}

/**
 * One course in the queue: a bar for the whole run that opens into its lessons.
 * Collapsed by default — the header already names the lesson being fetched, so
 * the per-item bars are a click away rather than filling the panel.
 */
function GroupCard({
  group,
  open,
  onToggle,
  onCancel,
  onRetry,
  onRemove,
}: {
  group: QueueGroup
  open: boolean
  onToggle: () => void
  onCancel: (id: string) => void
  onRetry: (id: string) => void
  onRemove: (id: string) => void
}) {
  const active = group.jobs.filter((job) => job.status === "queued" ? false : isActive(job.status)).length

  return (
    <div className="rounded-[var(--r-md)] border border-line bg-surface-1">
      <button
        type="button"
        aria-expanded={open}
        onClick={onToggle}
        className="tab-stop flex w-full items-start gap-2 p-2.5 pb-1.5 text-left"
      >
        <Icon name={open ? "chevron-down" : "chevron-right"} size={12} className="mt-1 shrink-0 text-ink-faint" />
        <span className="min-w-0 flex-1">
          <span className="flex items-baseline gap-2">
            <span className="min-w-0 flex-1 truncate text-[11.5px] font-medium text-ink" title={group.title}>
              {group.title}
            </span>
            <span className="shrink-0 font-mono text-[10px] text-ink-dim tabular-nums">{Math.round(group.percent)}%</span>
          </span>
          <span className="mt-0.5 flex flex-wrap items-center gap-x-2 text-[10px] text-ink-dim">
            <span>
              {group.done}/{group.total} lessons
            </span>
            {active ? <span className="text-brand">{active} downloading</span> : null}
            {group.failed ? <span className="text-warning">{group.failed} failed</span> : null}
            {group.state === "active" ? <span className="min-w-0 truncate text-ink-faint">· {group.lead.title}</span> : null}
          </span>
        </span>
      </button>

      <div className="px-2.5 pb-2 pl-[26px]">
        <ProgressBar value={group.percent} tone={STATE_TONE[group.state]} height={3} />
      </div>

      {open ? (
        <div className="space-y-2 border-t border-line p-2">
          {group.jobs.map((job) => (
            <JobRow key={job.id} job={job} onCancel={onCancel} onRetry={onRetry} onRemove={onRemove} />
          ))}
        </div>
      ) : null}
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
  const qualityLabel = qualities.find((option) => option.id === defaults.quality)?.label ?? "—"
  const queue = useMemo(() => queueProgress(jobs), [jobs])
  const groups = useMemo(() => groupQueue(jobs), [jobs])
  const [openGroups, setOpenGroups] = useState<string[]>([])
  const toggleGroup = (key: string) =>
    setOpenGroups((keys) => (keys.includes(key) ? keys.filter((open) => open !== key) : [...keys, key]))
  const sections = [
    { key: "active", label: "In progress", groups: groups.filter((group) => group.state === "active") },
    { key: "attention", label: "Needs attention", groups: groups.filter((group) => group.state === "attention") },
    { key: "finished", label: "Finished", groups: groups.filter((group) => group.state === "finished") },
  ]

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
      <section className="space-y-1.5 rounded-[var(--r-md)] border border-line bg-surface-1 p-2.5">
        <div className="flex items-baseline justify-between gap-2">
          <p className="text-[10px] font-semibold tracking-[0.08em] text-ink-dim uppercase">Queue progress</p>
          <span className="font-mono text-[12px] font-medium text-ink tabular-nums">{Math.round(queue.percent)}%</span>
        </div>
        <ProgressBar value={queue.percent} height={6} />
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[10.5px] text-ink-dim tabular-nums">
          <span className="font-medium text-ink">
            {queue.done} of {queue.total} downloads
          </span>
          {queue.active ? (
            <span className="inline-flex items-center gap-1">
              <span className="h-1.5 w-1.5 animate-[pulse_1.4s_ease-in-out_infinite] rounded-full bg-brand" />
              {queue.active} active
            </span>
          ) : null}
          {queue.attention ? <span className="text-warning">{queue.attention} need attention</span> : null}
          {queue.speed > 0 ? <span>{formatSpeed(queue.speed)}</span> : null}
          {queue.eta > 0 ? <span>ETA {formatEta(queue.eta)}</span> : null}
          <span className="ml-auto inline-flex items-center gap-2">
            <span>{formatBytes(queue.bytes)} on disk</span>
            <span className="font-mono">
              {qualityLabel} · {defaults.concurrency} at a time
            </span>
          </span>
        </div>
      </section>

      {!tools.ffmpeg ? (
        <p className="flex items-start gap-1.5 rounded-[var(--r-sm)] border border-warning/40 bg-warning-dim px-2.5 py-2 text-[10.5px] leading-relaxed text-warning">
          <Icon name="alert" size={11} className="mt-0.5 shrink-0" />
          No ffmpeg was found, so downloads are being saved as .ts transport streams. Drop an ffmpeg binary in the app's
          bin folder to get MP4 output.
        </p>
      ) : null}

      {sections.map((section) =>
        section.groups.length ? (
          <section key={section.key} className="space-y-2">
            <h3 className="text-[10px] font-semibold tracking-[0.08em] text-ink-dim uppercase">{section.label}</h3>
            {section.groups.map((group) =>
              group.kind === "single" ? (
                <JobRow
                  key={group.key}
                  job={group.jobs[0]}
                  onCancel={onCancel}
                  onRetry={onRetry}
                  onRemove={onRemove}
                />
              ) : (
                <GroupCard
                  key={group.key}
                  group={group}
                  open={openGroups.includes(group.key)}
                  onToggle={() => toggleGroup(group.key)}
                  onCancel={onCancel}
                  onRetry={onRetry}
                  onRemove={onRemove}
                />
              ),
            )}
          </section>
        ) : null,
      )}

      <div className="flex flex-wrap items-center gap-2 pt-1">
        <Button size="sm" icon="folder" variant="secondary" onClick={onOpenFolder} className="flex-1">
          Open content folder
        </Button>
        <Button
          size="sm"
          icon="trash"
          variant="ghost"
          disabled={!queue.done && !queue.attention}
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
