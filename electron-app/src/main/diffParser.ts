import type { DiffFile, DiffHunk, DiffLine } from '@shared/types'

export function parseUnifiedDiff(text: string): DiffFile[] {
  const files: DiffFile[] = []
  let currentFile: string | null = null
  let currentHunks: DiffHunk[] = []
  let currentHunkHeader: string | null = null
  let currentHunkLines: DiffLine[] = []

  function flushHunk(): void {
    if (currentHunkHeader !== null) {
      currentHunks.push({ header: currentHunkHeader, lines: currentHunkLines })
    }
    currentHunkHeader = null
    currentHunkLines = []
  }

  function flushFile(): void {
    flushHunk()
    if (currentFile !== null) {
      const hunks = currentHunks
      const additions = hunks.reduce(
        (sum, h) => sum + h.lines.filter((l) => l.kind === 'addition').length,
        0,
      )
      const deletions = hunks.reduce(
        (sum, h) => sum + h.lines.filter((l) => l.kind === 'deletion').length,
        0,
      )
      files.push({ path: currentFile, hunks, additions, deletions })
    }
    currentFile = null
    currentHunks = []
  }

  for (const rawLine of text.split('\n')) {
    if (rawLine.startsWith('diff --git ')) {
      flushFile()
      const idx = rawLine.indexOf(' b/')
      if (idx !== -1) currentFile = rawLine.slice(idx + 3)
      continue
    }
    if (rawLine.startsWith('+++ ')) {
      const stripped = rawLine.slice(4)
      currentFile = stripped.startsWith('b/') ? stripped.slice(2) : stripped
      continue
    }
    if (rawLine.startsWith('--- ')) continue
    if (rawLine.startsWith('@@')) {
      flushHunk()
      currentHunkHeader = rawLine
      continue
    }
    if (rawLine.startsWith('+')) {
      currentHunkLines.push({ kind: 'addition', text: rawLine.slice(1) })
    } else if (rawLine.startsWith('-')) {
      currentHunkLines.push({ kind: 'deletion', text: rawLine.slice(1) })
    } else if (rawLine.startsWith(' ')) {
      currentHunkLines.push({ kind: 'context', text: rawLine.slice(1) })
    } else if (rawLine && currentHunkHeader !== null) {
      currentHunkLines.push({ kind: 'meta', text: rawLine })
    }
  }
  flushFile()
  return files
}
