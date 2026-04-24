import ElectronStore from 'electron-store'
import type { AppSettings, AnthropicModel } from '@shared/types'
import { defaultAppSettings } from '@shared/types'

interface StoreSchema {
  notionDatabaseID: string
  repositoryPath: string | null
  model: AnthropicModel
  maxBudgetUSD: number
}

const store = new ElectronStore<StoreSchema>({
  name: 'settings',
  defaults: {
    notionDatabaseID: defaultAppSettings.notionDatabaseID,
    repositoryPath: defaultAppSettings.repositoryPath,
    model: defaultAppSettings.model,
    maxBudgetUSD: defaultAppSettings.maxBudgetUSD,
  },
})

export function getSettings(): AppSettings {
  return {
    notionDatabaseID: store.get('notionDatabaseID'),
    repositoryPath: store.get('repositoryPath') ?? null,
    model: store.get('model'),
    maxBudgetUSD: store.get('maxBudgetUSD'),
  }
}

export function setSettings(partial: Partial<AppSettings>): AppSettings {
  if (partial.notionDatabaseID !== undefined) store.set('notionDatabaseID', partial.notionDatabaseID)
  if (partial.repositoryPath !== undefined) store.set('repositoryPath', partial.repositoryPath ?? null)
  if (partial.model !== undefined) store.set('model', partial.model)
  if (partial.maxBudgetUSD !== undefined) store.set('maxBudgetUSD', partial.maxBudgetUSD)
  return getSettings()
}

let _keytar: typeof import('keytar') | null = null
async function keytar(): Promise<typeof import('keytar')> {
  if (!_keytar) _keytar = await import('keytar')
  return _keytar
}

const KEYTAR_SERVICE = 'QAFixMac'
const KEYTAR_ACCOUNT = 'notionToken'

export async function getNotionToken(): Promise<string | null> {
  const kt = await keytar()
  return kt.getPassword(KEYTAR_SERVICE, KEYTAR_ACCOUNT)
}

export async function setNotionToken(token: string): Promise<void> {
  const kt = await keytar()
  await kt.setPassword(KEYTAR_SERVICE, KEYTAR_ACCOUNT, token)
}

export async function deleteNotionToken(): Promise<void> {
  const kt = await keytar()
  await kt.deletePassword(KEYTAR_SERVICE, KEYTAR_ACCOUNT)
}
