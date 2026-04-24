import { useEffect, useState } from 'react'
import type { AgentState } from '@shared/types'
import { emptyAgentState } from '@shared/types'

export function useAgentState(): AgentState {
  const [state, setState] = useState<AgentState>(emptyAgentState)

  useEffect(() => {
    let cancelled = false

    window.api.agent.getState().then((s) => {
      if (!cancelled) setState(s)
    })

    const unsub = window.api.agent.onUpdate((s) => {
      if (!cancelled) setState(s)
    })

    return () => {
      cancelled = true
      unsub()
    }
  }, [])

  return state
}
