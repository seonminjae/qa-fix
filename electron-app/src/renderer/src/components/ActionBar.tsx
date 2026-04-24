import React from 'react'
import type { AgentState } from '@shared/types'
import { cx } from '../lib/cx.js'

const btnPrimary = 'bg-blue-600 hover:bg-blue-500 text-white rounded px-3 py-1.5 text-sm transition-colors disabled:opacity-40 disabled:cursor-not-allowed'
const btnSecondary = 'bg-surface-2 hover:bg-surface-3 text-slate-200 rounded px-3 py-1.5 text-sm border border-surface-3 transition-colors disabled:opacity-40 disabled:cursor-not-allowed'
const btnDanger = 'bg-red-900/50 hover:bg-red-800/60 text-red-300 rounded px-3 py-1.5 text-sm border border-red-900/60 transition-colors disabled:opacity-40 disabled:cursor-not-allowed'

interface Props {
  state: AgentState
  onCommit: () => void
  onRefix: () => void
  onCancel: () => void
  onExit: () => void
}

function formatCost(usd: number): string {
  return `$${usd.toFixed(4)}`
}

function formatTokens(n: number): string {
  if (n >= 1000) return `${Math.round(n / 1000)}k`
  return String(n)
}

export function ActionBar({ state, onCommit, onRefix, onCancel, onExit }: Props) {
  const { phase, cumulativeCost, cumulativeInputTokens, cumulativeOutputTokens, commitSHA } = state
  const isRunning = phase === 'debugger' || phase === 'verifier' || phase === 'question'
  const isFinished = phase === 'finished'
  const isFailed = phase === 'failed'

  return (
    <div className="shrink-0 flex items-center gap-2 px-4 py-2 bg-surface-1 border-t border-surface-3">
      {isRunning && (
        <>
          <span className="text-xs text-slate-500 animate-pulse">실행 중…</span>
          <button className={btnDanger} onClick={onCancel}>Cancel</button>
        </>
      )}

      {isFinished && (
        <>
          <button className={btnPrimary} onClick={onCommit}>Commit</button>
          <button className={btnSecondary} onClick={onRefix}>Re-fix</button>
          <button className={btnDanger} onClick={onCancel}>변경사항 폐기</button>
          <button className={cx(btnSecondary, 'ml-1')} onClick={onExit}>← 목록으로</button>
        </>
      )}

      {isFailed && (
        <>
          <button className={btnDanger} onClick={onCancel}>변경사항 폐기</button>
          <button className={btnSecondary} onClick={onExit}>← 목록으로</button>
        </>
      )}

      {phase === 'idle' && (
        <span className="text-xs text-slate-600">대기 중</span>
      )}

      <div className="ml-auto flex items-center gap-3 text-xs text-slate-500 font-mono shrink-0">
        {(cumulativeCost > 0 || cumulativeInputTokens > 0) && (
          <span>
            {formatCost(cumulativeCost)} · in {formatTokens(cumulativeInputTokens)} · out {formatTokens(cumulativeOutputTokens)}
          </span>
        )}
        {commitSHA && (
          <span className="text-emerald-400 font-semibold">
            Committed {commitSHA.slice(0, 7)}
          </span>
        )}
      </div>
    </div>
  )
}
