import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { useEffect } from "react"
import { api, type CreateJobsInput } from "./client"
import { connectEvents } from "./events"
import type { JobRecord } from "./types"

export const queryKeys = {
  meta: ["meta"] as const,
  catalog: ["catalog"] as const,
  jobs: ["jobs"] as const,
  library: ["library"] as const,
}

export function useMeta() {
  return useQuery({ queryKey: queryKeys.meta, queryFn: () => api.meta(), staleTime: Number.POSITIVE_INFINITY })
}

export function useCatalog() {
  return useQuery({ queryKey: queryKeys.catalog, queryFn: () => api.catalog(), staleTime: 10 * 60 * 1000 })
}

export function useLibrary() {
  return useQuery({ queryKey: queryKeys.library, queryFn: () => api.library(), staleTime: 15 * 1000 })
}

/**
 * Jobs live in the query cache and are patched in place by the event stream.
 * `onLibraryChanged` is the only thing that triggers a refetch, because that is
 * the only moment the on-disk truth actually changes.
 */
export function useJobs(onLibraryChanged?: () => void) {
  const queryClient = useQueryClient()

  const query = useQuery({ queryKey: queryKeys.jobs, queryFn: () => api.jobs(), staleTime: Number.POSITIVE_INFINITY })

  useEffect(() => {
    const disconnect = connectEvents({
      onJob: (job) => {
        queryClient.setQueryData<JobRecord[]>(queryKeys.jobs, (existing) => {
          const list = existing ?? []
          const index = list.findIndex((candidate) => candidate.id === job.id)
          if (index === -1) return [job, ...list]
          const next = [...list]
          next[index] = job
          return next
        })
      },
      onRemoved: ({}) => {
        // Fresh list is authoritative after a delete; one refetch is fine here.
        void queryClient.invalidateQueries({ queryKey: queryKeys.jobs })
      },
      onLibraryChanged: () => {
        void queryClient.invalidateQueries({ queryKey: queryKeys.library })
        onLibraryChanged?.()
      },
      onStatus: () => {},
    })
    return disconnect
  }, [queryClient, onLibraryChanged])

  return query
}

export function useStartDownloads(onResult?: (summary: { created: number; skipped: number; missing: number }) => void) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (input: CreateJobsInput) => api.createJobs(input),
    onSuccess: (response) => {
      queryClient.setQueryData<JobRecord[]>(queryKeys.jobs, (existing) => [...response.created, ...(existing ?? [])])
      onResult?.({
        created: response.created.length,
        skipped: response.skipped.length,
        missing: response.missing.length,
      })
    },
  })
}

export function useJobActions() {
  const queryClient = useQueryClient()
  const invalidateJobs = () => queryClient.invalidateQueries({ queryKey: queryKeys.jobs })

  return {
    cancel: useMutation({ mutationFn: api.cancelJob, onSuccess: invalidateJobs }),
    retry: useMutation({ mutationFn: api.retryJob, onSuccess: invalidateJobs }),
    remove: useMutation({ mutationFn: api.removeJob, onSuccess: invalidateJobs }),
    clearFinished: useMutation({ mutationFn: api.clearFinished, onSuccess: invalidateJobs }),
  }
}
