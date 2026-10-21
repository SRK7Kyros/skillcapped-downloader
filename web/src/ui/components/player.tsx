import Hls from "hls.js"
import { useEffect, useState } from "react"
import { api } from "../../api/client"
import type { CatalogItem, PreviewInfo, Quality } from "../../api/types"
import { formatDuration, roleVar } from "../../lib/format"
import { Icon } from "../icons"
import { Badge, Button, Modal, Segmented, Spinner } from "../primitives"

/** Why a media element refused to play, in words a person can act on. */
function mediaError(video: HTMLVideoElement): string {
  switch (video.error?.code) {
    case MediaError.MEDIA_ERR_SRC_NOT_SUPPORTED:
      return "This file cannot be played in the browser."
    case MediaError.MEDIA_ERR_DECODE:
      return "This file is damaged and cannot be decoded."
    case MediaError.MEDIA_ERR_NETWORK:
      return "Reading the file stopped — it may have moved."
    default:
      return "The preview could not be started."
  }
}

/**
 * Preview player. A video that is already downloaded plays straight from the
 * file on disk (native MP4, instant seeking); anything else streams the parts
 * the server relays from the CDN. The element is captured through state rather
 * than a ref: the modal mounts its content a commit later than the component
 * that owns the effect, so a ref was still null when the source was chosen and
 * the player never loaded anything.
 */
export function PreviewPlayer({
  item,
  qualities,
  quality,
  onQualityChange,
  onDownload,
  onClose,
}: {
  item: CatalogItem | null
  qualities: Quality[]
  quality: number
  onQualityChange: (quality: number) => void
  onDownload: (item: CatalogItem) => void
  onClose: () => void
}) {
  const [video, setVideo] = useState<HTMLVideoElement | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)
  const [source, setSource] = useState<PreviewInfo | null>(null)

  useEffect(() => {
    if (!item || !video) return

    const controller = new AbortController()
    let hls: Hls | null = null
    let mounted = true

    const fail = (message: string) => {
      if (!mounted) return
      setLoading(false)
      setError(message)
    }

    const start = (info: PreviewInfo) => {
      if (!mounted) return
      setSource(info)

      if (info.mode === "local") {
        video.src = info.url
        video.addEventListener("loadeddata", () => mounted && setLoading(false), { once: true })
        video.addEventListener("error", () => fail(mediaError(video)), { once: true })
        void video.play().catch(() => {})
        return
      }

      if (!Hls.isSupported()) {
        if (video.canPlayType("application/vnd.apple.mpegurl")) {
          video.src = info.url
          video.addEventListener("loadeddata", () => mounted && setLoading(false), { once: true })
          void video.play().catch(() => {})
          return
        }
        fail("This browser cannot play HLS streams. Downloading still works.")
        return
      }

      hls = new Hls({ maxBufferLength: 30 })
      hls.on(Hls.Events.MANIFEST_PARSED, () => {
        if (!mounted) return
        setLoading(false)
        void video.play().catch(() => {})
      })
      hls.on(Hls.Events.ERROR, (_event, data) => {
        if (!data.fatal) return
        fail(
          data.details === "manifestLoadError"
            ? "This video is not published on the CDN — downloading it will fail too."
            : `Playback stopped (${data.details}).`,
        )
        hls?.destroy()
        hls = null
      })
      hls.loadSource(info.url)
      hls.attachMedia(video)
    }

    setError(null)
    setSource(null)
    setLoading(true)

    void api.preview(item.id, quality, item.durationSec, controller.signal).then(start).catch((cause: unknown) => {
      if (controller.signal.aborted) return
      fail(cause instanceof Error ? cause.message : "The preview could not be prepared.")
    })

    return () => {
      mounted = false
      controller.abort()
      hls?.destroy()
      video.removeAttribute("src")
      video.load()
    }
  }, [video, item, quality])

  const color = item ? roleVar(item.role) : "var(--accent)"
  const local = source?.mode === "local"

  return (
    <Modal open={Boolean(item)} onOpenChange={(open) => (!open ? onClose() : undefined)} title={item?.title ?? "Preview"}>
      {item ? (
        <div>
          <div className="relative aspect-video w-full bg-black">
            <video ref={setVideo} controls playsInline className="h-full w-full" />
            {loading && !error ? (
              <div className="pointer-events-none absolute inset-0 grid place-items-center">
                <Spinner size={22} className="text-white/70" />
              </div>
            ) : null}
            {error ? (
              <div className="absolute inset-0 grid place-items-center bg-black/75 px-6 text-center">
                <div className="space-y-1.5">
                  <Icon name="alert" size={20} className="mx-auto text-warning" />
                  <p className="text-[12px] font-medium text-ink">{error}</p>
                </div>
              </div>
            ) : null}
          </div>

          <div className="flex flex-wrap items-center gap-3 border-t border-line px-4 py-3">
            <div className="min-w-0 flex-1">
              <p className="truncate text-[12px] font-medium text-ink">{item.title}</p>
              <p className="mt-0.5 flex items-center gap-2 text-[10.5px] text-ink-dim">
                <span className="inline-flex items-center gap-1">
                  <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
                  <span className="uppercase" style={{ color }}>
                    {item.role}
                  </span>
                </span>
                <span>{formatDuration(item.durationSec)}</span>
                {item.category ? <span className="truncate">· {item.category}</span> : null}
              </p>
            </div>

            {local ? (
              <Badge className="h-6 px-2 text-[10px]" color="var(--success)">
                From disk{source.label ? ` · ${source.label}` : ""}
              </Badge>
            ) : (
              <Segmented
                ariaLabel="Preview quality"
                value={String(quality)}
                onChange={(value) => onQualityChange(Number(value))}
                options={qualities.map((option) => ({ value: String(option.id), label: option.short }))}
              />
            )}

            <Button variant="primary" icon="download" onClick={() => onDownload(item)}>
              Download
            </Button>
          </div>

          {item.kind === "commentary" && item.champions ? (
            <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-line px-4 py-2.5 text-[10.5px] text-ink-dim">
              <span>Match-up: <span className="text-ink">{item.champions}</span></span>
              {item.kda ? <span>KDA: <span className="font-mono text-ink">{item.kda}</span></span> : null}
              {item.staff ? <span>Coach: <span className="text-ink">{item.staff}</span></span> : null}
            </div>
          ) : null}
        </div>
      ) : null}
    </Modal>
  )
}
