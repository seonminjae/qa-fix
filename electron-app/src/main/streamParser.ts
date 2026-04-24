import type { ClaudeStreamEvent, ClaudeUsage } from '@shared/types'

export function parseLine(line: string): ClaudeStreamEvent {
  let json: Record<string, unknown>
  try {
    json = JSON.parse(line) as Record<string, unknown>
  } catch {
    return { type: 'unknown', rawJSON: line }
  }

  const type = json['type']
  if (typeof type !== 'string') return { type: 'unknown', rawJSON: line }

  switch (type) {
    case 'assistant': {
      const message = json['message'] as Record<string, unknown> | undefined
      const blocks = message?.['content'] as Array<Record<string, unknown>> | undefined
      if (!Array.isArray(blocks)) return { type: 'unknown', rawJSON: line }

      let accumulated = ''
      for (const block of blocks) {
        const blockType = block['type']
        if (blockType === 'tool_use') {
          const name = typeof block['name'] === 'string' ? block['name'] : '?'
          const input = block['input'] ?? {}
          return {
            type: 'toolUse',
            name,
            input: JSON.stringify(input, null, 2),
          }
        }
        if (blockType === 'text' && typeof block['text'] === 'string') {
          accumulated += block['text']
        }
      }
      if (accumulated) return { type: 'assistantText', text: accumulated }
      return { type: 'unknown', rawJSON: line }
    }

    case 'user': {
      const message = json['message'] as Record<string, unknown> | undefined
      const blocks = message?.['content'] as Array<Record<string, unknown>> | undefined
      if (!Array.isArray(blocks)) return { type: 'unknown', rawJSON: line }

      for (const block of blocks) {
        if (block['type'] !== 'tool_result') continue
        const content = block['content']
        if (Array.isArray(content)) {
          const text = (content as Array<Record<string, unknown>>)
            .map((c) => (typeof c['text'] === 'string' ? c['text'] : ''))
            .join('\n')
          return { type: 'toolResult', text }
        }
        if (typeof content === 'string') {
          return { type: 'toolResult', text: content }
        }
      }
      return { type: 'unknown', rawJSON: line }
    }

    case 'system': {
      const subtype = typeof json['subtype'] === 'string' ? json['subtype'] : ''
      return { type: 'system', subtype, raw: line }
    }

    case 'rate_limit_event':
      return { type: 'rateLimit', raw: line }

    case 'result': {
      const subtype = typeof json['subtype'] === 'string' ? json['subtype'] : ''
      if (subtype === 'error_during_execution' || subtype === 'error_max_turns') {
        const message =
          typeof json['result'] === 'string' ? json['result'] : 'Claude reported an error.'
        return { type: 'error', message }
      }

      const usageRaw = json['usage'] as Record<string, unknown> | undefined
      const usage: ClaudeUsage = {
        inputTokens: typeof usageRaw?.['input_tokens'] === 'number' ? usageRaw['input_tokens'] : 0,
        outputTokens:
          typeof usageRaw?.['output_tokens'] === 'number' ? usageRaw['output_tokens'] : 0,
        cacheCreationInputTokens:
          typeof usageRaw?.['cache_creation_input_tokens'] === 'number'
            ? usageRaw['cache_creation_input_tokens']
            : 0,
        cacheReadInputTokens:
          typeof usageRaw?.['cache_read_input_tokens'] === 'number'
            ? usageRaw['cache_read_input_tokens']
            : 0,
        totalCostUSD:
          typeof json['total_cost_usd'] === 'number' ? json['total_cost_usd'] : undefined,
        durationMS: typeof json['duration_ms'] === 'number' ? json['duration_ms'] : undefined,
      }
      const text = typeof json['result'] === 'string' ? json['result'] : undefined
      return { type: 'result', usage, text }
    }

    case 'error': {
      const errObj = json['error'] as Record<string, unknown> | undefined
      const message =
        (typeof errObj?.['message'] === 'string' ? errObj['message'] : undefined) ??
        (typeof json['message'] === 'string' ? json['message'] : undefined) ??
        'Claude reported an error.'
      return { type: 'error', message }
    }

    default:
      return { type: 'unknown', rawJSON: line }
  }
}

export class NDJSONLineBuffer {
  private buffer: Buffer = Buffer.alloc(0)

  append(chunk: Buffer | string): string[] {
    const bytes = typeof chunk === 'string' ? Buffer.from(chunk, 'utf8') : chunk
    this.buffer = Buffer.concat([this.buffer, bytes])
    const lines: string[] = []

    let idx: number
    while ((idx = this.buffer.indexOf(0x0a)) !== -1) {
      const lineBytes = this.buffer.subarray(0, idx)
      this.buffer = this.buffer.subarray(idx + 1)
      const text = lineBytes.toString('utf8')
      if (text) lines.push(text)
    }

    return lines
  }

  flush(): string | null {
    if (this.buffer.length === 0) return null
    const text = this.buffer.toString('utf8')
    this.buffer = Buffer.alloc(0)
    return text || null
  }
}
