import { useEffect, useState, type RefObject } from "react"

/** The column count the grid is actually painting. CSS owns the breakpoints. */
export function useGridColumns(ref: RefObject<HTMLElement | null>): number {
  const [columns, setColumns] = useState(1)

  useEffect(() => {
    const node = ref.current
    if (!node) return
    const read = () => {
      const tracks = getComputedStyle(node).gridTemplateColumns.split(" ").filter(Boolean)
      setColumns(tracks.length || 1)
    }
    read()
    const observer = new ResizeObserver(read)
    observer.observe(node)
    return () => observer.disconnect()
  }, [ref])

  return columns
}
