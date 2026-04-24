export type Severity = 'Critical' | 'Major' | 'Minor' | 'Trivial' | '-'

export const severityRank: Record<Severity, number> = {
  Critical: 0,
  Major: 1,
  Minor: 2,
  Trivial: 3,
  '-': 4
}

export function severityCompare(a: Severity, b: Severity): number {
  return severityRank[a] - severityRank[b]
}

export function parseSeverity(raw: string | null | undefined): Severity {
  if (!raw) return '-'
  const known: Severity[] = ['Critical', 'Major', 'Minor', 'Trivial']
  return (known.find((s) => s === raw) ?? '-') as Severity
}

export interface TicketAttachment {
  id: string
  name: string
  url: string
}

export interface TicketComment {
  id: string
  author: string
  createdTime: string
  text: string
}

export interface Ticket {
  pageID: string
  displayID: string
  title: string
  severity: Severity
  status: string
  type: string
  reporter: string[]
  references: string[]
  assignees: string[]
  environment: string[]
  device: string
  appVerified: string
  issueCount: string
  notes: string
  reproduceSteps: string
  reproduceResult: string
  affectedVersion: string
  attachments: TicketAttachment[]
  versionTags: string[]
  createdTime?: string
  lastEditedTime?: string
  comments: TicketComment[]
}

export type AnthropicModel =
  | 'claude-opus-4-6'
  | 'claude-opus-4-7'
  | 'claude-sonnet-4-6'
  | 'claude-haiku-4-5-20251001'

export const anthropicModelDisplayName: Record<AnthropicModel, string> = {
  'claude-opus-4-6': 'Claude Opus 4.6 (default)',
  'claude-opus-4-7': 'Claude Opus 4.7',
  'claude-sonnet-4-6': 'Claude Sonnet 4.6',
  'claude-haiku-4-5-20251001': 'Claude Haiku 4.5'
}

export const allAnthropicModels: AnthropicModel[] = [
  'claude-opus-4-6',
  'claude-opus-4-7',
  'claude-sonnet-4-6',
  'claude-haiku-4-5-20251001'
]

export interface AppSettings {
  notionDatabaseID: string
  repositoryPath: string | null
  model: AnthropicModel
  maxBudgetUSD: number
}

export const defaultAppSettings: AppSettings = {
  notionDatabaseID: '',
  repositoryPath: null,
  model: 'claude-opus-4-6',
  maxBudgetUSD: 5.0
}

export type AgentPhase =
  | 'idle'
  | 'debugger'
  | 'verifier'
  | 'question'
  | 'finished'
  | 'failed'

export type AgentLogSource =
  | 'system'
  | 'debugger'
  | 'verifier'
  | 'toolUse'
  | 'toolResult'
  | 'error'
  | 'user'

export interface AgentLogEntry {
  id: string
  timestamp: string
  source: AgentLogSource
  text: string
}

export interface ClaudeUsage {
  inputTokens: number
  outputTokens: number
  cacheCreationInputTokens: number
  cacheReadInputTokens: number
  totalCostUSD?: number
  durationMS?: number
}

export type ClaudeStreamEvent =
  | { type: 'assistantText'; text: string }
  | { type: 'toolUse'; name: string; input: string }
  | { type: 'toolResult'; text: string }
  | { type: 'result'; usage: ClaudeUsage; text?: string }
  | { type: 'system'; subtype: string; raw: string }
  | { type: 'rateLimit'; raw: string }
  | { type: 'error'; message: string }
  | { type: 'unknown'; rawJSON: string }

export type DiffLineKind = 'addition' | 'deletion' | 'context' | 'meta'

export interface DiffLine {
  kind: DiffLineKind
  text: string
}

export interface DiffHunk {
  header: string
  lines: DiffLine[]
}

export interface DiffFile {
  path: string
  hunks: DiffHunk[]
  additions: number
  deletions: number
}

export interface AgentState {
  phase: AgentPhase
  log: AgentLogEntry[]
  cumulativeCost: number
  cumulativeInputTokens: number
  cumulativeOutputTokens: number
  lastDebuggerOutput: string
  lastVerifierOutput: string
  lastError: string | null
  refixCount: number
  maxRefix: number
  ticket: Ticket | null
  repoPath: string | null
  diff: string
  commitSHA: string | null
}

export const emptyAgentState: AgentState = {
  phase: 'idle',
  log: [],
  cumulativeCost: 0,
  cumulativeInputTokens: 0,
  cumulativeOutputTokens: 0,
  lastDebuggerOutput: '',
  lastVerifierOutput: '',
  lastError: null,
  refixCount: 0,
  maxRefix: 3,
  ticket: null,
  repoPath: null,
  diff: '',
  commitSHA: null
}

export interface ClaudeVersionInfo {
  raw: string
  major: number
  minor: number
  patch: number
  isSupported: boolean
}

export interface AgentStreamChunk {
  source: AgentLogSource
  text: string
}

export interface CommitResult {
  ok: boolean
  sha?: string
  subject?: string
  reason?: string
  raw: string
}

export interface RunAgentPayload {
  ticket: Ticket
  repoPath: string
}
