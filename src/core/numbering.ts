/**
 * The number a lesson carries in its file name.
 *
 * A lesson is numbered by its position in the collection the library groups it
 * into, and the width of that number is the width of the collection's size:
 *
 *   course lesson         position in the course's own `lessonIds` / its length
 *   loose video           order within `Videos/<role>/<category>` / that count
 *   commentary            order within `Commentaries/<role>` / that count
 *
 * The catalogue is what defines that order, so the phone and the desktop — which
 * read the same `catalog.json` — must agree to the digit: the comparator below
 * is deliberately locale-free (newest first, then title, then id) and is
 * mirrored by `CatalogIndex.fileNumber` in the iOS app. A `localeCompare` here
 * would order two same-day lessons differently on a phone than on this host.
 */

import type { CatalogItem } from "../types/catalog.ts"
import { relativeFolder, type DownloadShape, type FileNumber } from "./naming.ts"

function shapeOf(item: CatalogItem): DownloadShape {
  return {
    kind: item.kind,
    title: item.title,
    role: item.role,
    category: item.category,
    courseTitle: item.courseTitle,
  }
}

/** Newest first, then title, then id — the same order on both surfaces. */
export function compareLessons(first: CatalogItem, second: CatalogItem): number {
  if (first.date !== second.date) return second.date - first.date
  const firstTitle = first.title.toLowerCase()
  const secondTitle = second.title.toLowerCase()
  if (firstTitle !== secondTitle) return firstTitle < secondTitle ? -1 : 1
  if (first.id === second.id) return 0
  return first.id < second.id ? -1 : 1
}

/**
 * Every lesson's number, keyed by catalogue id. A course's lessons are numbered
 * by the course, so the count a user sees on the card is the count in the name.
 *
 * Items are sorted by id first: a lesson two courses both list belongs to the
 * one the pass reaches first, and the phone only has a dictionary of the same
 * catalogue — sorting is what makes both surfaces agree on that tie.
 */
export function fileNumbers(items: readonly CatalogItem[]): Map<string, FileNumber> {
  const numbers = new Map<string, FileNumber>()
  const known = new Set(items.map((item) => item.id))
  const ordered = [...items].sort((first, second) => (first.id < second.id ? -1 : first.id > second.id ? 1 : 0))

  for (const course of ordered) {
    if (course.kind !== "course") continue
    const lessons = course.lessonIds ?? []
    lessons.forEach((id, offset) => {
      if (!known.has(id) || numbers.has(id)) return
      numbers.set(id, { index: offset + 1, total: lessons.length })
    })
  }

  // A course owns its folder, so an item merely pointing at one (a lesson the
  // course does not list) takes no number rather than a number that would
  // collide with the course's own.
  const courseFolders = new Set(
    items.filter((item) => item.kind === "course").map((course) => relativeFolder(shapeOf(course))),
  )

  const groups = new Map<string, CatalogItem[]>()
  for (const item of ordered) {
    if (item.kind === "course" || numbers.has(item.id)) continue
    const folder = relativeFolder(shapeOf(item))
    if (courseFolders.has(folder)) continue
    const group = groups.get(folder) ?? []
    group.push(item)
    groups.set(folder, group)
  }

  for (const group of groups.values()) {
    group.sort(compareLessons)
    group.forEach((item, offset) => numbers.set(item.id, { index: offset + 1, total: group.length }))
  }

  return numbers
}
