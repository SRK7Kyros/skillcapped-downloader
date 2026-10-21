/**
 * Realtime channel. Job progress arrives over SSE and is written straight into
 * the query cache — refetching a job list several times a second would be
 * wasteful, and the library only needs a refresh when a job settles.
 */

import type { JobRecord } from "./types"

type Handlers = {
  onJob: (job: JobRecord) => void
  onRemoved: (id: string) => void
  onLibraryChanged: () => void
  onStatus: (connected: boolean) => void
}

export function connectEvents(handlers: Handlers): () => void {
  const source = new EventSource("/api/events")

  source.addEventListener("open", () => handlers.onStatus(true))
  source.addEventListener("error", () => handlers.onStatus(false))
  source.addEventListener("hello", () => handlers.onStatus(true))

  source.addEventListener("job", (event) => {
    handlers.onJob(JSON.parse((event as MessageEvent).data) as JobRecord)
  })

  source.addEventListener("removed", (event) => {
    const payload = JSON.parse((event as MessageEvent).data) as { id: string }
    handlers.onRemoved(payload.id)
  })

  source.addEventListener("library", () => handlers.onLibraryChanged())

  return () => source.close()
}
