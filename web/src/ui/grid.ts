import { useEffect, useState, type RefObject } from "react"

/** The column count the grid is actually painting. CSS owns the breakpoints. */
export function useGridColumns(ref: RefObject<HTMLElement | null>): number {
  const [columns, setColumns] = useState(1)

  useEffect(() => {
    const node = ref.current
    if (!node) return

    // An empty clone cannot introduce implicit tracks the way an open panel does,
    // so its template is the count the CSS breakpoints actually ask for.
    const trackCount = () => {
      const probe = node.cloneNode(false) as HTMLElement
      probe.style.position = "absolute"
      probe.style.visibility = "hidden"
      probe.style.pointerEvents = "none"
      probe.style.width = `${node.clientWidth}px`
      probe.setAttribute("aria-hidden", "true")
      node.parentElement?.appendChild(probe)
      const tracks = getComputedStyle(probe).gridTemplateColumns.split(" ").filter(Boolean).length
      probe.remove()
      return tracks || 1
    }

    const read = () => setColumns(trackCount())
    read()
    const observer = new ResizeObserver(read)
    observer.observe(node)
    return () => observer.disconnect()
  }, [ref])

  return columns
}
