import { useState } from "react"
import type { Quality } from "../../api/types"
import { Icon } from "../icons"
import { Button, IconButton, Switch, Tooltip, cx } from "../primitives"

export function SelectionBar({
  count,
  visibleCount,
  qualities,
  quality,
  onQualityChange,
  remux,
  onRemuxChange,
  skipExisting,
  onSkipExistingChange,
  onDownload,
  onSelectAll,
  onClear,
  busy,
}: {
  count: number
  visibleCount: number
  qualities: Quality[]
  quality: number
  onQualityChange: (quality: number) => void
  remux: boolean
  onRemuxChange: (value: boolean) => void
  skipExisting: boolean
  onSkipExistingChange: (value: boolean) => void
  onDownload: () => void
  onSelectAll: () => void
  onClear: () => void
  busy: boolean
}) {
  const [expanded, setExpanded] = useState(false)

  if (count === 0) return null

  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-0 z-[var(--z-sticky)] flex justify-center px-3 pb-[max(12px,env(safe-area-inset-bottom))]">
      <div className="pointer-events-auto w-full max-w-[860px] rounded-[var(--r-lg)] border border-line-strong bg-surface-2/97 shadow-elev-lg backdrop-blur-md">
        <div className="flex flex-wrap items-center gap-2 px-3 py-2">
          <span className="inline-flex h-6 items-center gap-1.5 rounded-full bg-brand-dim px-2.5 text-[11px] font-semibold text-brand tabular-nums">
            <Icon name="check" size={11} strokeWidth={3} />
            {count.toLocaleString()} selected
          </span>

          <button
            type="button"
            onClick={onSelectAll}
            disabled={visibleCount === 0 || visibleCount === count}
            className="h-7 rounded-[var(--r-sm)] px-2 text-[11px] font-medium text-ink-muted transition-colors hover:bg-surface-3 hover:text-ink disabled:opacity-40 tab-stop"
          >
            Select all {visibleCount.toLocaleString()} filtered
          </button>

          <button
            type="button"
            onClick={onClear}
            className="h-7 rounded-[var(--r-sm)] px-2 text-[11px] font-medium text-ink-dim transition-colors hover:bg-surface-3 hover:text-ink tab-stop"
          >
            Clear
          </button>

          <div className="ml-auto flex items-center gap-2">
            <span className="hidden items-center gap-1.5 text-[10.5px] text-ink-dim sm:flex">
              <Icon name="chevron-down" size={11} className={cx("transition-transform", expanded && "rotate-180")} />
              Options
            </span>
            <IconButton
              icon={expanded ? "chevron-down" : "chevron-right"}
              label={expanded ? "Hide download options" : "Show download options"}
              onClick={() => setExpanded((value) => !value)}
              className="sm:hidden"
            />
            <Button variant="primary" size="md" icon="download" loading={busy} onClick={onDownload} className="px-4">
              Download {count.toLocaleString()}
            </Button>
          </div>
        </div>

        <div
          className={cx(
            "flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-line px-3 py-2",
            expanded ? "block" : "hidden sm:flex",
          )}
        >
          <label className="flex items-center gap-1.5">
            <span className="text-[10.5px] font-medium text-ink-dim">Quality</span>
            <select
              value={quality}
              onChange={(event) => onQualityChange(Number(event.target.value))}
              className="select-chevron h-7 rounded-[var(--r-sm)] border border-line bg-surface-1 pr-6 pl-2 text-[11px] font-medium text-ink outline-none focus:border-line-strong tab-stop"
            >
              {qualities.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label}
                </option>
              ))}
            </select>
          </label>

          <Switch id="remux-toggle" checked={remux} onCheckedChange={onRemuxChange} label="Remux to MP4" />
          <Switch
            id="skip-toggle"
            checked={skipExisting}
            onCheckedChange={onSkipExistingChange}
            label="Skip downloaded"
          />

          <Tooltip label="Courses expand to one job per lesson.">
            <span className="ml-auto flex items-center gap-1 text-[10px] text-ink-faint">
              <Icon name="alert" size={10} />
              Courses expand per lesson
            </span>
          </Tooltip>

          <IconButton icon="x" label="Clear selection" onClick={onClear} />
        </div>
      </div>
    </div>
  )
}
