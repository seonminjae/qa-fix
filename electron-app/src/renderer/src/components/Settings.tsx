import React, { useEffect, useState } from 'react'
import type { AppSettings, AnthropicModel, Platform } from '@shared/types'
import {
  allAnthropicModels,
  allPlatforms,
  anthropicModelDisplayName,
  defaultAppSettings,
  platformDisplayName,
} from '@shared/types'
import { cx } from '../lib/cx.js'

const inputCls =
  'bg-surface-2 border border-surface-3 rounded px-3 py-1.5 text-sm focus:border-blue-500 outline-none w-full'
const btnPrimary =
  'bg-blue-600 hover:bg-blue-500 text-white rounded px-3 py-1.5 text-sm transition-colors whitespace-nowrap shrink-0'
const btnSecondary =
  'bg-surface-2 hover:bg-surface-3 text-slate-200 rounded px-3 py-1.5 text-sm border border-surface-3 transition-colors whitespace-nowrap shrink-0'

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="mb-6">
      <h2 className="text-xs font-semibold uppercase tracking-widest text-slate-500 mb-2">{title}</h2>
      <div className="bg-surface-1 border border-surface-3 rounded-md p-4 flex flex-col gap-4">
        {children}
      </div>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <label className="text-xs text-slate-400">{label}</label>
      {children}
    </div>
  )
}

function StatusText({ text, isOk }: { text: string; isOk?: boolean }) {
  return (
    <p
      className={cx(
        'text-xs mt-1',
        isOk === true && 'text-emerald-400',
        isOk === false && 'text-red-400',
        isOk === undefined && 'text-slate-400'
      )}
    >
      {text}
    </p>
  )
}

