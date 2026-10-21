/**
 * State that must survive a restart. A bulk run can take a long while, so a
 * half-finished queue is persisted and picked back up; anything that was
 * mid-flight when the process died is reported as interrupted rather than
 * silently vanishing.
 */

import { mkdir, readFile, rm, writeFile } from "node:fs/promises"
import { stateDir, tmpDir } from "../paths.ts"
import type { JobRecord } from "./queue.ts"

const VERSION = 1

type StoreFile = { version: number; jobs: JobRecord[] }

export async function loadJobs(root: string): Promise<JobRecord[]> {
  try {
    const raw = await readFile(jobsPath(root), "utf8")
    const parsed = JSON.parse(raw) as StoreFile
    if (parsed.version !== VERSION || !Array.isArray(parsed.jobs)) return []
    return parsed.jobs
  } catch {
    return []
  }
}

export async function saveJobs(root: string, jobs: JobRecord[]): Promise<void> {
  await mkdir(stateDir(root), { recursive: true })
  const payload: StoreFile = { version: VERSION, jobs }
  await writeFile(jobsPath(root), JSON.stringify(payload), "utf8")
}

/** Debounced writer — progress changes arrive far faster than the disk needs. */
export function createDebouncedSaver(root: string, delayMs = 700) {
  let timer: ReturnType<typeof setTimeout> | null = null
  let pending: JobRecord[] = []

  return {
    schedule(jobs: JobRecord[]) {
      pending = jobs
      if (timer) return
      timer = setTimeout(() => {
        timer = null
        void saveJobs(root, pending)
      }, delayMs)
    },
    async flush() {
      if (timer) {
        clearTimeout(timer)
        timer = null
      }
      if (pending.length) await saveJobs(root, pending)
    },
  }
}

/** Delete scratch left behind by a previous run. */
export async function sweepScratch(root: string): Promise<void> {
  await rm(tmpDir(root), { recursive: true, force: true })
  await mkdir(tmpDir(root), { recursive: true })
}

function jobsPath(root: string): string {
  return `${stateDir(root)}/jobs.json`
}
