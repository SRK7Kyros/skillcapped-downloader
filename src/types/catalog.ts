/**
 * Shapes of the upstream course dump, parsed tolerantly: the dump is a
 * third-party 2.38 MB document with no version field, so a renamed or missing
 * field must degrade one record instead of blanking the whole catalogue.
 */

import { z } from "zod"

const looseString = z.string().catch("")

export const dumpSchema = z.object({
  seasonLabel: looseString.optional().default(""),
  patch: z
    .object({ patchVal: looseString.optional().default("") })
    .catch({ patchVal: "" })
    .optional()
    .default({ patchVal: "" }),
  tagInfo: z
    .array(z.object({ name: looseString }).catch({ name: "" }))
    .catch([])
    .optional()
    .default([]),
  videos: z
    .array(
      z.object({
        uuid: looseString,
        title: looseString,
        desc: looseString.optional().default(""),
        role: looseString.optional().default("all"),
        tId: z.number().catch(0).optional().default(0),
        durSec: z.number().catch(0).optional().default(0),
        rDate: z.number().catch(0).optional().default(0),
        tSS: looseString.optional().default(""),
        encoding: looseString.optional().default(""),
      }),
    )
    .catch([])
    .optional()
    .default([]),
  commentaries: z
    .array(
      z.object({
        uuid: looseString,
        role: looseString.optional().default("all"),
        tId: z.number().catch(0).optional().default(0),
        durSec: z.number().catch(0).optional().default(0),
        rDate: z.number().catch(0).optional().default(0),
        tSS: looseString.optional().default(""),
        staff: looseString.optional().default(""),
        matchLink: looseString.optional().default(""),
        yourChampion: looseString.optional().default(""),
        theirChampion: looseString.optional().default(""),
        k: z.number().catch(0).optional().default(0),
        d: z.number().catch(0).optional().default(0),
        a: z.number().catch(0).optional().default(0),
        carry: looseString.optional().default(""),
      }),
    )
    .catch([])
    .optional()
    .default([]),
  courses: z
    .array(
      z.object({
        uuid: looseString,
        title: looseString,
        role: looseString.optional().default("all"),
        rDate: z.number().catch(0).optional().default(0),
        tags: z.array(looseString).catch([]).optional().default([]),
        courseImage: looseString.optional().default(""),
        courseImage2: looseString.optional().default(""),
        courseImage3: looseString.optional().default(""),
      }),
    )
    .catch([])
    .optional()
    .default([]),
  videosToCourses: z
    .record(
      z.string(),
      z.object({
        chapters: z
          .array(
            z.object({
              title: looseString.optional().default(""),
              vids: z.array(z.object({ uuid: looseString })).catch([]).optional().default([]),
            }),
          )
          .catch([])
          .optional()
          .default([]),
      }),
    )
    .catch({})
    .optional()
    .default({}),
})

export type Dump = z.infer<typeof dumpSchema>

export type ItemKind = "video" | "commentary" | "course"

/** One row in the browse grid — already normalised, ready for the client. */
export type CatalogItem = {
  id: string
  kind: ItemKind
  title: string
  role: string
  durationSec: number
  date: number
  /** Finest tag the source assigns (tagInfo name, or a course's last tag). */
  category: string
  tags: string[]
  thumb: string
  /** Course membership, present on videos that belong to one. */
  courseTitle?: string
  /** Courses only: the ordered lesson ids, flattened across chapters. */
  lessonIds?: string[]
  videoCount?: number
  /** Commentaries only. */
  staff?: string
  champions?: string
  kda?: string
}

export type Catalog = {
  season: string
  patch: string
  generatedAt: number
  dumpUrl: string
  roles: string[]
  categories: string[]
  items: CatalogItem[]
}
