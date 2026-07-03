#!/usr/bin/env bash
#
# Installer for the Superpowers -> Obsidian vault hook.
#
#   - Copies hooks/obsidian-vault.mjs into ~/.claude/hooks/
#   - Merges a PostToolUse hook into ~/.claude/settings.json (idempotent, with backup)
#
# Safe to run more than once. Re-running updates the script and leaves settings.json alone
# if the hook is already installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_SRC="$SCRIPT_DIR/hooks/obsidian-vault.mjs"
HOOK_DST="$HOOKS_DIR/obsidian-vault.mjs"

# --- Requirements -----------------------------------------------------------
NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "error: node not found on PATH. Install Node.js first (e.g. 'brew install node')." >&2
  exit 1
fi

# --- Sanity check: has Obsidian ever run? -----------------------------------
# The hook edits obsidian.json, which Obsidian creates on first launch. If its
# parent dir is missing, registration still works but the hook stays a silent
# no-op until Obsidian has run at least once — so warn, don't fail.
case "$(uname -s)" in
  Darwin) OBS_DIR="$HOME/Library/Application Support/obsidian" ;;
  *)      OBS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/obsidian" ;;
esac
if [ ! -d "$OBS_DIR" ]; then
  echo "note: Obsidian config dir not found ($OBS_DIR)." >&2
  echo "      Install and launch Obsidian at least once, then this hook will register vaults." >&2
fi

# --- Copy the hook script ---------------------------------------------------
mkdir -p "$HOOKS_DIR"
cp "$HOOK_SRC" "$HOOK_DST"
chmod +x "$HOOK_DST"
echo "installed: $HOOK_DST"

# --- Merge the hook into settings.json --------------------------------------
# The merge runs in node (already a requirement) so there's no jq dependency and
# existing hooks are preserved. The command is written with the detected node path.
NODE_BIN="$NODE_BIN" SETTINGS="$SETTINGS" "$NODE_BIN" <<'NODE'
const { readFileSync, writeFileSync, existsSync, copyFileSync } = require('node:fs');

const settingsPath = process.env.SETTINGS;
const nodeBin = process.env.NODE_BIN;

const command =
  `j=$(cat); printf "%s" "$j" | grep -q "docs/superpowers/plans/" && ` +
  `printf "%s" "$j" | "${nodeBin}" "$HOME/.claude/hooks/obsidian-vault.mjs" hook 2>/dev/null; true`;

let cfg = {};
if (existsSync(settingsPath)) {
  copyFileSync(settingsPath, settingsPath + '.bak');
  try { cfg = JSON.parse(readFileSync(settingsPath, 'utf8')); }
  catch { console.error('error: settings.json is not valid JSON; aborting merge.'); process.exit(1); }
}

cfg.hooks = cfg.hooks || {};
cfg.hooks.PostToolUse = cfg.hooks.PostToolUse || [];

// Idempotent: bail if any existing hook already points at our script.
const already = JSON.stringify(cfg.hooks.PostToolUse).includes('obsidian-vault.mjs');
if (already) {
  console.log('settings.json: obsidian hook already present, left unchanged.');
  process.exit(0);
}

cfg.hooks.PostToolUse.push({
  matcher: 'Write|Edit',
  hooks: [{ type: 'command', command }],
});

writeFileSync(settingsPath, JSON.stringify(cfg, null, 2) + '\n');
console.log(`settings.json: added PostToolUse hook (backup at ${settingsPath}.bak).`);
NODE

cat <<'EOF'

Done. Next steps:
  1. Restart Obsidian so it picks up newly registered vaults.
  2. Let Superpowers write a plan (docs/superpowers/plans/*.md) in any repo —
     that repo is auto-registered as an Obsidian vault.

Optional: to open specific files from the CLI, enable
"Command line interface" in Obsidian's Settings -> Advanced.
EOF
