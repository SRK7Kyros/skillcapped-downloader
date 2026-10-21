/**
 * Open the user's default browser at the local server address. Best effort —
 * a headless or locked-down machine simply gets the URL printed instead.
 */

import { spawn } from "node:child_process"

export function openBrowser(url: string): boolean {
  const command =
    process.platform === "win32"
      ? { cmd: "cmd", args: ["/c", "start", "", url] }
      : process.platform === "darwin"
        ? { cmd: "open", args: [url] }
        : { cmd: "xdg-open", args: [url] }

  try {
    const child = spawn(command.cmd, command.args, { detached: true, stdio: "ignore" })
    child.on("error", () => {})
    child.unref()
    return true
  } catch {
    return false
  }
}

/** Reveal a folder in the OS file manager. Used by the "Open folder" action. */
export function openFolder(folder: string): boolean {
  const command =
    process.platform === "win32"
      ? { cmd: "explorer", args: [folder] }
      : process.platform === "darwin"
        ? { cmd: "open", args: [folder] }
        : { cmd: "xdg-open", args: [folder] }

  try {
    const child = spawn(command.cmd, command.args, { detached: true, stdio: "ignore" })
    child.on("error", () => {})
    child.unref()
    return true
  } catch {
    return false
  }
}
