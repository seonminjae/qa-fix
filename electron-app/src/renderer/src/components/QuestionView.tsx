import React, { useState } from 'react'

interface Props {
  questionText: string
  onSubmit: (answer: string) => void
  onCancel: () => void
}

export function QuestionView({ questionText, onSubmit, onCancel }: Props) {
  const [answer, setAnswer] = useState('')

  function handleSubmit() {
    if (!answer.trim()) return
    onSubmit(answer.trim())
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50">
      <div className="bg-surface-1 border border-surface-3 rounded-lg w-full max-w-lg mx-4 shadow-2xl">
        <div className="px-5 pt-5 pb-4">
          <h3 className="text-sm font-semibold text-slate-200 mb-3">에이전트 질문</h3>
          <pre className="text-sm text-slate-300 whitespace-pre-wrap bg-surface-2 rounded p-3 mb-4 max-h-60 overflow-y-auto font-sans leading-relaxed">
            {questionText}
          </pre>
          <textarea
            className="w-full bg-surface-2 border border-surface-3 rounded px-3 py-2 text-sm text-slate-200 focus:border-blue-500 outline-none resize-none"
            rows={4}
            placeholder="답변을 입력하세요…"
            value={answer}
            onChange={(e) => setAnswer(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) handleSubmit()
            }}
            autoFocus
          />
          <p className="text-xs text-slate-600 mt-1">⌘↵ 로 제출</p>
        </div>
        <div className="flex justify-end gap-2 px-5 pb-4">
          <button
            className="bg-surface-2 hover:bg-surface-3 text-slate-200 rounded px-3 py-1.5 text-sm border border-surface-3 transition-colors"
            onClick={onCancel}
            type="button"
          >
            Cancel
          </button>
          <button
            className="bg-blue-600 hover:bg-blue-500 text-white rounded px-3 py-1.5 text-sm transition-colors disabled:opacity-40"
            onClick={handleSubmit}
            disabled={!answer.trim()}
            type="button"
          >
            Submit
          </button>
        </div>
      </div>
    </div>
  )
}
