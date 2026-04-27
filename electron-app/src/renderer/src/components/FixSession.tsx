import React, { useEffect, useState } from 'react'
import type { Ticket, DiffFile } from '@shared/types'
import { useAgentState } from '../hooks/useAgentState.js'
import { AgentLog } from './AgentLog.js'
import { DiffView } from './DiffView.js'
import { ActionBar } from './ActionBar.js'
import { QuestionView } from './QuestionView.js'

interface Props {
  ticket: Ticket
  repoPath: string
  mode: 'start' | 'resume'
  onExit: () => void
}

function SeverityPill({ severity }: { severity: string }) {
  const cls: Record<string, string> = {
    Critical: 'bg-severity-critical/20 text-severity-critical border-severity-critical/40',
    Major: 'bg-severity-major/20 text-severity-major border-severity-major/40',
    Minor: 'bg-severity-minor/20 text-severity-minor border-severity-minor/40',
    Trivial: 'bg-severity-trivial/20 text-severity-trivial border-severity-trivial/40',
    '-': 'bg-severity-unknown/20 text-severity-unknown border-severity-unknown/40',
  }
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium border ${cls[severity] ?? cls['-']}`}>
      {severity}
    </span>
  )
}

export function FixSession({ ticket, repoPath, mode, onExit }: Props) {
  const { state, streaming } = useAgentState()
  const [started, setStarted] = useState(false)
  const [diffFiles, setDiffFiles] = useState<DiffFile[]>([])
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (started) return
    setStarted(true)
    if (mode === 'resume') return
    window.api.agent.start({ ticket, repoPath }).catch((e: unknown) => {
      setError(String(e instanceof Error ? e.message : e))
    })
  }, [started, ticket, repoPath, mode])

  useEffect(() => {
    if (!state.diff) {
      setDiffFiles([])
      return
    }
    window.api.git.parseDiff(state.diff).then(setDiffFiles).catch(() => setDiffFiles([]))
  }, [state.diff])

  async function handleCommit() {
    setError(null)
    try {
      await window.api.agent.commit()
    } catch (e: unknown) {
      setError(String(e instanceof Error ? e.message : e))
    }
  }

  async function handleRefix() {
    setError(null)
    try {
      await window.api.agent.start({ ticket, repoPath })
    } catch (e: unknown) {
      setError(String(e instanceof Error ? e.message : e))
    }
  }

  async function handleCancel() {
    setError(null)
    try {
      await window.api.agent.cancel()
      await window.api.agent.discardChanges()
    } catch (e: unknown) {
      setError(String(e instanceof Error ? e.message : e))
    }
    onExit()
  }

  async function handleSubmitAnswer(answer: string) {
    try {
      await window.api.agent.submitAnswer(answer)
    } catch (e: unknown) {
      setError(String(e instanceof Error ? e.message : e))
    }
  }

  return (
    <div className="flex flex-col h-full">
      {/* Ticket header */}
      <div className="shrink-0 px-4 py-3 border-b border-surface-3 bg-surface-1">
        <div className="flex items-center gap-3">
          <button
            className="text-xs text-slate-500 hover:text-slate-300 transition-colors"
            onClick={onExit}
            type="button"
          >
            ← 목록
          </button>
          <SeverityPill severity={ticket.severity} />
          <span className="font-mono text-xs text-slate-500">{ticket.displayID}</span>
          <h2 className="text-sm font-semibold text-slate-100 truncate flex-1">{ticket.title}</h2>
        </div>
        {ticket.environment.length > 0 && (
          <div className="flex gap-1 mt-1.5">
            {ticket.environment.map((env) => (
              <span key={env} className="bg-surface-3 rounded px-1.5 py-0.5 text-xs text-slate-400">
                {env}
              </span>
            ))}
          </div>
        )}
      </div>

      {/* Main split */}
      <div className="flex-1 flex overflow-hidden">
        {/* Left: agent log — 70% */}
        <div className="flex flex-col overflow-hidden" style={{ flex: '0 0 70%' }}>
          <div className="shrink-0 px-3 py-1.5 border-b border-surface-3 bg-surface-2">
            <span className="text-xs text-slate-500">Agent Log</span>
          </div>
          <div className="flex-1 overflow-hidden">
            <AgentLog log={state.log} streaming={streaming} />
          </div>
        </div>

        {/* Divider */}
        <div className="w-px bg-surface-3 shrink-0" />

        {/* Right: diff — 30% */}
        <div className="flex flex-col overflow-hidden flex-1">
          <div className="shrink-0 px-3 py-1.5 border-b border-surface-3 bg-surface-2">
            <span className="text-xs text-slate-500">Diff</span>
          </div>
          <div className="flex-1 overflow-hidden">
            <DiffView files={diffFiles} />
          </div>
        </div>
      </div>

      {/* Error banner */}
      {(error ?? state.lastError) && (
        <div className="shrink-0 px-4 py-2 bg-red-950/40 border-t border-red-900/40 text-xs text-red-400">
          {error ?? state.lastError}
        </div>
      )}

      {/* Action bar */}
      <ActionBar
        state={state}
        onCommit={handleCommit}
        onRefix={handleRefix}
        onCancel={handleCancel}
        onExit={onExit}
      />

      {/* Question overlay */}
      {state.phase === 'question' && (
        <QuestionView
          questionText={state.lastDebuggerOutput || '에이전트가 질문을 요청했습니다.'}
          onSubmit={handleSubmitAnswer}
          onCancel={handleCancel}
        />
      )}
    </div>
  )
}
