import { mkdirSync, writeFileSync, renameSync } from 'node:fs'
import { join } from 'node:path'
import { homedir, tmpdir } from 'node:os'
import { randomBytes } from 'node:crypto'

const APP_SUPPORT_DIR = join(homedir(), 'Library/Application Support/QAFixMac')
const MCP_CONFIG_FILE = 'mcp.json'

export function configFileURL(): string {
  mkdirSync(APP_SUPPORT_DIR, { recursive: true })
  return join(APP_SUPPORT_DIR, MCP_CONFIG_FILE)
}

export async function writeNotionConfig(token: string): Promise<string> {
  const filePath = configFileURL()
  const headersValue = `{"Authorization": "Bearer ${token}", "Notion-Version": "2022-06-28"}`
  const config = {
    mcpServers: {
      notion: {
        command: 'npx',
        args: ['-y', '@notionhq/notion-mcp-server'],
        env: {
          OPENAPI_MCP_HEADERS: headersValue,
        },
      },
    },
  }
  const content = JSON.stringify(config, null, 2)
  // Atomic write: write to temp file then rename
  const tmp = join(tmpdir(), `mcp-${randomBytes(6).toString('hex')}.json`)
  writeFileSync(tmp, content, 'utf8')
  renameSync(tmp, filePath)
  return filePath
}
