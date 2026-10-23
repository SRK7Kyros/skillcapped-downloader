import { Dialog as RadixDialog, Popover as RadixPopover, Switch as RadixSwitch, Tooltip as RadixTooltip } from "radix-ui"
import type { ButtonHTMLAttributes, ReactNode } from "react"
import { Icon, type IconName } from "./icons"

export const cx = (...values: Array<string | false | null | undefined>): string =>
  values.filter(Boolean).join(" ")

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "danger"
  size?: "sm" | "md"
  icon?: IconName
  loading?: boolean
}

export function Button({
  variant = "secondary",
  size = "md",
  icon,
  loading,
  children,
  className,
  disabled,
  ...rest
}: ButtonProps) {
  const base =
    "inline-flex items-center justify-center gap-2 rounded-[var(--r-sm)] border font-medium whitespace-nowrap transition-colors duration-[var(--dur-fast)] disabled:opacity-45 disabled:pointer-events-none"
  const sizes = {
    sm: "h-7 px-2.5 text-[11px]",
    md: "h-9 px-3.5 text-[12px]",
  }[size]
  const variants = {
    primary:
      "bg-brand text-brand-ink border-transparent hover:bg-brand-hover active:bg-brand-press shadow-elev-sm",
    secondary: "bg-surface-2 text-ink border-line hover:bg-surface-3 hover:border-line-strong",
    ghost: "bg-transparent text-ink-muted border-transparent hover:bg-surface-2 hover:text-ink",
    danger: "bg-danger-dim text-danger border-transparent hover:bg-danger hover:text-ink-inverse",
  }[variant]

  return (
    <button type="button" className={cx(base, sizes, variants, "tab-stop", className)} disabled={disabled || loading} {...rest}>
      {loading ? <Spinner size={13} /> : icon ? <Icon name={icon} size={size === "sm" ? 13 : 14} /> : null}
      {children}
    </button>
  )
}

export function IconButton({
  icon,
  label,
  active,
  className,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { icon: IconName; label: string; active?: boolean }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      className={cx(
        "inline-flex h-8 w-8 shrink-0 items-center justify-center rounded-[var(--r-sm)] border transition-colors duration-[var(--dur-fast)]",
        active
          ? "border-brand-line bg-brand-dim text-brand"
          : "border-transparent text-ink-muted hover:bg-surface-2 hover:text-ink",
        "tab-stop",
        className,
      )}
      {...rest}
    >
      <Icon name={icon} size={15} />
    </button>
  )
}

export function Chip({
  active,
  children,
  className,
  ...rest
}: ButtonHTMLAttributes<HTMLButtonElement> & { active?: boolean }) {
  return (
    <button
      type="button"
      aria-pressed={active}
      className={cx(
        "inline-flex h-7 items-center gap-1.5 rounded-full border px-3 text-[11px] font-medium transition-colors duration-[var(--dur-fast)] tab-stop",
        active
          ? "border-brand-line bg-brand-dim text-brand"
          : "border-line bg-surface-1 text-ink-muted hover:border-line-strong hover:text-ink",
        className,
      )}
      {...rest}
    >
      {children}
    </button>
  )
}

export function Segmented<T extends string>({
  value,
  options,
  onChange,
  ariaLabel,
}: {
  value: T
  options: Array<{ value: T; label: string; icon?: IconName }>
  onChange: (value: T) => void
  ariaLabel: string
}) {
  return (
    <div
      role="tablist"
      aria-label={ariaLabel}
      className="inline-flex shrink-0 items-center gap-0.5 rounded-[var(--r-sm)] border border-line bg-surface-1 p-0.5"
    >
      {options.map((option) => {
        const active = option.value === value
        return (
          <button
            key={option.value}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange(option.value)}
            className={cx(
              "inline-flex h-7 items-center gap-1.5 whitespace-nowrap rounded-[var(--r-xs)] px-2.5 text-[11px] font-medium transition-colors duration-[var(--dur-fast)] tab-stop",
              active ? "bg-surface-3 text-ink shadow-elev-xs" : "text-ink-muted hover:text-ink",
            )}
          >
            {option.icon ? <Icon name={option.icon} size={13} /> : null}
            {option.label}
          </button>
        )
      })}
    </div>
  )
}

