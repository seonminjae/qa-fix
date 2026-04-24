import React, { useState } from 'react'
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
}

export function App() {
  const [tab, setTab] = useState<Tab>('tickets')
  const [session, setSession] = useState<SessionState | null>(null)
  const agentState = useAgentState()

  function handleStartSession(ticket: Ticket, repoPath: string) {
    setSession({ ticket, repoPath })
  }

  function handleExitSession() {
    setSession(null)
    setTab('tickets')
  }

  const tabs: { id: Tab; label: string }[] = [
    { id: 'tickets', label: 'Tickets' },
    { id: 'settings', label: 'Settings' },
    { id: 'cost', label: 'Cost' },
  ]

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
              onClick={() => {
                setTab(id)
                if (id !== 'tickets') setSession(null)
              }}
              className={cx(
                'px-3 py-1 rounded text-sm transition-colors',
                tab === id && !session
                  ? 'bg-surface-3 text-slate-100'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-surface-2'
              )}
            >
              {label}
            </button>
          ))}
        </nav>

        {/* Phase indicator in header */}
        {agentState.phase !== 'idle' && (
          <div className="ml-auto flex items-center gap-2">
            <span
              className={cx(
                'w-1.5 h-1.5 rounded-full',
                agentState.phase === 'debugger' || agentState.phase === 'verifier'
                  ? 'bg-blue-400 animate-pulse'
                  : agentState.phase === 'finished'
                  ? 'bg-emerald-400'
                  : agentState.phase === 'failed'
                  ? 'bg-red-400'
                  : 'bg-amber-400'
              )}
            />
            <span className="text-xs text-slate-500">
              {agentState.phase === 'debugger'
                ? '디버깅 중'
                : agentState.phase === 'verifier'
                ? '검증 중'
                : agentState.phase === 'question'
                ? '질문 대기'
                : agentState.phase === 'finished'
                ? '완료'
                : '실패'}
            </span>
          </div>
        )}
      </header>

      {/* Main content */}
      <main className="flex-1 overflow-hidden">
        {session ? (
          <FixSession
            ticket={session.ticket}
            repoPath={session.repoPath}
            onExit={handleExitSession}
          />
        ) : tab === 'tickets' ? (
          <TicketList onStartSession={handleStartSession} />
        ) : tab === 'settings' ? (
          <Settings />
        ) : (
          <CostDashboard state={agentState} />
        )}
      </main>
    </div>
  )
}
