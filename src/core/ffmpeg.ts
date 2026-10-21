/**
 * ffmpeg/ffprobe wrappers. The merged transport stream is already a valid
 * video; remuxing only swaps the container, so it is a nicety rather than a
 * requirement and every failure here degrades instead of losing the download.
 */

import type { Tool } from "../paths.ts"

export class RemuxError extends Error {
  constructor(message: string) {
    super(message)
    this.name = "RemuxError"
  }
}

/**
 * Rewrap a concatenated MPEG-TS into a fast-start MP4 without re-encoding.
 * The AAC bitstream filter is required: ADTS-framed audio must be converted to
 * raw AAC for the MP4 container to be valid.
 */
export async function remuxToMp4(tool: Tool, input: string, output: string, signal?: AbortSignal): Promise<void> {
  const process_ = Bun.spawn({
    cmd: [
      tool.path,
      "-hide_banner",
      "-loglevel", "error",
      "-y",
      "-i", input,
      "-c", "copy",
      "-bsf:a", "aac_adtstoasc",
      "-movflags", "+faststart",
      // The output is written under a `.part` name while it is being built, so
      // the muxer cannot be inferred from the extension and must be named.
      "-f", "mp4",
      output,
    ],
    stdout: "ignore",
    stderr: "pipe",
    signal,
  })

  const stderr = await new Response(process_.stderr).text()
  const code = await process_.exited
  if (code !== 0) throw new RemuxError(`ffmpeg exited with code ${code}${stderr ? `: ${stderr.trim().slice(0, 400)}` : ""}`)
}

/** Duration in seconds, or null when the file cannot be probed. */
export async function probeDuration(tool: Tool, file: string): Promise<number | null> {
  try {
    const process_ = Bun.spawn({
      cmd: [
        tool.path,
        "-hide_banner",
        "-loglevel", "error",
        "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1",
        file,
      ],
      stdout: "pipe",
      stderr: "ignore",
    })
    const text = await new Response(process_.stdout).text()
    const code = await process_.exited
    if (code !== 0) return null
    const value = Number.parseFloat(text.trim())
    return Number.isFinite(value) ? value : null
  } catch {
    return null
  }
}
