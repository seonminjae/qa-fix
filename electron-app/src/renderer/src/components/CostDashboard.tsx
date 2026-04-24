import React from 'react'
import type { AgentState } from '@shared/types'

interface Props {
  state: AgentState
}

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-surface-1 border border-surface-3 rounded-md px-5 py-4 flex flex-col gap-1">
      <span className="text-xs text-slate-500 uppercase tracking-wide">{label}</span>
      <span className="text-2xl font-mono font-semibold text-slate-100">{value}</span>
    </div>
  )
}

function formatTokens(n: number): string {
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(2)}M`
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`
  return String(n)
}

export function CostDashboard({ state }: Props) {
  const { cumulativeCost, cumulativeInputTokens, cumulativeOutputTokens, phase, refixCount, maxRefix } = state

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-6 py-6">
        <h2 className="text-xs font-semibold uppercase tracking-widest text-slate-500 mb-4">
          현재 세션 비용
        </h2>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <StatCard label="총 비용" value={`$${cumulativeCost.toFixed(4)}`} />
          <StatCard label="입력 토큰" value={formatTokens(cumulativeInputTokens)} />
          <StatCard label="출력 토큰" value={formatTokens(cumulativeOutputTokens)} />
          <StatCard label="재수정 횟수" value={`${refixCount} / ${maxRefix}`} />
          <StatCard
            label="페이즈"
            value={phase === 'idle' ? '대기' : phase === 'debugger' ? '디버거' : phase === 'verifier' ? '검증' : phase === 'question' ? '질문' : phase === 'finished' ? '완료' : '실패'}
          />
        </div>

        {phase === 'idle' && cumulativeCost === 0 && (
          <p className="text-sm text-slate-600 mt-8 text-center">
            세션을 시작하면 비용이 여기에 표시됩니다.
          </p>
        )}
      </div>
    </div>
  )
}
