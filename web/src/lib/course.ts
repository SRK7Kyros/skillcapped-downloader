import type { CatalogItem } from "../api/types"

/**
 * The lessons a course is made of, in the order the catalogue publishes them.
 * `lessonIds` is authoritative; the title match is the fallback for a dump that
 * has the lessons but no id list.
 */
export function courseLessons(items: CatalogItem[], course: CatalogItem): CatalogItem[] {
  if (course.lessonIds?.length) {
    const byId = new Map(items.map((item) => [item.id, item]))
    return course.lessonIds
      .map((id) => byId.get(id))
      .filter((item): item is CatalogItem => Boolean(item))
  }
  return items
    .filter((item) => item.kind === "video" && item.courseTitle === course.title)
    .sort((a, b) => a.date - b.date)
}

/** How much of a course is already on disk, by lesson count. */
export function courseDiskState(
  lessons: CatalogItem[],
  downloaded: Map<string, string>,
): { have: number; total: number; complete: boolean } {
  const have = lessons.filter((lesson) => downloaded.has(lesson.id)).length
  return { have, total: lessons.length, complete: lessons.length > 0 && have === lessons.length }
}

/** The lessons still to fetch, in course order. */
export function missingLessons(lessons: CatalogItem[], downloaded: Map<string, string>): CatalogItem[] {
  return lessons.filter((lesson) => !downloaded.has(lesson.id))
}
