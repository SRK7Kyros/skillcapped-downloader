/**
 * Copies the Vite build output over the embedded copy the server imports.
 * The output is a single self-contained HTML file: no sidecar JS, CSS, fonts.
 * `singleFile()` in `web/vite.config.ts` is what guarantees that, so this script
 * only checks the result is a plausible document — scanning for `src="../..` is
 * useless because the inlined JavaScript legitimately contains script-tag
 * strings of its own.
 */

import { mkdir } from "node:fs/promises"
import path from "node:path"

const root = path.resolve(import.meta.dir, "..")
const built = path.join(root, "web", "dist", "index.html")
const target = path.join(root, "src", "server", "web.html")

const source = Bun.file(built)
if (!(await source.exists())) {
  console.error(`No build output at ${built} — run the Vite build first.`)
  process.exit(1)
}

const html = await source.text()
const problems: string[] = []
if (!html.includes('<div id="root">')) problems.push("no #root mount point")
if (!html.includes("<style>")) problems.push("no inlined stylesheet")
if (!html.includes('type="module"')) problems.push("no inlined module script")
if (html.length < 200_000) problems.push(`implausibly small (${html.length} bytes)`)

if (problems.length) {
  console.error(`Refusing to embed a broken bundle: ${problems.join("; ")}.`)
  process.exit(1)
}

await mkdir(path.dirname(target), { recursive: true })
await Bun.write(target, html)
console.log(`embedded ${(html.length / 1024).toFixed(0)} KB -> src/server/web.html`)
