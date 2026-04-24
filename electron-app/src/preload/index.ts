import { contextBridge, ipcRenderer } from 'electron'
import type {
  AppSettings,
  AgentState,
  Ticket,
  TicketComment,
  ClaudeVersionInfo,
  DiffFile,
  AgentStreamChunk,
  CommitResult,
  RunAgentPayload,
} from '@shared/types'

const api = {
  settings: {
    get: () => ipcRenderer.invoke('settings:get') as Promise<AppSettings>,
    set: (partial: Partial<AppSettings>) =>
      ipcRenderer.invoke('settings:set', partial) as Promise<AppSettings>,
  },
  secrets: {
    getToken: () => ipcRenderer.invoke('secrets:getToken') as Promise<string | null>,
    setToken: (token: string) => ipcRenderer.invoke('secrets:setToken', token) as Promise<void>,
    deleteToken: () => ipcRenderer.invoke('secrets:deleteToken') as Promise<void>,
  },
  notion: {
    verify: (databaseID: string) =>
      ipcRenderer.invoke('notion:verify', databaseID) as Promise<void>,
    fetchTickets: (version?: string) =>
      ipcRenderer.invoke('notion:fetchTickets', version) as Promise<Ticket[]>,
    fetchComments: (pageID: string) =>
      ipcRenderer.invoke('notion:fetchComments', pageID) as Promise<TicketComment[]>,
    fetchImages: (pageID: string) =>
      ipcRenderer.invoke('notion:fetchImages', pageID) as Promise<string[]>,
    patchStatus: (pageID: string, status: string) =>
      ipcRenderer.invoke('notion:patchStatus', pageID, status) as Promise<void>,
  },
  cli: {
    resolveBinary: () => ipcRenderer.invoke('cli:resolveBinary') as Promise<string | null>,
    probeVersion: () => ipcRenderer.invoke('cli:probeVersion') as Promise<ClaudeVersionInfo>,
  },
  mcp: {
    writeConfig: () => ipcRenderer.invoke('mcp:writeConfig') as Promise<string>,
  },
  git: {
    diff: (cwd: string) => ipcRenderer.invoke('git:diff', cwd) as Promise<string>,
    parseDiff: (text: string) => ipcRenderer.invoke('git:parseDiff', text) as Promise<DiffFile[]>,
  },
  fs: {
    pickDirectory: () => ipcRenderer.invoke('fs:pickDirectory') as Promise<string | null>,
  },
  agent: {
    start: (payload: RunAgentPayload) =>
      ipcRenderer.invoke('agent:start', payload) as Promise<void>,
    submitAnswer: (answer: string) =>
      ipcRenderer.invoke('agent:submitAnswer', answer) as Promise<void>,
    cancel: () => ipcRenderer.invoke('agent:cancel') as Promise<void>,
    commit: () => ipcRenderer.invoke('agent:commit') as Promise<CommitResult>,
    discardChanges: () => ipcRenderer.invoke('agent:discardChanges') as Promise<void>,
    getState: () => ipcRenderer.invoke('agent:getState') as Promise<AgentState>,
    onUpdate: (callback: (state: AgentState) => void) => {
      const listener = (_: Electron.IpcRendererEvent, state: AgentState) => callback(state)
      ipcRenderer.on('agent:update', listener)
      return () => ipcRenderer.removeListener('agent:update', listener)
    },
    onStreamChunk: (callback: (chunk: AgentStreamChunk) => void) => {
      const listener = (_: Electron.IpcRendererEvent, chunk: AgentStreamChunk) => callback(chunk)
      ipcRenderer.on('agent:streamChunk', listener)
      return () => ipcRenderer.removeListener('agent:streamChunk', listener)
    },
  },
}

contextBridge.exposeInMainWorld('api', api)

export type Api = typeof api
