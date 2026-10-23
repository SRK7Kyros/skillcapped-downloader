import type { ItemKind } from "../api/types"

/**
 * The one shape every card of a kind is drawn at. A course's art is a 576×912
 * portrait card with the title baked into the top, everything else ships
 * 1280×720 stills.
 *
 * The box is always this shape whatever picture arrived (see `object-top` on the
 * card), so a row stays uniform, a poster that is a little taller loses its
 * bottom instead of its neighbours standing taller, and nothing reflows when the
 * art finishes loading.
 */
const POSTER_WINDOW: Record<ItemKind, string> = {
  course: "576 / 912",
  video: "16 / 9",
  commentary: "16 / 9",
}

export function posterRatio(kind: ItemKind): string {
  return POSTER_WINDOW[kind] ?? "16 / 9"
}
