import { ipcMain, dialog, BrowserWindow } from 'electron'
import { orchestrator } from './orchestrator.js'
import { getSettings, setSettings, getNotionToken, setNotionToken, deleteNotionToken } from './settings.js'
import {
  verifyDatabase,
  fetchOpenedTickets,
  fetchComments,
  fetchImageBlocks,
  patchStatus,
} from './notion.js'
import { resolveBinary, probeVersion } from './claudeCli.js'
import { writeNotionConfig } from './mcp.js'
import * as git from './git.js'
import { parseUnifiedDiff } from './diffParser.js'
import type { AppSettings, RunAgentPayload } from '@shared/types'

export function registerIpcHandlers(window: BrowserWindow): void {
  orchestrator.on('update', (state) => {
    window.webContents.send('agent:update', state)
  })
  orchestrator.on('streamChunk', (chunk) => {
    window.webContents.send('agent:streamChunk', chunk)
  })

  // ---- Settings ----
  ipcMain.handle('settings:get', () => getSettings())

  ipcMain.handle('settings:set', (_e, partial: Partial<AppSettings>) => setSettings(partial))

  // ---- Secrets ----
  ipcMain.handle('secrets:getToken', () => getNotionToken())

  ipcMain.handle('secrets:setToken', (_e, token: string) => setNotionToken(token))

  ipcMain.handle('secrets:deleteToken', () => deleteNotionToken())

  // ---- Notion ----
  ipcMain.handle('notion:verify', async (_e, databaseID: string) => {
    const token = await getNotionToken()
    if (!token) throw new Error('Notion token not set')
    await verifyDatabase(databaseID, token)
  })

  ipcMain.handle('notion:fetchTickets', async (_e, version?: string) => {
    const settings = getSettings()
    const token = await getNotionToken()
    if (!token) throw new Error('Notion token not set')
    return fetchOpenedTickets(settings.notionDatabaseID, token, version, settings.platforms)
  })

  ipcMain.handle('notion:fetchComments', async (_e, pageID: string) => {
    const token = await getNotionToken()
    if (!token) throw new Error('Notion token not set')
    return fetchComments(pageID, token)
  })

  ipcMain.handle('notion:fetchImages', async (_e, pageID: string) => {
    const token = await getNotionToken()
    if (!token) throw new Error('Notion token not set')
    return fetchImageBlocks(pageID, token)
  })

  ipcMain.handle('notion:patchStatus', async (_e, pageID: string, status: string) => {
    const token = await getNotionToken()
    if (!token) throw new Error('Notion token not set')
    await patchStatus(pageID, status, token)
  })

  // ---- CLI ----
  ipcMain.handle('cli:resolveBinary', () => resolveBinary())

  ipcMain.handle('cli:probeVersion', async () => {
    const binary = resolveBinary()
    if (!binary) return null
    return probeVersion(binary)
  })

  // ---- MCP ----
  ipcMain.handle('mcp:writeConfig', async () => {
    const token = await getNotionToken()
    if (!token) throw new Error('Notion token not set')
    return writeNotionConfig(token)
  })

  // ---- Git ----
  ipcMain.handle('git:diff', (_e, cwd: string) => git.diff(cwd))

  ipcMain.handle('git:parseDiff', (_e, text: string) => parseUnifiedDiff(text))

  // ---- FS ----
  ipcMain.handle('fs:pickDirectory', async () => {
    const result = await dialog.showOpenDialog(window, { properties: ['openDirectory'] })
    return result.canceled ? null : (result.filePaths[0] ?? null)
  })

  // ---- Agent ----
  ipcMain.handle('agent:start', (_e, payload: RunAgentPayload) => {
    const settings = getSettings()
    orchestrator.run(payload.ticket, payload.repoPath, settings).catch((err) => {
      console.error('orchestrator.run error:', err)
    })
  })

  ipcMain.handle('agent:submitAnswer', (_e, answer: string) => {
    const settings = getSettings()
    orchestrator.submitAnswer(answer, settings).catch((err) => {
      console.error('orchestrator.submitAnswer error:', err)
    })
  })

  ipcMain.handle('agent:cancel', () => orchestrator.cancel())

  ipcMain.handle('agent:commit', async () => {
    const settings = getSettings()
    return orchestrator.commit(settings)
  })

  ipcMain.handle('agent:discardChanges', () => orchestrator.discardChanges())

  ipcMain.handle('agent:getState', () => orchestrator.getState())
}
