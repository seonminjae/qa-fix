import React, { useEffect, useState } from 'react'
import type { Ticket, TicketComment } from '@shared/types'
import { severityCompare } from '@shared/types'
import { cx } from '../lib/cx.js'

const severityBg: Record<string, string> = {
  Critical: 'bg-severity-critical/20 text-severity-critical border-severity-critical/40',
  Major: 'bg-severity-major/20 text-severity-major border-severity-major/40',
  Minor: 'bg-severity-minor/20 text-severity-minor border-severity-minor/40',
  Trivial: 'bg-severity-trivial/20 text-severity-trivial border-severity-trivial/40',
  '-': 'bg-severity-unknown/20 text-severity-unknown border-severity-unknown/40',
}

function SeverityPill({ severity }: { severity: string }) {
  return (
    <span
      className={cx(
        'inline-flex items-center px-2 py-0.5 rounded text-xs font-medium border',
        severityBg[severity] ?? severityBg['-']
      )}
    >
      {severity}
    </span>
  )
}

function TicketRow({
  ticket,
  selected,
  active,
  onClick,
}: {
  ticket: Ticket
  selected: boolean
  active: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cx(
        'w-full text-left px-3 py-2.5 border-b border-surface-3 transition-colors',
        selected ? 'bg-surface-3' : 'hover:bg-surface-2'
      )}
    >
      <div className="flex items-center gap-2 mb-1">
        <SeverityPill severity={ticket.severity} />
        <span className="font-mono text-xs text-slate-500">{ticket.displayID}</span>
        {active && (
          <span className="ml-auto inline-flex items-center gap-1 text-[10px] text-blue-300">
            <span className="w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse" />
            진행 중
          </span>
        )}
      </div>
      <p className="text-sm text-slate-200 line-clamp-2 leading-snug">{ticket.title}</p>
    </button>
  )
}

function MetaRow({ label, value }: { label: string; value: string }) {
  if (!value || value === '-') return null
  return (
    <div className="flex gap-2 text-xs">
      <span className="text-slate-500 w-24 shrink-0">{label}</span>
      <span className="text-slate-300">{value}</span>
    </div>
  )
}

function TextBlock({ title, body }: { title: string; body: string }) {
  if (!body) return null
  return (
    <div>
      <h4 className="text-xs font-semibold text-slate-400 mb-1">{title}</h4>
      <pre className="text-xs text-slate-300 whitespace-pre-wrap bg-surface-2 rounded p-2.5 leading-relaxed">
        {body}
      </pre>
    </div>
  )
}

function CommentItem({ comment }: { comment: TicketComment }) {
  return (
    <div className="flex gap-3">
      <div className="w-6 h-6 rounded-full bg-surface-3 flex items-center justify-center text-xs text-slate-400 shrink-0">
        {comment.author.charAt(0).toUpperCase()}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-baseline gap-2 mb-0.5">
          <span className="text-xs font-medium text-slate-300">{comment.author}</span>
          <span className="text-xs text-slate-600">{comment.createdTime.slice(0, 10)}</span>
        </div>
        <pre className="text-xs text-slate-400 whitespace-pre-wrap leading-relaxed">{comment.text}</pre>
      </div>
    </div>
  )
}

interface Props {
  onStartSession: (ticket: Ticket, repoPath: string) => void
  onResumeSession: () => void
  activeTicketID: string | null
}

