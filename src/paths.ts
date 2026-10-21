/**
 * Every path decision in the app goes through this module — where the
 * executable lives, where `content/` is, which ffmpeg to use, where scratch
 * files go. Keeping it in one place is what makes the compiled binary behave
 * the same as the source run.
 */

import path from "node:path"
import type { Flags } from "./flags.ts"

/**
 * True when running as a compiled executable. Bun mounts an embedded VFS at
 * `/$bunfs`, so `import.meta.dir` points inside it instead of a real folder.
 */
export function isStandalone(): boolean {
  return (import.meta.dir ?? "").startsWith("/$bunfs")
}

/** The folder the app "lives" in: beside the exe when compiled, repo root in dev. */
export function appDir(): string {
  return isStandalone() ? path.dirname(process.execPath) : path.resolve(import.meta.dir, "..")
}

/** Root of all downloads. Always a real directory next to the executable. */
export function contentDir(flags: Pick<Flags, "contentDir">): string {
  return flags.contentDir ? path.resolve(flags.contentDir) : path.join(appDir(), "content")
}

/** Hidden scratch/metadata folder inside the content root. */
export function stateDir(root: string): string {
  return path.join(root, ".skillcapped")
}

/** Per-run scratch space. Never holds anything the user should see. */
export function tmpDir(root: string): string {
  return path.join(stateDir(root), "tmp")
}

export type Tool = { path: string; source: "env" | "bundled" | "PATH"; version: string }

function probeTool(candidate: string): string | null {
  try {
    const result = Bun.spawnSync({ cmd: [candidate, "-version"], stdout: "pipe", stderr: "ignore" })
    if (result.exitCode !== 0) return null
    const first = new TextDecoder().decode(result.stdout).split("\n")[0]?.trim() ?? ""
    return first || "unknown"
  } catch {
    return null
  }
}

/**
 * Locate a media tool in the documented order: explicit env override, then a
 * copy bundled next to the executable, then whatever the OS PATH offers.
 * Returns `null` when nothing usable is found — the caller degrades instead of
 * crashing (the merged transport stream is a perfectly valid artifact).
 */
export function resolveTool(name: "ffmpeg" | "ffprobe", env: Record<string, string | undefined> = process.env): Tool | null {
  const exe = process.platform === "win32" ? `${name}.exe` : name
  const envKey = name === "ffmpeg" ? "SKILLCAPPED_FFMPEG" : "SKILLCAPPED_FFPROBE"

  const candidates: Array<{ path: string; source: Tool["source"] }> = []
  const fromEnv = env[envKey]
  if (fromEnv) candidates.push({ path: fromEnv, source: "env" })
  candidates.push({ path: path.join(appDir(), "bin", exe), source: "bundled" })
  candidates.push({ path: exe, source: "PATH" })

  for (const candidate of candidates) {
    const version = probeTool(candidate.path)
    if (version) return { path: candidate.path, source: candidate.source, version }
  }
  return null
}
