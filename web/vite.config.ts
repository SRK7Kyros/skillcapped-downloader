import path from "node:path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig, type Plugin } from "vite"

/*
 * The web app ships INSIDE the executable, so the build must collapse to one
 * `index.html`: `singleFile()` splices every JS chunk and stylesheet into the
 * document during `generateBundle` and deletes the sidecar entries.
 * `assetsInlineLimit` is unbounded so the self-hosted woff2 faces become data
 * URIs instead of files.
 *
 * Each entry must prove it was inlined, and the final check is the bundle-entry
 * count rather than a scan of the document text: the inlined JavaScript carries
 * script-tag strings of its own (React's hoisting helpers), so a regex over the
 * HTML cannot tell a real tag from a string literal.
 */
function singleFile(): Plugin {
  return {
    name: "skillcapped:single-file",
    enforce: "post",
    generateBundle(_options, bundle) {
      const htmlKey = Object.keys(bundle).find((key) => key.endsWith(".html"))
      if (!htmlKey) throw new Error("single-file: no .html asset was emitted")
      const htmlAsset = bundle[htmlKey] as { source: string | Uint8Array }
      let html = String(htmlAsset.source)

      for (const [fileName, output] of Object.entries(bundle)) {
        if (fileName === htmlKey) continue
        const base = path.basename(fileName).replace(/[.$?*+^\[\]\\(){}|]/g, "\\$&")
        const tag = (attribute: "src" | "href") =>
          new RegExp(`<[^>]+${attribute}=["'][^"']*${base}["'][^>]*>`)

        const before = html
        if (output.type === "chunk") {
          // A replacer function, not a string: `$&`/`` $` ``/`$'` inside a
          // minified 1 MB bundle are substitution patterns to String.replace and
          // would splice the surrounding document into the code.
          const code = output.code.replace(/<\/script/gi, "<\\/script")
          html = html.replace(tag("src"), () => `<script type="module">${code}</script>`)
        } else if (fileName.endsWith(".css")) {
          html = html.replace(tag("href"), () => `<style>${String(output.source)}</style>`)
        }
        if (html === before) {
          throw new Error(`single-file: ${fileName} (${output.type}) was emitted but never referenced by ${htmlKey}`)
        }
        delete bundle[fileName]
      }

      const unhandled = Object.keys(bundle).filter((key) => key !== htmlKey)
      if (unhandled.length) {
        throw new Error(`single-file: ${unhandled.length} entry(s) not inlined: ${unhandled.join(", ")}`)
      }
      htmlAsset.source = html
    },
  }
}

export default defineConfig({
  plugins: [react(), tailwindcss(), singleFile()],
  resolve: { alias: { "@": path.resolve(import.meta.dirname, "./src") } },
  build: {
    target: "esnext",
    cssCodeSplit: false,
    assetsInlineLimit: Number.MAX_SAFE_INTEGER,
    chunkSizeWarningLimit: 4000,
  },
  server: {
    host: "127.0.0.1",
    port: 5179,
    strictPort: true,
    proxy: {
      "/api": { target: "http://127.0.0.1:4780", changeOrigin: false },
    },
  },
})
