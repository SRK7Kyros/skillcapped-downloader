import { useEffect, useState, type RefObject } from "react"

export interface GridMetrics {
  /** The column count the grid is actually painting. CSS owns the breakpoints. */
  columns: number
  /** Width of one column track, in pixels. */
  track: number
  /** Column gap, in pixels. */
  gap: number
}

const EMPTY: GridMetrics = { columns: 1, track: 0, gap: 0 }

/** The geometry the grid is painting right now. */
export function useGridMetrics(ref: RefObject<HTMLElement | null>): GridMetrics {
  const [metrics, setMetrics] = useState<GridMetrics>(EMPTY)

  useEffect(() => {
    const node = ref.current
    if (!node) return

    // An empty clone cannot introduce implicit tracks the way an open panel does,
    // so its template is the geometry the CSS breakpoints actually ask for.
    const measure = (): GridMetrics => {
      const probe = node.cloneNode(false) as HTMLElement
      probe.style.position = "absolute"
      probe.style.visibility = "hidden"
      probe.style.pointerEvents = "none"
      probe.style.width = `${node.clientWidth}px`
      probe.setAttribute("aria-hidden", "true")
      node.parentElement?.appendChild(probe)
      const painted = getComputedStyle(probe)
      const tracks = painted.gridTemplateColumns.split(" ").filter(Boolean).map(Number.parseFloat)
      const gap = Number.parseFloat(painted.columnGap) || 0
      probe.remove()
      return tracks.length ? { columns: tracks.length, track: tracks[0] ?? 0, gap } : EMPTY
    }

    const read = () => setMetrics(measure())
    read()
    const observer = new ResizeObserver(read)
    observer.observe(node)
    return () => observer.disconnect()
  }, [ref])

  return metrics
}

/** The column count the grid is actually painting. */
export function useGridColumns(ref: RefObject<HTMLElement | null>): number {
  return useGridMetrics(ref).columns
}
