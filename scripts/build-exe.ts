/**
 * Compile the server (with the web bundle already embedded in it) into a
 * standalone executable. Pass target names as arguments, or `--all`.
 */

import { mkdir } from "node:fs/promises"
import path from "node:path"

const TARGETS = ["linux-arm64", "linux-x64", "windows-x64", "darwin-arm64", "darwin-x64"] as const
type Target = (typeof TARGETS)[number]

const root = path.resolve(import.meta.dir, "..")
const outDir = path.join(root, "dist")

async function main() {
  const args = Bun.argv.slice(2).filter((arg) => !arg.startsWith("--"))
  const all = Bun.argv.includes("--all")
  const requested: Target[] = args.length ? (args as Target[]) : all ? [...TARGETS] : [hostTarget()]

  const embedded = Bun.file(path.join(root, "src", "server", "web.html"))
  if (!(await embedded.exists()) || (await embedded.text()).startsWith("placeholder:")) {
    console.error("The web bundle is not embedded yet — run `bun run build:web` first.")
    process.exit(1)
  }

  await mkdir(outDir, { recursive: true })

  for (const target of requested) {
    if (!TARGETS.includes(target)) {
      console.error(`Unknown target "${target}". Known: ${TARGETS.join(", ")}`)
      process.exit(1)
    }
    const extension = target.startsWith("windows") ? ".exe" : ""
    const outfile = path.join(outDir, `skillcapped-downloader-${target}${extension}`)
    console.log(`building ${target} …`)

    const result = Bun.spawnSync({
      cmd: [
        "bun",
        "build",
        path.join(root, "src", "index.ts"),
        "--compile",
        `--target=bun-${target}`,
        "--minify",
        "--sourcemap",
        `--outfile=${outfile}`,
      ],
      stdout: "inherit",
      stderr: "inherit",
    })
    if (result.exitCode !== 0) {
      console.error(`build failed for ${target}`)
      process.exit(result.exitCode ?? 1)
    }
    const size = Bun.file(outfile).size
    console.log(`  -> ${path.relative(root, outfile)} (${(size / 1024 / 1024).toFixed(1)} MB)`)
  }
}

function hostTarget(): Target {
  const platform = process.platform === "win32" ? "windows" : process.platform === "darwin" ? "darwin" : "linux"
  const arch = process.arch === "x64" ? "x64" : "arm64"
  const candidate = `${platform}-${arch}` as Target
  return TARGETS.includes(candidate) ? candidate : "linux-arm64"
}

await main()