export function Spinner({ size = 14, className }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" className={cx("animate-[spin_0.8s_linear_infinite]", className)} aria-hidden="true">
      <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeOpacity="0.22" strokeWidth="2.6" />
      <path d="M21 12a9 9 0 0 0-9-9" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" />
    </svg>
  )
}

export function ProgressBar({
  value,
  tone = "brand",
  height = 4,
  className,
}: {
  value: number
  tone?: "brand" | "danger" | "success" | "warning" | "muted"
  height?: number
  className?: string
}) {
  const clamped = Math.max(0, Math.min(100, Number.isFinite(value) ? value : 0))
  const tones = {
    brand: "bg-brand",
    danger: "bg-danger",
    success: "bg-success",
    warning: "bg-warning",
    muted: "bg-ink-faint",
  }
  return (
    <div
      className={cx("w-full overflow-hidden rounded-full bg-surface-4", className)}
      style={{ height }}
      role="progressbar"
      aria-valuenow={Math.round(clamped)}
      aria-valuemin={0}
      aria-valuemax={100}
    >
      <div
        className={cx("h-full rounded-full transition-[width] duration-[var(--dur-med)] ease-out", tones[tone])}
        style={{ width: `${clamped}%` }}
      />
    </div>
  )
}

export function Badge({
  children,
  color,
  className,
  subtle,
}: {
  children: ReactNode
  color?: string
  className?: string
  subtle?: boolean
}) {
  const style = color
    ? subtle
      ? { color, backgroundColor: `color-mix(in srgb, ${color} 14%, transparent)`, borderColor: `color-mix(in srgb, ${color} 34%, transparent)` }
      : { color: "var(--text-inverse)", backgroundColor: color, borderColor: "transparent" }
    : undefined
  return (
    <span
      className={cx(
        "inline-flex h-5 items-center rounded-[var(--r-xs)] border px-1.5 font-mono text-[10px] font-semibold tracking-[0.06em] uppercase",
        !color && "border-line bg-surface-3 text-ink-muted",
        className,
      )}
      style={style}
    >
      {children}
    </span>
  )
}

export function EmptyState({
  icon = "search",
  title,
  body,
  action,
}: {
  icon?: IconName
  title: string
  body?: string
  action?: ReactNode
}) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 rounded-[var(--r-md)] border border-dashed border-line bg-surface-1/60 px-6 py-16 text-center">
      <span className="flex h-11 w-11 items-center justify-center rounded-full border border-line bg-surface-2 text-ink-dim">
        <Icon name={icon} size={19} />
      </span>
      <div className="space-y-1">
        <p className="text-[13px] font-semibold text-ink">{title}</p>
        {body ? <p className="max-w-sm text-[11.5px] leading-relaxed text-ink-muted">{body}</p> : null}
      </div>
      {action}
    </div>
  )
}

/** Side sheet used for the download queue. */
export function Drawer({
  open,
  onOpenChange,
  title,
  description,
  children,
  footer,
  width = "min(460px, 100vw)",
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description?: string
  children: ReactNode
  footer?: ReactNode
  width?: string
}) {
  return (
    <RadixDialog.Root open={open} onOpenChange={onOpenChange}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="fixed inset-0 z-[var(--z-drawer)] bg-black/55 backdrop-blur-[1px] data-[state=open]:animate-[pop-in_140ms_ease-out]" />
        <RadixDialog.Content
          style={{ maxWidth: width }}
          className="fixed top-0 right-0 z-[var(--z-drawer)] flex h-full w-full flex-col border-l border-line-strong bg-surface-1 shadow-elev-lg outline-none"
        >
          <header className="flex items-start justify-between gap-4 border-b border-line px-4 py-3">
            <div className="min-w-0">
              <RadixDialog.Title className="text-[13px] font-semibold text-ink">{title}</RadixDialog.Title>
              {description ? (
                <RadixDialog.Description className="mt-0.5 text-[11px] text-ink-muted">
                  {description}
                </RadixDialog.Description>
              ) : null}
            </div>
            <RadixDialog.Close asChild>
              <IconButton icon="x" label="Close" className="tab-stop" />
            </RadixDialog.Close>
          </header>
          <div className="min-h-0 flex-1 overflow-y-auto px-4 py-3">{children}</div>
          {footer ? <footer className="border-t border-line px-4 py-3">{footer}</footer> : null}
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  )
}

