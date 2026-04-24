import type {
  AppSettings,
  AgentState,
  AgentStreamChunk,
  ClaudeVersionInfo,
  DiffFile,
  RunAgentPayload,
  Ticket,
  TicketComment,
  CommitResult,
} from '@shared/types'

declare global {
  interface Window {
    api: {
      settings: {
        get(): Promise<AppSettings>
        set(partial: Partial<AppSettings>): Promise<AppSettings>
      }
      secrets: {
        getToken(): Promise<string | null>
        setToken(token: string): Promise<void>
        deleteToken(): Promise<void>
      }
      notion: {
        verify(databaseID: string): Promise<void>
        fetchTickets(version?: string): Promise<Ticket[]>
        fetchComments(pageID: string): Promise<TicketComment[]>
        fetchImages(pageID: string): Promise<string[]>
        patchStatus(pageID: string, status: string): Promise<void>
      }
      cli: {
        resolveBinary(): Promise<string | null>
        probeVersion(): Promise<ClaudeVersionInfo>
      }
      mcp: {
        writeConfig(): Promise<string>
      }
      git: {
        diff(cwd: string): Promise<string>
        parseDiff(text: string): Promise<DiffFile[]>
      }
      fs: {
        pickDirectory(): Promise<string | null>
      }
      agent: {
        start(payload: RunAgentPayload): Promise<void>
        submitAnswer(answer: string): Promise<void>
        cancel(): Promise<void>
        commit(): Promise<CommitResult>
        discardChanges(): Promise<void>
        getState(): Promise<AgentState>
        onUpdate(callback: (state: AgentState) => void): () => void
        onStreamChunk(callback: (chunk: AgentStreamChunk) => void): () => void
      }
    }
  }
}

export {}
