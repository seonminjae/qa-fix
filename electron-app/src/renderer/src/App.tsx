import React, { useEffect, useRef, useState } from 'react'
import type { Ticket } from '@shared/types'
import { TicketList } from './components/TicketList.js'
import { FixSession } from './components/FixSession.js'
import { Settings } from './components/Settings.js'
import { CostDashboard } from './components/CostDashboard.js'
import { useAgentState } from './hooks/useAgentState.js'
import { cx } from './lib/cx.js'

type Tab = 'tickets' | 'settings' | 'cost'

interface SessionState {
  ticket: Ticket
  repoPath: string
  mode: 'start' | 'resume'
}

export function App() {
  const [tab, setTab] = useState<Tab>('tickets')
  const [session, setSession] = useState<SessionState | null>(null)
  const { state: agentState } = useAgentState()
  const restoredRef = useRef(false)

  useEffect(() => {
    if (restoredRef.current) return
    if (
      !session &&
      agentState.ticket &&
      agentState.repoPath &&
      agentState.phase !== 'idle'
    ) {
      setSession({
        ticket: agentState.ticket,
        repoPath: agentState.repoPath,
        mode: 'resume',
      })
      restoredRef.current = true
    }
  }, [agentState.ticket, agentState.repoPath, agentState.phase, session])

  function handleStartSession(ticket: Ticket, repoPath: string) {
    setSession({ ticket, repoPath, mode: 'start' })
  }

  function handleExitSession() {
    setSession(null)
    setTab('tickets')
  }

  function handleResumeSession() {
    setTab('tickets')
    if (agentState.ticket && agentState.repoPath) {
      setSession({
        ticket: agentState.ticket,
        repoPath: agentState.repoPath,
        mode: 'resume',
      })
    }
  }

  const activeTicketID =
    agentState.phase !== 'idle' && agentState.ticket ? agentState.ticket.pageID : null

  const tabs: { id: Tab; label: string }[] = [
    { id: 'tickets', label: 'Tickets' },
    { id: 'settings', label: 'Settings' },
    { id: 'cost', label: 'Cost' },
  ]

  const hasActiveSession = session !== null || agentState.phase !== 'idle'
  const phaseLabel =
    agentState.phase === 'debugger'
      ? '디버깅 중'
      : agentState.phase === 'verifier'
      ? '검증 중'
      : agentState.phase === 'question'
      ? '질문 대기'
      : agentState.phase === 'finished'
      ? '완료'
      : agentState.phase === 'failed'
      ? '실패'
      : null
  const phaseDot =
    agentState.phase === 'debugger' || agentState.phase === 'verifier'
      ? 'bg-blue-400 animate-pulse'
      : agentState.phase === 'finished'
      ? 'bg-emerald-400'
      : agentState.phase === 'failed'
      ? 'bg-red-400'
      : 'bg-amber-400'

  return (
    <div className="h-screen flex flex-col bg-surface-0">
      {/* Header */}
      <header className="h-11 shrink-0 flex items-center px-4 border-b border-surface-3 bg-surface-1">
        <span className="text-sm font-semibold text-slate-200 tracking-tight mr-6">
          QA Fix
        </span>
        <nav className="flex items-center gap-1">
          {tabs.map(({ id, label }) => (
            <button
              key={id}
              type="button"
              onClick={() => setTab(id)}
              className={cx(
                'px-3 py-1 rounded text-sm transition-colors',
                tab === id
                  ? 'bg-surface-3 text-slate-100'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-surface-2'
              )}
            >
              {label}
            </button>
          ))}
        </nav>

        {/* Phase indicator — clickable to jump back to active session */}
        {phaseLabel && (
          <button
            type="button"
            onClick={handleResumeSession}
            disabled={!hasActiveSession}
            title={hasActiveSession ? '진행 중인 세션으로 이동' : undefined}
            className={cx(
              'ml-auto flex items-center gap-2 px-2 py-0.5 rounded transition-colors',
              hasActiveSession
                ? 'hover:bg-surface-2 cursor-pointer'
                : 'cursor-default'
            )}
          >
            <span className={cx('w-1.5 h-1.5 rounded-full', phaseDot)} />
            <span className="text-xs text-slate-400">{phaseLabel}</span>
            {agentState.ticket && (
              <span className="text-xs text-slate-500 font-mono">
                {agentState.ticket.displayID}
              </span>
            )}
          </button>
        )}
      </header>

      {/* Main content */}
      <main className="flex-1 overflow-hidden">
        {tab === 'tickets' &&
          (session ? (
            <FixSession
              ticket={session.ticket}
              repoPath={session.repoPath}
              mode={session.mode}
              onExit={handleExitSession}
            />
          ) : (
            <TicketList
              onStartSession={handleStartSession}
              onResumeSession={handleResumeSession}
              activeTicketID={activeTicketID}
            />
          ))}
        {tab === 'settings' && <Settings />}
        {tab === 'cost' && <CostDashboard state={agentState} />}
      </main>
    </div>
  )
}
