#!/usr/bin/env node
// Superpowers -> Obsidian vault automation.
//
// Modes:
//   node obsidian-vault.mjs ensure <dir>   Register <dir> as an Obsidian vault (idempotent).
//   node obsidian-vault.mjs hook           PostToolUse hook: read the tool payload on stdin;
//                                          if the written file is a superpowers plan, register
//                                          the plan's repo root as a vault. Never blocks a tool.
//
// Vaults are registered by editing Obsidian's obsidian.json directly, so this works whether or
// not Obsidian is running. Dedupe is by resolved real path, so an already-registered folder is
// never registered twice. Works in any repo: the vault root is derived from the plan's path.

import {
  readFileSync, writeFileSync, existsSync, mkdirSync, realpathSync, appendFileSync, renameSync,
} from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir, platform } from 'node:os';
import { randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';

function obsidianConfigPath() {
  const home = homedir();
  switch (platform()) {
    case 'darwin':
      return join(home, 'Library', 'Application Support', 'obsidian', 'obsidian.json');
    case 'win32':
      return join(process.env.APPDATA || join(home, 'AppData', 'Roaming'), 'obsidian', 'obsidian.json');
    default:
      return join(process.env.XDG_CONFIG_HOME || join(home, '.config'), 'obsidian', 'obsidian.json');
  }
}

// Resolve to a canonical absolute path so dedupe compares apples to apples.
function norm(p) {
  try { return realpathSync(p); } catch { return p.replace(/\/+$/, ''); }
}

// Register `dir` as an Obsidian vault. Idempotent. Returns { added, vaultPath, name }.
function ensureVault(dir) {
  const vaultPath = norm(dir);
  if (!existsSync(vaultPath)) throw new Error(`vault dir does not exist: ${vaultPath}`);

  const cfgPath = obsidianConfigPath();
  let cfg = { vaults: {} };
  if (existsSync(cfgPath)) {
    try { cfg = JSON.parse(readFileSync(cfgPath, 'utf8')); } catch { cfg = { vaults: {} }; }
  }
  if (!cfg.vaults || typeof cfg.vaults !== 'object') cfg.vaults = {};

  // Dedupe by resolved path — never add a second entry for the same folder.
  const already = Object.values(cfg.vaults).some((v) => v && v.path && norm(v.path) === vaultPath);
  let added = false;
  if (!already) {
    let id = randomBytes(8).toString('hex');
    while (cfg.vaults[id]) id = randomBytes(8).toString('hex');
    cfg.vaults[id] = { path: vaultPath, ts: Date.now() };
    mkdirSync(dirname(cfgPath), { recursive: true });
    const tmp = `${cfgPath}.tmp-${process.pid}`;
    writeFileSync(tmp, JSON.stringify(cfg));
    renameSync(tmp, cfgPath); // atomic replace
    added = true;
  }

  // Make it a valid vault and keep code/deps from cluttering the file explorer & graph.
  const dotObs = join(vaultPath, '.obsidian');
  if (!existsSync(dotObs)) mkdirSync(dotObs, { recursive: true });
  const appJson = join(dotObs, 'app.json');
  if (!existsSync(appJson)) {
    writeFileSync(appJson, `${JSON.stringify({
      userIgnoreFilters: ['node_modules/', '.git/', 'dist/', 'build/', 'coverage/', '.superpowers/'],
    }, null, 2)}\n`);
  }

  // Hide .obsidian/ from git via the repo-local exclude file — never touches tracked files.
  try {
    if (existsSync(join(vaultPath, '.git'))) {
      const exPath = join(vaultPath, '.git', 'info', 'exclude');
      mkdirSync(dirname(exPath), { recursive: true });
      const ex = existsSync(exPath) ? readFileSync(exPath, 'utf8') : '';
      if (!/^\.obsidian\/?\s*$/m.test(ex)) {
        appendFileSync(exPath, `${ex && !ex.endsWith('\n') ? '\n' : ''}.obsidian/\n`);
      }
    }
  } catch { /* non-fatal: git exclude is a nicety, not required */ }

  return { added, vaultPath, name: vaultPath.split('/').pop() };
}

// Vault root for a plan file: the git repo root, else the `docs` ancestor, else the file's dir.
function vaultRootForPlan(file) {
  const dir = dirname(file);
  try {
    const root = execFileSync('git', ['-C', dir, 'rev-parse', '--show-toplevel'],
      { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim();
    if (root) return root;
  } catch { /* not a git repo */ }
  const idx = file.indexOf('/docs/');
  if (idx !== -1) return file.slice(0, idx + '/docs'.length);
  return dir;
}

// Matches the writing-plans default location: <repo>/docs/superpowers/plans/<name>.md
const PLAN_RE = /\/docs\/superpowers\/plans\/[^/]+\.md$/;

function runHook() {
  let raw = '';
  try { raw = readFileSync(0, 'utf8'); } catch { process.exit(0); }
  let data = {};
  try { data = JSON.parse(raw); } catch { process.exit(0); }
  const file = data && data.tool_input && data.tool_input.file_path;
  if (!file || !PLAN_RE.test(file)) process.exit(0); // not a plan -> silent no-op
  try {
    const res = ensureVault(vaultRootForPlan(file));
    if (res.added) {
      process.stdout.write(JSON.stringify({
        systemMessage: `Obsidian: registered vault "${res.name}" for this repo (${res.vaultPath}).`,
        suppressOutput: true,
      }));
    }
  } catch { /* never break the triggering tool */ }
  process.exit(0);
}

const mode = process.argv[2];
if (mode === 'hook') {
  runHook();
} else if (mode === 'ensure' && process.argv[3]) {
  console.log(JSON.stringify(ensureVault(process.argv[3])));
} else {
  console.error('usage: obsidian-vault.mjs (hook | ensure <dir>)');
  process.exit(2);
}
