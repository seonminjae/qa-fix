import { useEffect, useRef, useState } from 'react'
import type { AgentState, AgentLogSource } from '@shared/types'
import { emptyAgentState } from '@shared/types'

export type StreamingBuffers = Partial<Record<AgentLogSource, string>>

export interface AgentStateWithStream {
  state: AgentState
  streaming: StreamingBuffers
}

export function useAgentState(): AgentStateWithStream {
  const [state, setState] = useState<AgentState>(emptyAgentState)
  const [streaming, setStreaming] = useState<StreamingBuffers>({})
  const lastEntryIdRef = useRef<string | null>(null)

  useEffect(() => {
    let cancelled = false

    window.api.agent.getState().then((s) => {
      if (cancelled) return
      setState(s)
      const last = s.log[s.log.length - 1]
      lastEntryIdRef.current = last ? last.id : null
    })

    const unsubUpdate = window.api.agent.onUpdate((s) => {
      if (cancelled) return
      setState(s)
      const last = s.log[s.log.length - 1]
      const newId = last ? last.id : null
      if (newId !== lastEntryIdRef.current && last) {
        lastEntryIdRef.current = newId
        setStreaming((prev) => {
          if (prev[last.source] === undefined) return prev
          const next = { ...prev }
          delete next[last.source]
          return next
        })
      }
    })

    const unsubChunk = window.api.agent.onStreamChunk((chunk) => {
      if (cancelled) return
      setStreaming((prev) => ({
        ...prev,
        [chunk.source]: (prev[chunk.source] ?? '') + chunk.text,
      }))
    })

    return () => {
      cancelled = true
      unsubUpdate()
      unsubChunk()
    }
  }, [])

  return { state, streaming }
}
