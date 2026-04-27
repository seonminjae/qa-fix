import React, { useEffect, useRef } from 'react'
import type { AgentLogEntry, AgentLogSource } from '@shared/types'
import type { StreamingBuffers } from '../hooks/useAgentState.js'
import { cx } from '../lib/cx.js'

const sourceColor: Record<AgentLogSource, string> = {
  debugger: 'text-cyan-300',
  verifier: 'text-emerald-300',
  toolUse: 'text-slate-400',
  toolResult: 'text-slate-500',
  error: 'text-red-400',
  user: 'text-amber-300',
  system: 'text-slate-500',
}

const sourceLabel: Record<AgentLogSource, string> = {
  debugger: 'DEBUGGER',
  verifier: 'VERIFIER',
  toolUse: 'TOOL',
  toolResult: 'RESULT',
  error: 'ERROR',
  user: 'USER',
  system: 'SYSTEM',
}

function formatTime(iso: string): string {
  const d = new Date(iso)
  return d.toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false })
}

interface Props {
  log: AgentLogEntry[]
  streaming?: StreamingBuffers
}

export function AgentLog({ log, streaming }: Props) {
  const bottomRef = useRef<HTMLDivElement>(null)
  const prevSig = useRef('')

  const streamingEntries = streaming
    ? (Object.entries(streaming).filter(([, text]) => text && text.length > 0) as Array<
        [AgentLogSource, string]
      >)
    : []

  const streamSig = streamingEntries.map(([s, t]) => `${s}:${t.length}`).join('|')
  const sig = `${log.length}#${streamSig}`

  useEffect(() => {
    if (sig !== prevSig.current) {
      prevSig.current = sig
      bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
    }
  }, [sig])

  const isEmpty = log.length === 0 && streamingEntries.length === 0

  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center px-3 py-1.5 border-b border-surface-3 bg-surface-1 shrink-0">
        <span className="text-xs text-slate-500">{log.length} entries</span>
        {log.length > 0 && (
          <button
            className="ml-auto text-xs text-slate-500 hover:text-slate-300 transition-colors"
            onClick={() => {
              const text = log
                .map((e) => `[${e.timestamp}] ${sourceLabel[e.source]}: ${e.text}`)
                .join('\n')
              navigator.clipboard.writeText(text)
            }}
          >
            Copy all
          </button>
        )}
      </div>
      <div className="flex-1 overflow-y-auto font-mono text-xs">
        {isEmpty ? (
          <p className="text-slate-600 p-4">로그가 여기에 표시됩니다.</p>
        ) : (
          <>
            {log.map((entry) => (
              <div
                key={entry.id}
                className="flex gap-2 px-3 py-0.5 hover:bg-surface-2 transition-colors"
              >
                <span className={cx('shrink-0 w-16 font-semibold', sourceColor[entry.source])}>
                  {sourceLabel[entry.source]}
                </span>
                <span className="shrink-0 text-slate-600">{formatTime(entry.timestamp)}</span>
                <span className="text-slate-300 whitespace-pre-wrap break-words min-w-0">
                  {entry.text}
                </span>
              </div>
            ))}
            {streamingEntries.map(([source, text]) => (
              <div
                key={`stream-${source}`}
                className="flex gap-2 px-3 py-0.5 bg-surface-2/40"
              >
                <span className={cx('shrink-0 w-16 font-semibold', sourceColor[source])}>
                  {sourceLabel[source]}
                </span>
                <span className="shrink-0 text-slate-600">…</span>
                <span className="text-slate-300 whitespace-pre-wrap break-words min-w-0">
                  {text}
                  <span className="inline-block w-1.5 h-3 ml-0.5 align-middle bg-slate-400 animate-pulse" />
                </span>
              </div>
            ))}
          </>
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  )
}
