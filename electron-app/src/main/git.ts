import { spawn } from 'node:child_process'

export interface GitRunOptions { cwd: string }

export function run(args: string[], options: GitRunOptions): Promise<string> {
  return new Promise((resolve, reject) => {
    const proc = spawn('git', args, { cwd: options.cwd })
    let out = ''
    let err = ''
    proc.stdout.on('data', (chunk: Buffer) => (out += chunk.toString('utf8')))
    proc.stderr.on('data', (chunk: Buffer) => (err += chunk.toString('utf8')))
    proc.on('close', (code) => {
      if (code === 0) {
        resolve(out)
      } else {
        reject(new Error(`git exited ${code}: ${(err || out).slice(0, 200)}`))
      }
    })
    proc.on('error', reject)
  })
}

export async function diff(cwd: string): Promise<string> {
  return run(['diff'], { cwd })
}

export async function diffNameOnly(cwd: string): Promise<string[]> {
  const out = await run(['diff', '--name-only'], { cwd })
  return out.split('\n').map((l) => l.trim()).filter(Boolean)
}

export async function status(cwd: string): Promise<string> {
  return run(['status', '--porcelain'], { cwd })
}

export async function commit(message: string, files: string[], cwd: string): Promise<string> {
  if (files.length > 0) {
    await run(['add', '--', ...files], { cwd })
  }
  return run(['commit', '-m', message], { cwd })
}

export async function checkoutAll(cwd: string): Promise<void> {
  await run(['checkout', '--', '.'], { cwd })
}

export async function stashPush(message: string, cwd: string): Promise<string> {
  return run(['stash', 'push', '-u', '-m', message], { cwd })
}

export async function stashList(cwd: string): Promise<string> {
  return run(['stash', 'list'], { cwd })
}

export async function stashPop(cwd: string): Promise<string> {
  return run(['stash', 'pop'], { cwd })
}

export async function headSHA(cwd: string): Promise<string> {
  const out = await run(['rev-parse', '--short', 'HEAD'], { cwd })
  return out.trim()
}