export function Settings() {
  const [settings, setSettings] = useState<AppSettings>(defaultAppSettings)
  const [token, setToken] = useState('')
  const [tokenMasked, setTokenMasked] = useState(true)

  const [verifyMsg, setVerifyMsg] = useState<{ text: string; ok: boolean } | null>(null)
  const [verifying, setVerifying] = useState(false)

  const [cliStatus, setCliStatus] = useState<{ path: string | null; version: string | null; ok: boolean } | null>(null)
  const [detectingCli, setDetectingCli] = useState(false)

  const [mcpPath, setMcpPath] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [saveMsg, setSaveMsg] = useState('')

  useEffect(() => {
    window.api.settings.get().then(setSettings)
    window.api.secrets.getToken().then((t) => {
      if (t) setToken(t)
    })
  }, [])

  async function handleSaveToken() {
    setSaving(true)
    try {
      await window.api.secrets.setToken(token)
      setSaveMsg('토큰 저장됨')
    } finally {
      setSaving(false)
      setTimeout(() => setSaveMsg(''), 2000)
    }
  }

  async function handleVerify() {
    setVerifying(true)
    setVerifyMsg(null)
    try {
      await window.api.notion.verify(settings.notionDatabaseID)
      setVerifyMsg({ text: '연결 성공', ok: true })
    } catch (e: unknown) {
      setVerifyMsg({ text: String(e instanceof Error ? e.message : e), ok: false })
    } finally {
      setVerifying(false)
    }
  }

  async function handlePickDirectory() {
    const path = await window.api.fs.pickDirectory()
    if (path) {
      const next = { ...settings, repositoryPath: path }
      setSettings(next)
      await window.api.settings.set({ repositoryPath: path })
    }
  }

  async function handleDetectCli() {
    setDetectingCli(true)
    setCliStatus(null)
    try {
      const [path, info] = await Promise.all([
        window.api.cli.resolveBinary(),
        window.api.cli.probeVersion(),
      ])
      setCliStatus({
        path,
        version: info ? info.raw : null,
        ok: info ? info.isSupported : false,
      })
    } finally {
      setDetectingCli(false)
    }
  }

  async function handleWriteMcp() {
    try {
      const path = await window.api.mcp.writeConfig()
      setMcpPath(path)
    } catch (e: unknown) {
      setMcpPath(String(e instanceof Error ? e.message : e))
    }
  }

  async function updateSetting(partial: Partial<AppSettings>) {
    const next = { ...settings, ...partial }
    setSettings(next)
    await window.api.settings.set(partial)
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="max-w-2xl mx-auto px-6 py-6">

        <Section title="Notion">
          <Field label="Integration Token">
            <div className="flex gap-2">
              <input
                type={tokenMasked ? 'password' : 'text'}
                className={inputCls}
                value={token}
                placeholder="secret_xxxxxxxx"
                onChange={(e) => setToken(e.target.value)}
              />
              <button
                className={btnSecondary}
                onClick={() => setTokenMasked((v) => !v)}
                type="button"
              >
                {tokenMasked ? '표시' : '숨김'}
              </button>
              <button
                className={btnPrimary}
                onClick={handleSaveToken}
                disabled={saving}
                type="button"
              >
                저장
              </button>
            </div>
            {saveMsg && <StatusText text={saveMsg} isOk />}
          </Field>

          <Field label="Database ID">
            <div className="flex gap-2">
              <input
                type="text"
                className={inputCls}
                value={settings.notionDatabaseID}
                placeholder="32자리 UUID"
                onChange={(e) => updateSetting({ notionDatabaseID: e.target.value })}
              />
              <button
                className={btnSecondary}
                onClick={handleVerify}
                disabled={verifying}
                type="button"
              >
                {verifying ? '확인 중…' : 'Verify'}
              </button>
            </div>
            {verifyMsg && <StatusText text={verifyMsg.text} isOk={verifyMsg.ok} />}
          </Field>

          <Field label="MCP Config">
            <button className={btnSecondary} onClick={handleWriteMcp} type="button">
              Write MCP Config
            </button>
            {mcpPath && (
              <p className="text-xs text-slate-400 font-mono mt-1 break-all">{mcpPath}</p>
            )}
          </Field>
        </Section>

        <Section title="Platform">
          <p className="text-xs text-slate-500">
            조회할 환경을 선택하세요. 티켓의 <code className="bg-surface-2 px-1 rounded">환경</code> 속성과 겹치는 항목만 노출됩니다. 아무것도 선택하지 않으면 전체 티켓이 조회됩니다.
          </p>
          <div className="flex flex-wrap gap-x-5 gap-y-2">
            {allPlatforms.map((p) => {
              const checked = settings.platforms.includes(p)
              return (
                <label key={p} className="flex items-center gap-2 cursor-pointer select-none">
                  <input
                    type="checkbox"
                    className="w-4 h-4 accent-blue-500"
                    checked={checked}
                    onChange={(e) => {
                      const next = e.target.checked
                        ? [...settings.platforms, p]
                        : settings.platforms.filter((x) => x !== p)
                      updateSetting({ platforms: next as Platform[] })
                    }}
                  />
                  <span className="text-sm text-slate-200">{platformDisplayName[p]}</span>
                </label>
              )
            })}
          </div>
        </Section>

        <Section title="Repository">
          <Field label="iOS 저장소 경로">
            <div className="flex gap-2">
              <input
                type="text"
                className={cx(inputCls, 'text-slate-400')}
                value={settings.repositoryPath ?? '(선택 안 됨)'}
                readOnly
              />
              <button className={btnSecondary} onClick={handlePickDirectory} type="button">
                선택…
              </button>
            </div>
          </Field>
        </Section>

        <Section title="Claude Code CLI">
          <Field label="Binary">
            <button
              className={btnSecondary}
              onClick={handleDetectCli}
              disabled={detectingCli}
              type="button"
            >
              {detectingCli ? '감지 중…' : 'Detect'}
            </button>
            {cliStatus && (
              <div className="mt-1 space-y-0.5">
                {cliStatus.path && (
                  <p className="text-xs font-mono text-slate-400 break-all">{cliStatus.path}</p>
                )}
                {cliStatus.version && (
                  <StatusText
                    text={`버전: ${cliStatus.version}${cliStatus.ok ? ' ✓' : ' — 2.1.0+ 필요'}`}
                    isOk={cliStatus.ok}
                  />
                )}
                {!cliStatus.path && !cliStatus.version && (
                  <StatusText text="claude 바이너리를 찾을 수 없습니다" isOk={false} />
                )}
              </div>
            )}
          </Field>
          <p className="text-xs text-slate-500">
            Terminal에서 <code className="bg-surface-2 px-1 rounded">claude</code> 실행 후{' '}
            <code className="bg-surface-2 px-1 rounded">/login</code> 하면 Claude Max OAuth가
            Keychain에 저장되어 subprocess에서도 재사용됩니다.
          </p>
        </Section>

        <Section title="Agent">
          <Field label="Model">
            <select
              className={inputCls}
              value={settings.model}
              onChange={(e) => updateSetting({ model: e.target.value as AnthropicModel })}
            >
              {allAnthropicModels.map((m) => (
                <option key={m} value={m}>
                  {anthropicModelDisplayName[m]}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Max Budget (USD)">
            <input
              type="number"
              className={cx(inputCls, 'max-w-[160px]')}
              value={settings.maxBudgetUSD}
              step={0.5}
              min={0.1}
              onChange={(e) => updateSetting({ maxBudgetUSD: parseFloat(e.target.value) || 0.1 })}
            />
          </Field>
        </Section>

      </div>
    </div>
  )
}
