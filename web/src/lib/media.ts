import type { ItemKind } from "../api/types"

/**
 * The one shape every card of a kind is drawn at. A course's art is a 576×912
 * portrait card with the title baked into the top, everything else ships
 * 1280×720 stills.
 *
 * The course window is that card **with its dead foot cut off** (806, not 912):
 * the site prints a pure-black strip along the bottom of its course cards —
 * measured 9.9–10.9% of the height, the band SkillCapped's own site prints the
 * title onto — and we draw our title *under* the art, so showing the strip in
 * full leaves a band of black between the picture and the words that reads as
 * empty space. Cropping to 806 keeps the baked-in title at the top and ends the
 * art where it looks like it ends.
 *
 * The box is always this shape whatever picture arrived (see `object-top` on the
 * card), so a row stays uniform, a poster that is a little taller loses its
 * bottom instead of its neighbours standing taller, and nothing reflows when the
 * art finishes loading.
 */
const POSTER_WINDOW: Record<ItemKind, string> = {
  course: "576 / 806",
  video: "16 / 9",
  commentary: "16 / 9",
}

export function posterRatio(kind: ItemKind): string {
  return POSTER_WINDOW[kind] ?? "16 / 9"
}
