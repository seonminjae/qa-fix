import {
  Ticket,
  TicketComment,
  TicketAttachment,
  Severity,
  severityCompare,
  Platform,
} from '@shared/types'
import { RetryPolicy, ConcurrencyLimiter, defaultRetryPolicy } from './retry'

const BASE_URL = 'https://api.notion.com/v1'
const NOTION_VERSION = '2022-06-28'

const limiter = new ConcurrencyLimiter(3)
const retryPolicy = defaultRetryPolicy

function makeHeaders(token: string): Record<string, string> {
  return {
    Authorization: `Bearer ${token}`,
    'Notion-Version': NOTION_VERSION,
    'Content-Type': 'application/json',
  }
}

async function performRequest(
  path: string,
  method: string,
  token: string,
  body?: unknown,
): Promise<unknown> {
  await limiter.acquire()
  try {
    const url = `${BASE_URL}/${path}`
    let lastError: Error | undefined

    for (let attempt = 1; attempt <= retryPolicy.maxAttempts; attempt++) {
      try {
        const res = await fetch(url, {
          method,
          headers: makeHeaders(token),
          body: body !== undefined ? JSON.stringify(body) : undefined,
        })

        if (res.ok) {
          return await res.json()
        }

        if (retryPolicy.shouldRetry(res.status) && attempt < retryPolicy.maxAttempts) {
          const retryAfterHeader = res.headers.get('Retry-After')
          const retryAfterSec = retryAfterHeader ? parseFloat(retryAfterHeader) : undefined
          const delaySec = retryPolicy.delay(attempt, retryAfterSec)
          await sleep(delaySec * 1000)
          continue
        }

        const text = await res.text().catch(() => '')
        throw new Error(`Notion HTTP ${res.status}: ${text.slice(0, 200)}`)
      } catch (err) {
        if (err instanceof Error && err.message.startsWith('Notion HTTP')) throw err
        lastError = err instanceof Error ? err : new Error(String(err))
        if (attempt < retryPolicy.maxAttempts) {
          await sleep(retryPolicy.delay(attempt) * 1000)
          continue
        }
        throw lastError
      }
    }

    throw lastError ?? new Error('Notion request failed after max attempts')
  } finally {
    limiter.release()
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

// --------------- Property extraction helpers ---------------

type RawProperties = Record<string, RawProperty>

interface RawProperty {
  type: string
  title?: Array<{ plain_text: string }>
  rich_text?: Array<{ plain_text: string }>
  select?: { name: string } | null
  multi_select?: Array<{ name: string }>
  people?: Array<{ name?: string }>
  unique_id?: { prefix?: string; number?: number }
  files?: Array<{
    name: string
    external?: { url: string }
    file?: { url: string }
  }>
}

function richTexts(prop: RawProperty | undefined): string[] {
  if (!prop) return []
  if (prop.type === 'title') return (prop.title ?? []).map((t) => t.plain_text)
  if (prop.type === 'rich_text') return (prop.rich_text ?? []).map((t) => t.plain_text)
  return []
}

function selectVal(prop: RawProperty | undefined): string | undefined {
  if (!prop || prop.type !== 'select') return undefined
  return prop.select?.name
}

function multiSelectVals(prop: RawProperty | undefined): string[] {
  if (!prop || prop.type !== 'multi_select') return []
  return (prop.multi_select ?? []).map((m) => m.name)
}

function peopleVals(prop: RawProperty | undefined): string[] {
  if (!prop || prop.type !== 'people') return []
  return (prop.people ?? []).flatMap((p) => (p.name ? [p.name] : []))
}

function buildTicket(page: RawPage): Ticket {
  const props = page.properties as RawProperties
  const p = (key: string) => props[key]

  const title = richTexts(p('Projects')).join('')
  const sev = parseSeverity(selectVal(p('위험도')))
  const status = selectVal(p('상태')) ?? '-'
  const type = selectVal(p('유형')) ?? '-'
  const reporter = peopleVals(p('보고자'))
  const references = peopleVals(p('참조'))
  const assignees = peopleVals(p('담당자'))

  const envProp = p('환경')
  const environment: string[] =
    envProp?.type === 'multi_select'
      ? multiSelectVals(envProp)
      : envProp?.type === 'select' && envProp.select?.name
        ? [envProp.select.name]
        : []

  const device = richTexts(p('확인 Device')).join('')
  const appVerified = richTexts(p('확인 버전 (App)')).join('')

  const issueCountProp = p('이슈 등록 차수')
  const issueCount =
    issueCountProp?.type === 'select'
      ? (selectVal(issueCountProp) ?? '')
      : richTexts(issueCountProp).join('')

  const notes = richTexts(p('참고')).join('')
  const reproduceSteps = richTexts(p('재현 절차')).join('')
  const reproduceResult = richTexts(p('재현 결과')).join('')
  const affectedVersion = richTexts(p('발생 버전 (App)')).join('')
  const versionTags = multiSelectVals(p('검증 프로젝트 태그'))

  const filesProp = p('첨부')
  const attachments: TicketAttachment[] =
    filesProp?.type === 'files'
      ? (filesProp.files ?? []).map((f, i) => ({
          id: `${page.id}-file-${i}`,
          name: f.name,
          url: f.external?.url ?? f.file?.url ?? '',
        }))
      : []

  const uniqueID = p('ID')?.unique_id
  let displayID: string
  if (uniqueID) {
    const prefix = uniqueID.prefix ? `${uniqueID.prefix}-` : ''
    const num = uniqueID.number !== undefined ? String(uniqueID.number) : '?'
    displayID = `${prefix}${num}`
  } else {
    displayID = page.id.slice(0, 8)
  }

  return {
    pageID: page.id,
    displayID,
    title: title || '(no title)',
    severity: sev,
    status,
    type,
    reporter,
    references,
    assignees,
    environment,
    device,
    appVerified,
    issueCount,
    notes,
    reproduceSteps,
    reproduceResult,
    affectedVersion,
    attachments,
    versionTags,
    createdTime: page.created_time,
    lastEditedTime: page.last_edited_time,
    comments: [],
  }
}

function parseSeverity(raw: string | undefined): Severity {
  if (raw === 'Critical' || raw === 'Major' || raw === 'Minor' || raw === 'Trivial') return raw
  return '-'
}

interface RawPage {
  id: string
  created_time?: string
  last_edited_time?: string
  properties: Record<string, unknown>
}

interface QueryResponse {
  results: RawPage[]
}

interface CommentsResponse {
  results: Array<{
    created_time: string
    rich_text: Array<{ plain_text: string }>
    display_name?: { resolved_name?: string }
    created_by?: { name?: string }
  }>
}

interface BlocksResponse {
  results: Array<{
    type: string
    image?: {
      type: string
      external?: { url: string }
      file?: { url: string }
    }
  }>
}

// --------------- Public API ---------------

export async function fetchOpenedTickets(
  databaseID: string,
  token: string,
  version?: string,
  platforms?: Platform[],
): Promise<Ticket[]> {
  const filters: unknown[] = [{ property: '상태', select: { equals: 'Opened' } }]
  if (version && version.trim()) {
    filters.push({ property: '검증 프로젝트 태그', multi_select: { contains: version } })
  }

  const data = (await performRequest(`databases/${databaseID}/query`, 'POST', token, {
    filter: { and: filters },
  })) as QueryResponse

  let tickets = data.results.map(buildTicket)

  if (platforms && platforms.length > 0) {
    const selected = new Set<string>(platforms)
    tickets = tickets.filter((t) => t.environment.some((env) => selected.has(env)))
  }

  tickets.sort((a, b) => severityCompare(a.severity, b.severity))
  return tickets
}

export async function fetchComments(pageID: string, token: string): Promise<TicketComment[]> {
  const data = (await performRequest(
    `comments?block_id=${pageID}`,
    'GET',
    token,
  )) as CommentsResponse

  return data.results.map((c, i) => ({
    id: `${pageID}-comment-${i}`,
    author: c.display_name?.resolved_name ?? c.created_by?.name ?? 'unknown',
    createdTime: c.created_time,
    text: c.rich_text.map((r) => r.plain_text).join(''),
  }))
}

export async function fetchImageBlocks(pageID: string, token: string): Promise<string[]> {
  const data = (await performRequest(
    `blocks/${pageID}/children?page_size=50`,
    'GET',
    token,
  )) as BlocksResponse

  return data.results
    .filter((b) => b.type === 'image')
    .flatMap((b) => {
      const url = b.image?.external?.url ?? b.image?.file?.url
      return url ? [url] : []
    })
}

export async function verifyDatabase(databaseID: string, token: string): Promise<void> {
  await performRequest(`databases/${databaseID}`, 'GET', token)
}

export async function patchStatus(
  pageID: string,
  statusName: string,
  token: string,
): Promise<void> {
  await performRequest(`pages/${pageID}`, 'PATCH', token, {
    properties: { 상태: { select: { name: statusName } } },
  })
}
