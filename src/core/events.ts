/**
 * Minimal typed event bus. The server pushes job + library changes to the
 * browser over SSE; nothing else in the app is event-driven.
 */

export type Listener<T> = (payload: T) => void

export class Emitter<EventMap extends Record<string, unknown>> {
  private listeners = new Map<keyof EventMap, Set<Listener<never>>>()

  on<K extends keyof EventMap>(event: K, listener: Listener<EventMap[K]>): () => void {
    let set = this.listeners.get(event)
    if (!set) {
      set = new Set()
      this.listeners.set(event, set)
    }
    set.add(listener as Listener<never>)
    return () => set.delete(listener as Listener<never>)
  }

  emit<K extends keyof EventMap>(event: K, payload: EventMap[K]): void {
    const set = this.listeners.get(event)
    if (!set) return
    for (const listener of set) {
      try {
        ;(listener as Listener<EventMap[K]>)(payload)
      } catch {
        // A broken listener must never take down the download pipeline.
      }
    }
  }

  clear(): void {
    this.listeners.clear()
  }
}
