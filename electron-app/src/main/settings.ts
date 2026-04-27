import ElectronStore from 'electron-store'
import type { AppSettings, AnthropicModel, Platform } from '@shared/types'
import { allPlatforms, defaultAppSettings } from '@shared/types'

interface StoreSchema {
  notionDatabaseID: string
  repositoryPath: string | null
  model: AnthropicModel
  maxBudgetUSD: number
  platforms: Platform[]
}

const store = new ElectronStore<StoreSchema>({
  name: 'settings',
  defaults: {
    notionDatabaseID: defaultAppSettings.notionDatabaseID,
    repositoryPath: defaultAppSettings.repositoryPath,
    model: defaultAppSettings.model,
    maxBudgetUSD: defaultAppSettings.maxBudgetUSD,
    platforms: defaultAppSettings.platforms,
  },
})

function sanitizePlatforms(raw: unknown): Platform[] {
  if (!Array.isArray(raw)) return []
  const valid = new Set<Platform>(allPlatforms)
  return raw.filter((p): p is Platform => typeof p === 'string' && valid.has(p as Platform))
}

export function getSettings(): AppSettings {
  return {
    notionDatabaseID: store.get('notionDatabaseID'),
    repositoryPath: store.get('repositoryPath') ?? null,
    model: store.get('model'),
    maxBudgetUSD: store.get('maxBudgetUSD'),
    platforms: sanitizePlatforms(store.get('platforms')),
  }
}

export function setSettings(partial: Partial<AppSettings>): AppSettings {
  if (partial.notionDatabaseID !== undefined) store.set('notionDatabaseID', partial.notionDatabaseID.trim())
  if (partial.repositoryPath !== undefined) store.set('repositoryPath', partial.repositoryPath ?? null)
  if (partial.model !== undefined) store.set('model', partial.model)
  if (partial.maxBudgetUSD !== undefined) store.set('maxBudgetUSD', partial.maxBudgetUSD)
  if (partial.platforms !== undefined) store.set('platforms', sanitizePlatforms(partial.platforms))
  return getSettings()
}

let _keytar: typeof import('keytar') | null = null
async function keytar(): Promise<typeof import('keytar')> {
  if (!_keytar) {
    const mod = (await import('keytar')) as typeof import('keytar') & {
      default?: typeof import('keytar')
    }
    _keytar = mod.default ?? mod
  }
  return _keytar
}

const KEYTAR_SERVICE = 'QAFixMac'
const KEYTAR_ACCOUNT = 'notionToken'

export async function getNotionToken(): Promise<string | null> {
  const kt = await keytar()
  const raw = await kt.getPassword(KEYTAR_SERVICE, KEYTAR_ACCOUNT)
  return raw ? raw.trim() : raw
}

export async function setNotionToken(token: string): Promise<void> {
  const kt = await keytar()
  await kt.setPassword(KEYTAR_SERVICE, KEYTAR_ACCOUNT, token.trim())
}

export async function deleteNotionToken(): Promise<void> {
  const kt = await keytar()
  await kt.deletePassword(KEYTAR_SERVICE, KEYTAR_ACCOUNT)
}
