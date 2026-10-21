import Hls from "hls.js"
import { useEffect, useRef, useState } from "react"
import { api } from "../../api/client"
import type { CatalogItem, Quality } from "../../api/types"
import { formatDuration, roleVar } from "../../lib/format"
import { Icon } from "../icons"
import { Button, Modal, Segmented, Spinner } from "../primitives"

/**
 * Preview player. There is no upstream manifest, so this plays a playlist the
 * server synthesises from the same segment URL scheme the downloader uses —
 * which makes the preview a live proof that the download path is correct.
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
  const videoRef = useRef<HTMLVideoElement>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    if (!item) return
    const video = videoRef.current
    if (!video) return

    setError(null)
    setLoading(true)
    const url = api.streamPlaylistUrl(item.id, quality, item.durationSec)

    const nativeHls = video.canPlayType("application/vnd.apple.mpegurl") !== ""
    if (!Hls.isSupported()) {
      if (nativeHls) {
        video.src = url
        void video.play().catch(() => {})
        return
      }
      setLoading(false)
      setError("This browser cannot play HLS streams. Downloads still work.")
      return
    }

    const hls = new Hls({ maxBufferSize: 0, maxBufferLength: 30 })
    hls.on(Hls.Events.MANIFEST_PARSED, () => {
      setLoading(false)
      void video.play().catch(() => {})
    })
    hls.on(Hls.Events.ERROR, (_event, data) => {
      if (!data.fatal) return
      setLoading(false)
      setError(
        data.details === "manifestLoadError"
          ? "The stream could not be located. This video may no longer be published."
          : `Playback stopped (${data.details}).`,
      )
      hls.destroy()
    })

    hls.loadSource(url)
    hls.attachMedia(video)

    return () => {
      hls.destroy()
      video.removeAttribute("src")
      video.load()
    }
  }, [item, quality])

  const color = item ? roleVar(item.role) : "var(--accent)"

  return (
    <Modal open={Boolean(item)} onOpenChange={(open) => (!open ? onClose() : undefined)} title={item?.title ?? "Preview"}>
      {item ? (
        <div>
          <div className="relative aspect-video w-full bg-black">
            <video ref={videoRef} controls playsInline className="h-full w-full" />
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

            <Segmented
              ariaLabel="Preview quality"
              value={String(quality)}
              onChange={(value) => onQualityChange(Number(value))}
              options={qualities.map((option) => ({ value: String(option.id), label: option.short }))}
            />

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
