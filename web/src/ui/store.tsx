import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react"
import type { ReactNode } from "react"

export type Prefs = {
  quality: number
  remux: boolean
  skipExisting: boolean
}

export type ToastTone = "info" | "success" | "danger"
export type Toast = { id: number; message: string; tone: ToastTone }

type AppContextValue = {
  prefs: Prefs
  setPrefs: (patch: Partial<Prefs>) => void
  selection: Set<string>
  isSelected: (id: string) => boolean
  toggle: (id: string, mode?: "add" | "remove") => void
  selectMany: (ids: string[], mode?: "add" | "remove") => void
  clearSelection: () => void
  toasts: Toast[]
  notify: (message: string, tone?: ToastTone) => void
  dismiss: (id: number) => void
  downloadsOpen: boolean
  setDownloadsOpen: (open: boolean) => void
}

const AppContext = createContext<AppContextValue | null>(null)

const PREFS_KEY = "skillcapped.prefs"

function readPrefs(fallback: Prefs): Prefs {
  try {
    const raw = localStorage.getItem(PREFS_KEY)
    if (!raw) return fallback
    const parsed = JSON.parse(raw) as Partial<Prefs>
    return {
      quality: typeof parsed.quality === "number" ? parsed.quality : fallback.quality,
      remux: typeof parsed.remux === "boolean" ? parsed.remux : fallback.remux,
      skipExisting: typeof parsed.skipExisting === "boolean" ? parsed.skipExisting : fallback.skipExisting,
    }
  } catch {
    return fallback
  }
}

export function AppProvider({ defaults, children }: { defaults: Prefs; children: ReactNode }) {
  const [prefs, setPrefsState] = useState<Prefs>(() => readPrefs(defaults))
  const [selection, setSelection] = useState<Set<string>>(() => new Set())
  const [toasts, setToasts] = useState<Toast[]>([])
  const [downloadsOpen, setDownloadsOpen] = useState(false)
  const toastId = useRef(0)

  const setPrefs = useCallback((patch: Partial<Prefs>) => {
    setPrefsState((current) => {
      const next = { ...current, ...patch }
      try {
        localStorage.setItem(PREFS_KEY, JSON.stringify(next))
      } catch {
        // Persisting preferences is a nicety, never a requirement.
      }
      return next
    })
  }, [])

  const dismiss = useCallback((id: number) => {
    setToasts((current) => current.filter((toast) => toast.id !== id))
  }, [])

  const notify = useCallback(
    (message: string, tone: ToastTone = "info") => {
      toastId.current += 1
      const id = toastId.current
      setToasts((current) => [...current.slice(-3), { id, message, tone }])
      window.setTimeout(() => dismiss(id), tone === "danger" ? 9000 : 4500)
    },
    [dismiss],
  )

  const toggle = useCallback((id: string, mode: "add" | "remove" = "add") => {
    setSelection((current) => {
      const next = new Set(current)
      if (mode === "remove" || (mode === "add" && next.has(id))) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  const selectMany = useCallback((ids: string[], mode: "add" | "remove" = "add") => {
    setSelection((current) => {
      const next = new Set(current)
      for (const id of ids) {
        if (mode === "remove") next.delete(id)
        else next.add(id)
      }
      return next
    })
  }, [])

  const clearSelection = useCallback(() => setSelection(new Set()), [])

  const value = useMemo<AppContextValue>(
    () => ({
      prefs,
      setPrefs,
      selection,
      isSelected: (id: string) => selection.has(id),
      toggle,
      selectMany,
      clearSelection,
      toasts,
      notify,
      dismiss,
      downloadsOpen,
      setDownloadsOpen,
    }),
    [prefs, setPrefs, selection, toggle, selectMany, clearSelection, toasts, notify, dismiss, downloadsOpen],
  )

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

function useAppContext(): AppContextValue {
  const value = useContext(AppContext)
  if (!value) throw new Error("AppProvider is missing")
  return value
}

export const usePrefs = () => useAppContext().prefs
export const useSetPrefs = () => useAppContext().setPrefs
export const useSelection = () => useAppContext()
export const useToasts = () => useAppContext()
export const useDownloadsOpen = () => useAppContext()

/** Escape closes the topmost transient surface. */
export function useEscape(handler: () => void, active = true): void {
  useEffect(() => {
    if (!active) return
    const listener = (event: KeyboardEvent) => {
      if (event.key === "Escape") handler()
    }
    window.addEventListener("keydown", listener)
    return () => window.removeEventListener("keydown", listener)
  }, [handler, active])
}

export function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState(() => (typeof window === "undefined" ? false : window.matchMedia(query).matches))
  useEffect(() => {
    const list = window.matchMedia(query)
    const listener = () => setMatches(list.matches)
    list.addEventListener("change", listener)
    return () => list.removeEventListener("change", listener)
  }, [query])
  return matches
}

export function useDebounced<T>(value: T, delayMs = 180): T {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const timer = window.setTimeout(() => setDebounced(value), delayMs)
    return () => window.clearTimeout(timer)
  }, [value, delayMs])
  return debounced
}
