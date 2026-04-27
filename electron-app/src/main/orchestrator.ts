import { EventEmitter } from 'node:events'
import { randomUUID } from 'node:crypto'
import { existsSync } from 'node:fs'
import type {
  AgentState,
  AgentLogSource,
  AgentLogEntry,
  Ticket,
  AppSettings,
  CommitResult,
  ClaudeStreamEvent,
} from '@shared/types'
import { emptyAgentState } from '@shared/types'
import { ClaudeCodeCLIClient, type ClaudeInvocation } from './claudeCli.js'
import * as git from './git.js'
import { configFileURL, writeNotionConfig } from './mcp.js'
import {
  debuggerSystemPrompt,
  verifierSystemPrompt,
  debuggerUserPrompt,
  verifierUserPrompt,
  commitSystemPrompt,
} from './prompts.js'
import { getNotionToken } from './settings.js'
import * as notion from './notion.js'

export interface OrchestratorEvents {
  update: (state: AgentState) => void
  streamChunk: (chunk: { source: AgentLogSource; text: string }) => void
}

export class AgentOrchestrator extends EventEmitter {
  private state: AgentState = { ...emptyAgentState, log: [] }
  private currentCancel?: () => void
  private savedSettings?: AppSettings

  getState(): AgentState {
    return { ...this.state, log: [...this.state.log] }
  }

  append(source: AgentLogSource, text: string): void {
    const entry: AgentLogEntry = {
      id: randomUUID(),
      timestamp: new Date().toISOString(),
      source,
      text,
    }
    this.state.log.push(entry)
    this.emit('update', this.getState())
  }

  private setPhase(phase: AgentState['phase']): void {
    this.state.phase = phase
    this.emit('update', this.getState())
  }

  async run(ticket: Ticket, repoPath: string, settings: AppSettings): Promise<void> {
    this.savedSettings = settings
    this.state = {
      ...emptyAgentState,
      log: [],
      ticket,
      repoPath,
    }
    this.emit('update', this.getState())

    try {
      await git.stashPush(`qafix-${ticket.pageID}`, repoPath)
    } catch (err) {
      this.append('system', `stash 실패: ${String(err)}`)
    }

    await this.runDebugger(null, settings)
  }

  async submitAnswer(answer: string, settings: AppSettings): Promise<void> {
    this.savedSettings = settings
    this.append('user', answer)
    await this.runDebugger(`유저 응답:\n${answer}`, settings)
  }

  cancel(): void {
    this.currentCancel?.()
    this.currentCancel = undefined
    this.state.phase = 'idle'
    this.emit('update', this.getState())
  }

  async commit(settings: AppSettings): Promise<CommitResult> {
    const repoPath = this.state.repoPath ?? ''
    let mcpConfigPath: string | undefined
    try {
      const token = await getNotionToken()
      if (token) mcpConfigPath = await writeNotionConfig(token)
    } catch {
      // non-fatal
    }

    const invocation: ClaudeInvocation = {
      prompt:
        '현재 스테이지되지 않은 변경을 스테이지하고 커밋 메시지와 함께 커밋을 수행하세요. P0 리뷰 가이드를 따르세요.',
      systemPrompt: commitSystemPrompt(),
      model: settings.model,
      workingDirectory: repoPath,
      mcpConfigPath,
      maxBudgetUSD: settings.maxBudgetUSD,
    }

    const result = await this.consume(invocation, 'system')

    const raw = result.text

    const okMatch = /\[COMMIT OK\]\s*(\S+)\s+(.+)/.exec(raw)
    const blockedMatch = /\[COMMIT BLOCKED\]\s*(.+)/.exec(raw)

    if (okMatch) {
      const sha = okMatch[1] ?? ''
      const subject = (okMatch[2] ?? '').trim()
      this.state.commitSHA = sha
      this.emit('update', this.getState())

      try {
        const token = await getNotionToken()
        if (token && this.state.ticket) {
          await notion.patchStatus(this.state.ticket.pageID, 'In progress', token)
        }
      } catch (err) {
        this.append('error', `Notion patchStatus 실패: ${String(err)}`)
      }

      return { ok: true, sha, subject, raw }
    }

    if (blockedMatch) {
      return { ok: false, reason: (blockedMatch[1] ?? '').trim(), raw }
    }

    return { ok: false, reason: 'Commit output did not contain [COMMIT OK] or [COMMIT BLOCKED]', raw }
  }

  async discardChanges(): Promise<void> {
    const repoPath = this.state.repoPath ?? ''
    try {
      await git.checkoutAll(repoPath)
    } catch (err) {
      this.append('error', `checkout 실패: ${String(err)}`)
    }
    try {
      await git.stashPop(repoPath)
    } catch (err) {
      this.append('system', `stashPop 실패: ${String(err)}`)
    }
    this.state = { ...emptyAgentState, log: [] }
    this.emit('update', this.getState())
  }

  private async runDebugger(previousFeedback: string | null, settings: AppSettings): Promise<void> {
    this.state.phase = 'debugger'
    this.state.lastDebuggerOutput = ''
    this.emit('update', this.getState())

    const ticket = this.state.ticket
    if (!ticket) {
      this.state.phase = 'failed'
      this.state.lastError = 'No ticket set'
      this.emit('update', this.getState())
      return
    }

    const repoPath = this.state.repoPath ?? ''
    let mcpConfigPath: string | undefined
    const mcpFile = configFileURL()
    if (existsSync(mcpFile)) mcpConfigPath = mcpFile

    const invocation: ClaudeInvocation = {
      prompt: debuggerUserPrompt(ticket, previousFeedback ?? undefined),
      systemPrompt: debuggerSystemPrompt,
      model: settings.model,
      workingDirectory: repoPath,
      mcpConfigPath,
      maxBudgetUSD: settings.maxBudgetUSD,
    }

    const result = await this.consume(invocation, 'debugger')
    this.state.lastDebuggerOutput = result.text

    if (!result.success) {
      const msg = result.message ?? result.text
      this.state.lastError = msg
      this.append('error', msg)
      this.setPhase('failed')
      return
    }

    const outcome = parseDebugger(result.text)
    if (outcome === 'question') {
      this.setPhase('question')
    } else if (outcome === 'fixed') {
      await this.runVerifier(settings)
    } else {
      const msg = `Debugger did not produce a terminal keyword: ${result.text.slice(0, 200)}`
      this.state.lastError = msg
      this.setPhase('failed')
    }
  }

