import React, { useState } from 'react'
import type { DiffFile, DiffLine } from '@shared/types'
import { cx } from '../lib/cx.js'

function DiffLineRow({ line }: { line: DiffLine }) {
  const cls = {
    addition: 'bg-emerald-950/40 text-emerald-200',
    deletion: 'bg-red-950/40 text-red-200',
    context: 'text-slate-400',
    meta: 'text-slate-500 italic',
  }[line.kind]

  const prefix = line.kind === 'addition' ? '+' : line.kind === 'deletion' ? '-' : ' '

  return (
    <div className={cx('flex font-mono text-xs leading-5 px-3 whitespace-pre', cls)}>
      <span className="select-none w-4 shrink-0 opacity-60">{prefix}</span>
      <span className="break-words min-w-0">{line.text}</span>
    </div>
  )
}

function DiffFileCard({ file }: { file: DiffFile }) {
  const [open, setOpen] = useState(true)

  return (
    <div className="border border-surface-3 rounded-md overflow-hidden mb-3">
      <button
        className="w-full flex items-center gap-3 px-3 py-2 bg-surface-2 hover:bg-surface-3 transition-colors text-left"
        onClick={() => setOpen((v) => !v)}
        type="button"
      >
        <span className="text-xs text-slate-500 select-none">{open ? '▾' : '▸'}</span>
        <span className="font-mono text-xs text-slate-200 truncate flex-1">{file.path}</span>
        <span className="text-xs text-emerald-400 shrink-0">+{file.additions}</span>
        <span className="text-xs text-red-400 shrink-0 ml-1">-{file.deletions}</span>
      </button>
      {open && (
        <div className="bg-surface-0 overflow-x-auto">
          {file.hunks.map((hunk, hi) => (
            <div key={hi}>
              <div className="px-3 py-0.5 font-mono text-xs text-slate-500 bg-surface-1 border-t border-surface-3">
                {hunk.header}
              </div>
              {hunk.lines.map((line, li) => (
                <DiffLineRow key={li} line={line} />
              ))}
            </div>
          ))}
          {file.hunks.length === 0 && (
            <p className="text-xs text-slate-600 px-3 py-2">변경 없음</p>
          )}
        </div>
      )}
    </div>
  )
}

interface Props {
  files: DiffFile[]
}

export function DiffView({ files }: Props) {
  if (files.length === 0) {
    return (
      <div className="flex items-center justify-center h-full text-slate-600 text-sm">
        변경사항 없음
      </div>
    )
  }

  return (
    <div className="h-full overflow-y-auto p-3">
      {files.map((f) => (
        <DiffFileCard key={f.path} file={f} />
      ))}
    </div>
  )
}
