import {
  catalogSchema,
  createJobsSchema,
  jobsResponseSchema,
  librarySchema,
  metaSchema,
  type CatalogResponse,
  type CreateJobsResponse,
  type JobRecord,
  type LibraryResponse,
  type Meta,
} from "./types"

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message)
    this.name = "ApiError"
  }
}

async function request(path: string, init?: RequestInit): Promise<unknown> {
  const response = await fetch(path, {
    headers: { accept: "application/json", ...(init?.body ? { "content-type": "application/json" } : {}) },
    ...init,
  })
  const text = await response.text()
  const payload = text ? (JSON.parse(text) as unknown) : {}
  if (!response.ok) {
    const message = (payload as { error?: string }).error ?? `Request failed (HTTP ${response.status})`
    throw new ApiError(message, response.status)
  }
  return payload
}

export type CreateJobsInput = {
  ids: string[]
  quality: number
  remux: boolean
  skipExisting: boolean
}

export const api = {
  async meta(): Promise<Meta> {
    return metaSchema.parse(await request("/api/meta"))
  },

  async catalog(refresh = false): Promise<CatalogResponse> {
    return catalogSchema.parse(await request(`/api/catalog${refresh ? "?refresh=1" : ""}`))
  },

  async jobs(): Promise<JobRecord[]> {
    return jobsResponseSchema.parse(await request("/api/jobs")).jobs
  },

  async library(): Promise<LibraryResponse> {
    return librarySchema.parse(await request("/api/library"))
  },

  async createJobs(input: CreateJobsInput): Promise<CreateJobsResponse> {
    return createJobsSchema.parse(
      await request("/api/jobs", { method: "POST", body: JSON.stringify(input) }),
    )
  },

  async cancelJob(id: string): Promise<void> {
    await request(`/api/jobs/${id}/cancel`, { method: "POST" })
  },

  async retryJob(id: string): Promise<void> {
    await request(`/api/jobs/${id}/retry`, { method: "POST" })
  },

  async removeJob(id: string): Promise<void> {
    await request(`/api/jobs/${id}`, { method: "DELETE" })
  },

  async clearFinished(): Promise<void> {
    await request("/api/jobs/clear", { method: "POST" })
  },

  async openFolder(): Promise<void> {
    await request("/api/open-folder", { method: "POST" })
  },

  /** Synthetic VOD playlist the preview player feeds to hls.js. */
  streamPlaylistUrl(uuid: string, quality: number, durationSec: number): string {
    const params = new URLSearchParams({ quality: String(quality), dur: String(Math.round(durationSec)) })
    return `/api/stream/${uuid}.m3u8?${params.toString()}`
  },
}