export function TicketList({ onStartSession, onResumeSession, activeTicketID }: Props) {
  const [allTickets, setAllTickets] = useState<Ticket[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [selectedVersion, setSelectedVersion] = useState<string>('')
  const [selectedID, setSelectedID] = useState<string | null>(null)
  const [loadingComments, setLoadingComments] = useState(false)
  const [repoPath, setRepoPath] = useState<string | null>(null)
  useEffect(() => {
    window.api.settings.get().then((s) => {
      setRepoPath(s.repositoryPath)
      refresh()
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  async function refresh() {
    setLoading(true)
    setError(null)
    try {
      const tickets = await window.api.notion.fetchTickets(selectedVersion || undefined)
      const sorted = [...tickets].sort((a, b) => severityCompare(a.severity, b.severity))
      setAllTickets(sorted)
    } catch (e: unknown) {
      setError(String(e instanceof Error ? e.message : e))
    } finally {
      setLoading(false)
    }
  }

  const versions = Array.from(
    new Set(allTickets.flatMap((t) => t.versionTags))
  ).sort()

  const displayed = selectedVersion
    ? allTickets.filter((t) => t.versionTags.includes(selectedVersion))
    : allTickets

  const selectedTicket = displayed.find((t) => t.pageID === selectedID) ?? null

  async function selectTicket(ticket: Ticket) {
    setSelectedID(ticket.pageID)
    if (ticket.comments.length === 0) {
      setLoadingComments(true)
      try {
        const comments = await window.api.notion.fetchComments(ticket.pageID)
        setAllTickets((prev) =>
          prev.map((t) => (t.pageID === ticket.pageID ? { ...t, comments } : t))
        )
      } finally {
        setLoadingComments(false)
      }
    }
  }

  const isSelectedActive =
    selectedTicket !== null && selectedTicket.pageID === activeTicketID

  function handleStart() {
    if (!selectedTicket || !repoPath) return
    if (isSelectedActive) {
      onResumeSession()
      return
    }
    onStartSession(selectedTicket, repoPath)
  }

  return (
    <div className="flex h-full">
      {/* Sidebar */}
      <div className="w-80 shrink-0 border-r border-surface-3 flex flex-col bg-surface-1">
        <div className="flex items-center gap-2 px-3 py-2 border-b border-surface-3 bg-surface-2 shrink-0">
          <select
            className="flex-1 bg-surface-1 border border-surface-3 rounded px-2 py-1 text-xs text-slate-200 outline-none focus:border-blue-500"
            value={selectedVersion}
            onChange={(e) => setSelectedVersion(e.target.value)}
          >
            <option value="">전체 버전</option>
            {versions.map((v) => (
              <option key={v} value={v}>{v}</option>
            ))}
          </select>
          <button
            className="text-xs text-slate-400 hover:text-slate-200 transition-colors px-2 py-1 rounded hover:bg-surface-3"
            onClick={refresh}
            disabled={loading}
            type="button"
          >
            {loading ? '…' : '↺'}
          </button>
        </div>

        {error && (
          <p className="text-xs text-red-400 px-3 py-2 border-b border-surface-3">{error}</p>
        )}

        <div className="flex-1 overflow-y-auto">
          {loading && displayed.length === 0 ? (
            <p className="text-xs text-slate-600 p-4">불러오는 중…</p>
          ) : displayed.length === 0 ? (
            <p className="text-xs text-slate-600 p-4">티켓 없음</p>
          ) : (
            displayed.map((t) => (
              <TicketRow
                key={t.pageID}
                ticket={t}
                selected={t.pageID === selectedID}
                active={t.pageID === activeTicketID}
                onClick={() => selectTicket(t)}
              />
            ))
          )}
        </div>
      </div>

      {/* Detail */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {!selectedTicket ? (
          <div className="flex-1 flex items-center justify-center text-slate-600 text-sm">
            티켓을 선택하세요
          </div>
        ) : (
          <>
            <div className="flex-1 overflow-y-auto px-6 py-5 space-y-5">
              {/* Header */}
              <div className="flex items-start gap-3">
                <SeverityPill severity={selectedTicket.severity} />
                <div className="flex-1 min-w-0">
                  <h1 className="text-base font-semibold text-slate-100 leading-snug">
                    {selectedTicket.title}
                  </h1>
                  <p className="text-xs font-mono text-slate-500 mt-0.5">{selectedTicket.displayID}</p>
                </div>
              </div>

              {/* Meta */}
              <div className="space-y-1.5 border-b border-surface-3 pb-4">
                <MetaRow label="상태" value={selectedTicket.status} />
                <MetaRow label="유형" value={selectedTicket.type} />
                <MetaRow label="보고자" value={selectedTicket.reporter.join(', ')} />
                <MetaRow label="담당자" value={selectedTicket.assignees.join(', ')} />
                <MetaRow label="디바이스" value={selectedTicket.device} />
                <MetaRow label="발생 버전" value={selectedTicket.affectedVersion} />
                <MetaRow label="확인 버전" value={selectedTicket.appVerified} />
                {selectedTicket.environment.length > 0 && (
                  <div className="flex gap-2 text-xs">
                    <span className="text-slate-500 w-24 shrink-0">환경</span>
                    <div className="flex flex-wrap gap-1">
                      {selectedTicket.environment.map((env) => (
                        <span key={env} className="bg-surface-3 rounded px-1.5 py-0.5 text-slate-300">
                          {env}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              <TextBlock title="재현 절차" body={selectedTicket.reproduceSteps} />
              <TextBlock title="재현 결과" body={selectedTicket.reproduceResult} />
              <TextBlock title="참고" body={selectedTicket.notes} />

              {selectedTicket.attachments.length > 0 && (
                <div>
                  <h4 className="text-xs font-semibold text-slate-400 mb-2">첨부 이미지</h4>
                  <div className="flex flex-wrap gap-2">
                    {selectedTicket.attachments.map((att) => (
                      <a
                        key={att.id}
                        href={att.url}
                        target="_blank"
                        rel="noreferrer"
                        className="block"
                      >
                        <img
                          src={att.url}
                          alt={att.name}
                          className="max-h-48 max-w-xs rounded border border-surface-3 object-contain bg-surface-2"
                        />
                      </a>
                    ))}
                  </div>
                </div>
              )}

              {/* Comments */}
              {(selectedTicket.comments.length > 0 || loadingComments) && (
                <div>
                  <h4 className="text-xs font-semibold text-slate-400 mb-3">QA 댓글</h4>
                  {loadingComments ? (
                    <p className="text-xs text-slate-600">불러오는 중…</p>
                  ) : (
                    <div className="space-y-4">
                      {selectedTicket.comments.map((c) => (
                        <CommentItem key={c.id} comment={c} />
                      ))}
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Bottom bar */}
            <div className="shrink-0 flex items-center gap-3 px-6 py-3 border-t border-surface-3 bg-surface-1">
              {!repoPath && (
                <p className="text-xs text-amber-400">
                  Settings 에서 저장소 지정 필요
                </p>
              )}
              <div className="ml-auto">
                <button
                  className={cx(
                    'rounded px-4 py-1.5 text-sm transition-colors disabled:opacity-40 disabled:cursor-not-allowed',
                    isSelectedActive
                      ? 'bg-emerald-600 hover:bg-emerald-500 text-white'
                      : 'bg-blue-600 hover:bg-blue-500 text-white'
                  )}
                  onClick={handleStart}
                  disabled={!repoPath && !isSelectedActive}
                  type="button"
                >
                  {isSelectedActive ? '진행 중인 세션 이어보기' : 'Start Fix Session'}
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
