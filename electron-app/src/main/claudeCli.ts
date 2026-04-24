import { spawn, execFileSync } from 'node:child_process'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'
import { existsSync } from 'node:fs'
import type { ClaudeStreamEvent, ClaudeVersionInfo } from '@shared/types'
import { NDJSONLineBuffer, parseLine } from './streamParser'

const CANDIDATE_PATHS = [
  '/opt/homebrew/bin/claude',
  '/usr/local/bin/claude',
  join(homedir(), '.nvm/current/bin/claude'),
]

export function resolveBinary(): string | null {
  for (const p of CANDIDATE_PATHS) {
    if (existsSync(p)) return p
  }

  // glob ~/.nvm/versions/node/*/bin/claude
  const nvmVersionsDir = join(homedir(), '.nvm/versions/node')
  if (existsSync(nvmVersionsDir)) {
    try {
      // synchronous glob via readdir pattern
      const { readdirSync } = require('node:fs') as typeof import('node:fs')
      const nodes = readdirSync(nvmVersionsDir)
      for (const node of nodes) {
        const candidate = join(nvmVersionsDir, node, 'bin/claude')
        if (existsSync(candidate)) return candidate
      }
    } catch {
      // ignore
    }
  }

  // fall back to PATH search
  const extraPaths = [
    join(homedir(), '.nvm/current/bin'),
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    '/bin',
  ]
  const augmentedPath = [...extraPaths, ...(process.env['PATH'] ?? '').split(':')]
    .filter((v, i, arr) => v && arr.indexOf(v) === i)
    .join(':')
  try {
    const result = execFileSync('/usr/bin/which', ['claude'], {
      env: { ...process.env, PATH: augmentedPath },
      encoding: 'utf8',
    }).trim()
    if (result && existsSync(result)) return result
  } catch {
    // not found
  }
  return null
}

export function probeVersion(binary: string): Promise<ClaudeVersionInfo> {
  return new Promise((resolve, reject) => {
    const proc = spawn(binary, ['--version'], { env: buildEnv(binary) })
    let out = ''
    let err = ''
    proc.stdout.on('data', (chunk: Buffer) => (out += chunk.toString('utf8')))
    proc.stderr.on('data', (chunk: Buffer) => (err += chunk.toString('utf8')))
    proc.on('close', (code) => {
      if (code !== 0) {
        reject(new Error(`claude --version exited ${code}: ${err || out}`))
        return
      }
      const match = /(\d+)\.(\d+)\.(\d+)/.exec(out)
      if (!match) {
        reject(new Error(`Could not parse version from: ${out.trim()}`))
        return
      }
      const major = parseInt(match[1] ?? '0', 10)
      const minor = parseInt(match[2] ?? '0', 10)
      const patch = parseInt(match[3] ?? '0', 10)
      resolve({
        raw: out.trim(),
        major,
        minor,
        patch,
        isSupported: major > 2 || (major === 2 && minor >= 1),
      })
    })
    proc.on('error', reject)
  })
}

function buildEnv(binary: string): NodeJS.ProcessEnv {
  const binaryDir = dirname(binary)
  const extraDirs = [
    binaryDir,
    join(homedir(), '.nvm/current/bin'),
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    '/bin',
  ]
  const existingParts = (process.env['PATH'] ?? '').split(':')
  const deduped = [...extraDirs, ...existingParts]
    .filter((v, i, arr) => v && arr.indexOf(v) === i)
    .join(':')
  return { ...process.env, PATH: deduped }
}

export interface ClaudeInvocation {
  prompt: string
  systemPrompt?: string
  model: string
  workingDirectory: string
  mcpConfigPath?: string
  maxBudgetUSD?: number
}

function buildArgs(binary: string, inv: ClaudeInvocation): string[] {
  void binary
  const args = [
    '-p',
    '--verbose',
    '--output-format',
    'stream-json',
    '--include-partial-messages',
    '--permission-mode',
    'bypassPermissions',
    '--model',
    inv.model,
    '--add-dir',
    inv.workingDirectory,
  ]
  if (inv.systemPrompt) {
    args.push('--system-prompt', inv.systemPrompt)
  }
  if (inv.mcpConfigPath) {
    args.push('--mcp-config', inv.mcpConfigPath)
  }
  if (inv.maxBudgetUSD !== undefined) {
    args.push('--max-budget-usd', inv.maxBudgetUSD.toFixed(4))
  }
  return args
}

export class ClaudeCodeCLIClient {
  private proc: ReturnType<typeof spawn> | null = null
  private cancelTimer1: ReturnType<typeof setTimeout> | null = null
  private cancelTimer2: ReturnType<typeof setTimeout> | null = null

  async runAgent(
    invocation: ClaudeInvocation,
    onEvent: (event: ClaudeStreamEvent) => void,
    onStderr: (text: string) => void,
  ): Promise<void> {
    const binary = resolveBinary()
    if (!binary) throw new Error('Claude CLI binary not found')

    const args = buildArgs(binary, invocation)
    const env = buildEnv(binary)

    return new Promise((resolve, reject) => {
      const proc = spawn(binary, args, {
        cwd: invocation.workingDirectory,
        env,
        stdio: ['pipe', 'pipe', 'pipe'],
      })
      this.proc = proc

      const lineBuffer = new NDJSONLineBuffer()

      proc.stdout.on('data', (chunk: Buffer) => {
        const lines = lineBuffer.append(chunk)
        for (const line of lines) {
          onEvent(parseLine(line))
        }
      })

      proc.stderr.on('data', (chunk: Buffer) => {
        onStderr(chunk.toString('utf8'))
      })

      proc.on('close', (code, signal) => {
        this.proc = null
        this.clearTimers()

        const tail = lineBuffer.flush()
        if (tail) onEvent(parseLine(tail))

        if (signal) {
          reject(new Error('stoppedByUser'))
        } else if (code === 0) {
          resolve()
        } else {
          reject(new Error(`exitedWithError ${code}`))
        }
      })

      proc.on('error', (err) => {
        this.proc = null
        reject(err)
      })

      // Send prompt via stdin then close
      if (proc.stdin) {
        proc.stdin.write(invocation.prompt, 'utf8')
        proc.stdin.end()
      }
    })
  }

  cancel(): void {
    const proc = this.proc
    if (!proc) return
    try { proc.kill('SIGINT') } catch { /* ignore */ }

    this.cancelTimer1 = setTimeout(() => {
      if (proc.exitCode !== null) return
      try { proc.kill('SIGTERM') } catch { /* ignore */ }
      this.cancelTimer2 = setTimeout(() => {
        if (proc.exitCode !== null) return
        try { proc.kill('SIGKILL') } catch { /* ignore */ }
      }, 3000)
    }, 2000)
  }

  private clearTimers(): void {
    if (this.cancelTimer1) { clearTimeout(this.cancelTimer1); this.cancelTimer1 = null }
    if (this.cancelTimer2) { clearTimeout(this.cancelTimer2); this.cancelTimer2 = null }
  }
}
