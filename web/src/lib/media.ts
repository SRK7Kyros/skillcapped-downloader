import type { ItemKind } from "../api/types"

/**
 * Shape of the media box before its poster has loaded. A course's art is a
 * 576×912 portrait card with the title baked into the top, so a 16:9 box
 * cropped away the title and two thirds of the art; everything else ships
 * 1280×720 stills.
 */
const DEFAULT_RATIO: Record<ItemKind, string> = {
  course: "2 / 3",
  video: "16 / 9",
  commentary: "16 / 9",
}

export function posterRatio(kind: ItemKind): string {
  return DEFAULT_RATIO[kind] ?? "16 / 9"
}

/** The poster's own shape, so the card can show all of it instead of cropping to a house ratio. */
export function imageRatio(width: number, height: number): string | null {
  if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return null
  return `${Math.round(width)} / ${Math.round(height)}`
}