  private async runVerifier(settings: AppSettings): Promise<void> {
    this.state.phase = 'verifier'
    this.state.lastVerifierOutput = ''
    this.emit('update', this.getState())

    const ticket = this.state.ticket
    const repoPath = this.state.repoPath ?? ''

    let gitDiff: string
    try {
      gitDiff = await git.diff(repoPath)
    } catch {
      gitDiff = '(git diff 실행 실패)'
    }

    this.state.diff = gitDiff
    this.emit('update', this.getState())

    let mcpConfigPath: string | undefined
    const mcpFile = configFileURL()
    if (existsSync(mcpFile)) mcpConfigPath = mcpFile

    const invocation: ClaudeInvocation = {
      prompt: verifierUserPrompt(ticket!, this.state.lastDebuggerOutput, gitDiff),
      systemPrompt: verifierSystemPrompt,
      model: settings.model,
      workingDirectory: repoPath,
      mcpConfigPath,
      maxBudgetUSD: settings.maxBudgetUSD,
    }

    const result = await this.consume(invocation, 'verifier')
    this.state.lastVerifierOutput = result.text

    if (!result.success) {
      const msg = result.message ?? result.text
      this.state.lastError = msg
      this.setPhase('failed')
      return
    }

    const outcome = parseVerifier(result.text)
    if (outcome === 'pass') {
      this.setPhase('finished')
    } else if (outcome === 'refix') {
      if (this.state.refixCount < this.state.maxRefix) {
        this.state.refixCount++
        this.emit('update', this.getState())
        await this.runDebugger(result.text, settings)
      } else {
        this.append('system', `재수정 루프가 최대 ${this.state.maxRefix}회에 도달했습니다.`)
        this.setPhase('finished')
      }
    } else {
      const msg = `Verifier did not produce a terminal keyword: ${result.text.slice(0, 200)}`
      this.state.lastError = msg
      this.setPhase('failed')
    }
  }

  private async consume(
    invocation: ClaudeInvocation,
    source: AgentLogSource,
  ): Promise<{ success: boolean; text: string; message?: string }> {
    let accumulated = ''
    let streamBuf = ''
    let errorMessage: string | undefined

    const flushStream = (): void => {
      if (!streamBuf) return
      this.append(source, streamBuf)
      streamBuf = ''
    }

    const cli = new ClaudeCodeCLIClient()

    const onEvent = (event: ClaudeStreamEvent): void => {
      switch (event.type) {
        case 'assistantText':
          accumulated += event.text
          streamBuf += event.text
          this.emit('streamChunk', { source, text: event.text })
          break
        case 'toolUse':
          flushStream()
          this.append('toolUse', `${event.name} ${event.input.slice(0, 200)}`)
          break
        case 'toolResult':
          flushStream()
          this.append('toolResult', event.text.slice(0, 500))
          break
        case 'result':
          flushStream()
          this.state.cumulativeCost += event.usage.totalCostUSD ?? 0
          this.state.cumulativeInputTokens += event.usage.inputTokens
          this.state.cumulativeOutputTokens += event.usage.outputTokens
          if (event.usage.totalCostUSD != null) {
            this.append(
              'system',
              `result cost=$${event.usage.totalCostUSD.toFixed(4)} input=${event.usage.inputTokens} output=${event.usage.outputTokens}`,
            )
          }
          break
        case 'error':
          flushStream()
          errorMessage = event.message
          break
        case 'rateLimit':
          flushStream()
          this.append('system', 'rate-limit event received')
          break
        case 'system':
        case 'unknown':
          break
      }
    }

    const handle = cli.runAgent(invocation, onEvent, (_stderr) => {})
    this.currentCancel = () => cli.cancel()

    try {
      await handle
      this.currentCancel = undefined
      flushStream()

      if (errorMessage !== undefined) {
        return { success: false, text: accumulated, message: errorMessage }
      }
      return { success: true, text: accumulated }
    } catch (err) {
      this.currentCancel = undefined
      flushStream()
      const message = err instanceof Error ? err.message : String(err)
      return { success: false, text: accumulated, message }
    }
  }
}

function leadingNonEmptyLines(text: string, limit: number): string[] {
  const out: string[] = []
  for (const raw of text.split('\n')) {
    const t = raw.trim()
    if (!t) continue
    out.push(t)
    if (out.length >= limit) break
  }
  return out
}

function parseDebugger(text: string): 'question' | 'fixed' | 'inconclusive' {
  const head = leadingNonEmptyLines(text, 5)
  if (head.some((l) => l.includes('[질문 필요]'))) return 'question'
  if (head.some((l) => l.includes('[수정 완료]'))) return 'fixed'
  return 'inconclusive'
}

function parseVerifier(text: string): 'pass' | 'refix' | 'inconclusive' {
  const head = leadingNonEmptyLines(text, 5)
  if (head.some((l) => l.includes('[통과]'))) return 'pass'
  if (head.some((l) => l.includes('[재수정 필요]'))) return 'refix'
  return 'inconclusive'
}

export const orchestrator = new AgentOrchestrator()
