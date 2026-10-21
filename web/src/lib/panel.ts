/** Rows a lesson strip paints. */
export const STRIP_ROWS = 2
export const STRIP_GAP = 8
export const CARD_BORDER = 2
export const TITLE_BLOCK = 44
/** The strip's height when the panel takes the full row instead of one card's. */
export const STACKED_STRIP_HEIGHT = 296
/** The strip's own padding (p-2 on every side). */
export const PANEL_PADDING = 16
const POSTER_RATIO = 16 / 9
const MIN_POSTER_HEIGHT = 56
const FALLBACK_LESSON_WIDTH = 168

export interface PanelGeometry {
  stripHeight: number
  /** Width a lesson card needs so its 16:9 poster is never cropped. */
  lessonWidth: number
  /** Panel width the lessons need: its padding plus one column per two lessons. */
  contentWidth: number
}

/** The strip's card sizes at a given strip height — one source for the panel and the grid. */
export function panelGeometry(stripHeight: number, lessonCount: number): PanelGeometry {
  const measured = stripHeight > 0
  const rowHeight = measured ? (stripHeight - STRIP_GAP * (STRIP_ROWS - 1)) / STRIP_ROWS : 0
  const posterHeight = Math.max(MIN_POSTER_HEIGHT, rowHeight - TITLE_BLOCK)
  const lessonWidth = measured ? Math.ceil(posterHeight * POSTER_RATIO) + CARD_BORDER : FALLBACK_LESSON_WIDTH
  const lessonColumns = Math.max(1, Math.ceil(lessonCount / STRIP_ROWS))
  const stripWidth = lessonColumns * lessonWidth + (lessonColumns - 1) * STRIP_GAP

  return { stripHeight, lessonWidth, contentWidth: PANEL_PADDING + stripWidth }
}

/** The strip height a panel of that height leaves once it has padded itself. */
export function stripHeightFor(panelHeight: number, attached: boolean): number {
  return attached && panelHeight > 0 ? Math.max(0, panelHeight - PANEL_PADDING) : STACKED_STRIP_HEIGHT
}

/** Tracks a content width needs, kept within `min` and the room left in its row. */
export function panelTracks(
  contentWidth: number,
  track: number,
  gap: number,
  min: number,
  room: number,
): number {
  if (track <= 0) return Math.max(0, Math.min(room, min))
  const pitch = track + gap
  return Math.min(room, Math.max(min, Math.ceil((contentWidth + gap) / pitch)))
}
