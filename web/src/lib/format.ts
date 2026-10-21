const ROLE_LABELS: Record<string, string> = {
  all: "All roles",
  top: "Top",
  jungle: "Jungle",
  mid: "Mid",
  adc: "ADC",
  support: "Support",
}

const ROLE_SHORT: Record<string, string> = {
  all: "ALL",
  top: "TOP",
  jungle: "JNG",
  mid: "MID",
  adc: "ADC",
  support: "SUP",
}

export function roleLabel(role: string): string {
  return ROLE_LABELS[role] ?? role
}

export function roleShort(role: string): string {
  return ROLE_SHORT[role] ?? role.slice(0, 3).toUpperCase()
}

export function roleVar(role: string): string {
  return `var(--role-${ROLE_LABELS[role] ? role : "all"})`
}

export function formatBytes(bytes: number): string {
  if (!bytes || bytes < 0) return "0 B"
  const units = ["B", "KB", "MB", "GB", "TB"]
  let value = bytes
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  const digits = value >= 100 || unit === 0 ? 0 : 1
  return `${value.toFixed(digits)} ${units[unit]}`
}

export function formatDuration(seconds: number): string {
  if (!seconds || seconds < 0) return "—"
  const total = Math.round(seconds)
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  const secs = total % 60
  if (hours > 0) return `${hours}:${String(minutes).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
  return `${minutes}:${String(secs).padStart(2, "0")}`
}

export function formatDate(ms: number): string {
  if (!ms) return "—"
  return new Date(ms).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })
}

export function formatRelative(ms: number): string {
  if (!ms) return "—"
  const delta = Date.now() - ms
  const minutes = Math.round(delta / 60_000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.round(hours / 24)
  if (days < 30) return `${days}d ago`
  return formatDate(ms)
}

export function formatSpeed(bytesPerSecond: number): string {
  if (!bytesPerSecond || bytesPerSecond <= 0) return "—"
  return `${formatBytes(bytesPerSecond)}/s`
}

export function formatEta(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) return "—"
  if (seconds < 60) return `${Math.ceil(seconds)}s`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  return `${hours}h ${minutes % 60}m`
}

export function formatCount(value: number): string {
  return value.toLocaleString()
}
