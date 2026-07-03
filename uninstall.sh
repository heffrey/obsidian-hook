#!/usr/bin/env bash
#
# Uninstaller for the Superpowers -> Obsidian vault hook.
#
#   - Removes the PostToolUse hook entry from ~/.claude/settings.json (with backup)
#   - Removes ~/.claude/hooks/obsidian-vault.mjs
#
# Does NOT unregister any Obsidian vaults it created — those live in obsidian.json
# and are harmless to leave. Remove them from Obsidian's vault switcher if you want.

set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_DST="$CLAUDE_DIR/hooks/obsidian-vault.mjs"

NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "error: node not found on PATH." >&2
  exit 1
fi

if [ -f "$SETTINGS" ]; then
  SETTINGS="$SETTINGS" "$NODE_BIN" <<'NODE'
const { readFileSync, writeFileSync, existsSync, copyFileSync } = require('node:fs');
const settingsPath = process.env.SETTINGS;
let cfg = {};
try { cfg = JSON.parse(readFileSync(settingsPath, 'utf8')); }
catch { console.error('settings.json is not valid JSON; leaving it alone.'); process.exit(0); }

const arr = cfg.hooks && cfg.hooks.PostToolUse;
if (!Array.isArray(arr)) { console.log('no PostToolUse hooks; nothing to remove.'); process.exit(0); }

const kept = arr.filter((e) => !JSON.stringify(e).includes('obsidian-vault.mjs'));
if (kept.length === arr.length) { console.log('obsidian hook not found in settings.json.'); process.exit(0); }

copyFileSync(settingsPath, settingsPath + '.bak');
cfg.hooks.PostToolUse = kept;
if (kept.length === 0) delete cfg.hooks.PostToolUse;
writeFileSync(settingsPath, JSON.stringify(cfg, null, 2) + '\n');
console.log(`settings.json: removed obsidian hook (backup at ${settingsPath}.bak).`);
NODE
fi

if [ -f "$HOOK_DST" ]; then
  rm -f "$HOOK_DST"
  echo "removed: $HOOK_DST"
fi

echo "Done."
