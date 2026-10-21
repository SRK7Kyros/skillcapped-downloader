import type { Toast } from "../store"
import { Icon } from "../icons"
import { cx } from "../primitives"

const TONE: Record<Toast["tone"], { icon: "check" | "alert" | "dot"; className: string }> = {
  info: { icon: "dot", className: "border-line-strong text-ink" },
  success: { icon: "check", className: "border-success/40 text-success" },
  danger: { icon: "alert", className: "border-danger/40 text-danger" },
}

export function Toasts({ toasts, onDismiss }: { toasts: Toast[]; onDismiss: (id: number) => void }) {
  if (!toasts.length) return null
  return (
    <div
      aria-live="polite"
      aria-atomic="false"
      className="pointer-events-none fixed top-[calc(var(--topbar-h)+10px)] right-3 z-[var(--z-toast)] flex w-[min(360px,calc(100vw-24px))] flex-col gap-2"
    >
      {toasts.map((toast) => {
        const tone = TONE[toast.tone]
        return (
          <div
            key={toast.id}
            className={cx(
              "pointer-events-auto flex items-start gap-2 rounded-[var(--r-md)] border bg-surface-2/97 px-3 py-2.5 shadow-elev-md backdrop-blur-md data-[state=open]:animate-[pop-in_140ms_ease-out]",
              tone.className,
            )}
          >
            <Icon name={tone.icon} size={13} className="mt-0.5 shrink-0" />
            <p className="min-w-0 flex-1 text-[11.5px] leading-relaxed text-ink">{toast.message}</p>
            <button
              type="button"
              aria-label="Dismiss notification"
              onClick={() => onDismiss(toast.id)}
              className="shrink-0 rounded-[var(--r-xs)] text-ink-dim transition-colors hover:text-ink tab-stop"
            >
              <Icon name="x" size={11} />
            </button>
          </div>
        )
      })}
    </div>
  )
}