/** Centered modal, used for the preview player. */
export function Modal({
  open,
  onOpenChange,
  title,
  children,
  maxWidth = "min(1040px, 94vw)",
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  children: ReactNode
  maxWidth?: string
}) {
  return (
    <RadixDialog.Root open={open} onOpenChange={onOpenChange}>
      <RadixDialog.Portal>
        <RadixDialog.Overlay className="fixed inset-0 z-[var(--z-modal)] bg-black/70 backdrop-blur-[2px] data-[state=open]:animate-[pop-in_140ms_ease-out]" />
        <RadixDialog.Content
          style={{ maxWidth }}
          className="fixed top-1/2 left-1/2 z-[var(--z-modal)] w-full max-h-[92vh] -translate-x-1/2 -translate-y-1/2 overflow-hidden rounded-[var(--r-lg)] border border-line-strong bg-surface-1 shadow-elev-lg outline-none"
        >
          <header className="flex items-center justify-between gap-4 border-b border-line px-4 py-2.5">
            <RadixDialog.Title className="truncate text-[12.5px] font-semibold text-ink">{title}</RadixDialog.Title>
            <RadixDialog.Close asChild>
              <IconButton icon="x" label="Close preview" className="tab-stop" />
            </RadixDialog.Close>
          </header>
          <div className="max-h-[calc(92vh-44px)] overflow-y-auto">{children}</div>
        </RadixDialog.Content>
      </RadixDialog.Portal>
    </RadixDialog.Root>
  )
}

export function Popover({
  open,
  onOpenChange,
  trigger,
  children,
  align = "start",
  contentClassName,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  trigger: ReactNode
  children: ReactNode
  align?: "start" | "center" | "end"
  contentClassName?: string
}) {
  return (
    <RadixPopover.Root open={open} onOpenChange={onOpenChange}>
      <RadixPopover.Trigger asChild>{trigger}</RadixPopover.Trigger>
      <RadixPopover.Portal>
        <RadixPopover.Content
          align={align}
          sideOffset={6}
          collisionPadding={12}
          className={cx(
            "z-[var(--z-popover)] rounded-[var(--r-md)] border border-line-strong bg-surface-3 shadow-elev-md outline-none",
            contentClassName,
          )}
        >
          {children}
        </RadixPopover.Content>
      </RadixPopover.Portal>
    </RadixPopover.Root>
  )
}

export function Tooltip({ label, children }: { label: string; children: ReactNode }) {
  return (
    <RadixTooltip.Provider delayDuration={350}>
      <RadixTooltip.Root>
        <RadixTooltip.Trigger asChild>{children}</RadixTooltip.Trigger>
        <RadixTooltip.Portal>
          <RadixTooltip.Content
            sideOffset={6}
            className="z-[var(--z-popover)] rounded-[var(--r-xs)] border border-line-strong bg-surface-4 px-2 py-1 text-[10.5px] text-ink shadow-elev-sm"
          >
            {label}
          </RadixTooltip.Content>
        </RadixTooltip.Portal>
      </RadixTooltip.Root>
    </RadixTooltip.Provider>
  )
}

export function Switch({
  checked,
  onCheckedChange,
  label,
  id,
  disabled,
}: {
  checked: boolean
  onCheckedChange: (checked: boolean) => void
  label: string
  id?: string
  disabled?: boolean
}) {
  return (
    <label className="flex items-center gap-2 select-none" htmlFor={id}>
      <RadixSwitch.Root
        id={id}
        checked={checked}
        onCheckedChange={onCheckedChange}
        disabled={disabled}
        className={cx(
          "relative h-[18px] w-[32px] shrink-0 cursor-pointer rounded-full border transition-colors duration-[var(--dur-fast)] tab-stop",
          checked ? "border-brand-line bg-brand-dim" : "border-line bg-surface-3",
          "disabled:opacity-45",
        )}
      >
        <RadixSwitch.Thumb
          className={cx(
            "block h-[12px] w-[12px] translate-x-[2px] rounded-full transition-transform duration-[var(--dur-fast)] ease-out",
            checked ? "translate-x-[16px] bg-brand" : "bg-ink-dim",
          )}
        />
      </RadixSwitch.Root>
      <span className="text-[11px] font-medium text-ink-muted">{label}</span>
    </label>
  )
}
