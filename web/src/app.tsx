import { useQueryClient } from "@tanstack/react-query"
import { useCallback, useState } from "react"
import { api } from "./api/client"
import { queryKeys, useCatalog, useJobActions, useJobs, useLibrary, useMeta } from "./api/hooks"
import type { CatalogResponse, LibraryResponse, Meta } from "./api/types"
import { Icon } from "./ui/icons"
import { Button, Drawer, IconButton, Segmented, Spinner } from "./ui/primitives"
import { DownloadsPanel, isActive } from "./ui/components/downloads-panel"
import { Toasts } from "./ui/components/toasts"
import { AppProvider, useSelection } from "./ui/store"
import { BrowseView } from "./ui/views/browse"
import { LibraryView } from "./ui/views/library"

function Boot({ label, detail }: { label: string; detail?: string }) {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center gap-3 px-6 text-center">
      <span className="grid h-11 w-11 place-items-center rounded-[var(--r-md)] border border-line bg-surface-1 text-brand">
        <Icon name="logo" size={20} />
      </span>
      <div className="space-y-1">
        <p className="text-[13px] font-semibold text-ink">{label}</p>
        {detail ? <p className="max-w-md text-[11.5px] leading-relaxed text-ink-muted">{detail}</p> : null}
      </div>
      {!detail ? <Spinner size={16} className="text-ink-dim" /> : null}
    </div>
  )
}

export function App() {
  const meta = useMeta()

  if (meta.isPending) return <Boot label="Starting the local server…" />
  if (meta.isError) {
    return (
      <Boot
        label="The local API did not answer"
        detail={`${(meta.error as Error).message}. Restart the executable, then reload this page.`}
      />
    )
  }

  return (
    <AppProvider
      defaults={{
        quality: meta.data.defaults.quality,
        remux: meta.data.defaults.remux,
        skipExisting: true,
      }}
    >
      <Shell meta={meta.data} />
    </AppProvider>
  )
}

function Shell({ meta }: { meta: Meta }) {
  const { toasts, dismiss, notify, downloadsOpen, setDownloadsOpen } = useSelection()
  const [view, setView] = useState<"browse" | "library">("browse")
  const [refreshing, setRefreshing] = useState(false)

  const queryClient = useQueryClient()
  const catalog = useCatalog()
  const library = useLibrary()
  const jobs = useJobs()
  const actions = useJobActions()

  const jobList = jobs.data ?? []
  const activeCount = jobList.filter((job) => isActive(job.status)).length

  const refresh = useCallback(async () => {
    setRefreshing(true)
    try {
      const fresh = await api.catalog(true)
      queryClient.setQueryData<CatalogResponse>(queryKeys.catalog, fresh)
      notify(`Catalogue refreshed — ${fresh.items.length.toLocaleString()} items`, "success")
    } catch (error) {
      notify((error as Error).message, "danger")
    } finally {
      setRefreshing(false)
    }
  }, [notify, queryClient])

  const openFolder = async () => {
    try {
      await api.openFolder()
    } catch (error) {
      notify((error as Error).message, "danger")
    }
  }

  const loading = catalog.isPending || library.isPending

  return (
    <div className="min-h-dvh">
      <header className="fixed inset-x-0 top-0 z-[var(--z-topbar)] h-[var(--topbar-h)] border-b border-line bg-canvas/92 backdrop-blur-md">
        <div className="mx-auto flex h-full max-w-[var(--content-max)] items-center gap-3 px-4 sm:px-6">
          <span className="grid h-8 w-8 shrink-0 place-items-center rounded-[var(--r-sm)] border border-line bg-surface-1 text-brand">
            <Icon name="logo" size={17} />
          </span>
          <div className="min-w-0">
            <p className="truncate text-[12.5px] leading-tight font-semibold text-ink">
              SkillCapped <span className="font-normal text-ink-dim">Downloader</span>
            </p>
            <p className="truncate text-[10px] leading-tight text-ink-faint">
              {catalog.data ? `${catalog.data.season} · patch ${catalog.data.patch}` : "loading catalogue…"}
              {meta.standalone ? "" : " · dev"}
            </p>
          </div>

          <div className="ml-auto flex items-center gap-2">
            <Segmented
              ariaLabel="Section"
              value={view}
              onChange={setView}
              options={[
                { value: "browse", label: "Browse", icon: "grid" },
                { value: "library", label: "Library", icon: "folder" },
              ]}
            />
            <Button
              variant={activeCount ? "primary" : "secondary"}
              size="sm"
              icon="download"
              onClick={() => setDownloadsOpen(true)}
              className="tab-stop"
            >
              Downloads
              {jobList.length ? (
                <span
                  className={
                    activeCount
                      ? "inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-brand-ink/25 px-1 font-mono text-[9.5px] font-bold tabular-nums"
                      : "inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-surface-4 px-1 font-mono text-[9.5px] font-bold text-ink-dim tabular-nums"
                  }
                >
                  {activeCount || jobList.length}
                </span>
              ) : null}
            </Button>
            <IconButton icon="folder" label="Open the content folder" onClick={() => void openFolder()} />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-[var(--content-max)] px-4 pt-[calc(var(--topbar-h)+16px)] pb-28 sm:px-6">
        {loading ? (
          <div className="flex items-center justify-center gap-2 py-24 text-[12px] text-ink-dim">
            <Spinner size={15} />
            Loading the catalogue…
          </div>
        ) : catalog.isError ? (
          <div className="rounded-[var(--r-md)] border border-danger/40 bg-danger-dim px-4 py-3">
            <p className="text-[12px] font-semibold text-danger">The catalogue could not be loaded</p>
            <p className="mt-1 text-[11px] leading-relaxed text-ink-muted">{(catalog.error as Error).message}</p>
            <Button size="sm" variant="secondary" icon="retry" className="mt-2.5" onClick={() => void refresh()}>
              Try again
            </Button>
          </div>
        ) : view === "browse" ? (
          <BrowseView
            catalog={catalog.data as CatalogResponse}
            library={library.data as LibraryResponse}
            meta={meta}
            onOpenDownloads={() => setDownloadsOpen(true)}
            onRefresh={() => void refresh()}
            refreshing={refreshing}
          />
        ) : (
          <LibraryView library={library.data as LibraryResponse} meta={meta} onNotify={notify} />
        )}
      </main>

      <Drawer
        open={downloadsOpen}
        onOpenChange={setDownloadsOpen}
        title="Downloads"
        description={`${meta.tools.ffmpeg ? "Remuxing to MP4" : "Saving raw transport streams"} · ${meta.contentDir}`}
      >
        <DownloadsPanel
          jobs={jobList}
          qualities={meta.qualities}
          defaults={{ quality: meta.defaults.quality, concurrency: meta.defaults.concurrency }}
          tools={{ ffmpeg: meta.tools.ffmpeg }}
          onCancel={(id) => actions.cancel.mutate(id)}
          onRetry={(id) => actions.retry.mutate(id)}
          onRemove={(id) => actions.remove.mutate(id)}
          onClearFinished={() => actions.clearFinished.mutate()}
          onOpenFolder={() => void openFolder()}
          onClose={() => setDownloadsOpen(false)}
        />
      </Drawer>

      <Toasts toasts={toasts} onDismiss={dismiss} />
    </div>
  )
}
