#!/usr/bin/env bash
#
# Round-trip test for install.sh / uninstall.sh.
#
# Runs against a throwaway CLAUDE_CONFIG_DIR so it never touches your real ~/.claude.
# Asserts that install adds our hook while preserving a pre-existing unrelated hook,
# that a second install is a no-op, and that uninstall removes only our hook.
#
# Usage: test/roundtrip.sh   (from the repo root, or anywhere — it finds the repo)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export CLAUDE_CONFIG_DIR="$TMP/.claude"
SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
mkdir -p "$CLAUDE_CONFIG_DIR"

# Seed a settings.json with an unrelated hook we expect to survive untouched.
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PostToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "echo existing" }] }
    ]
  }
}
JSON

fail() { echo "FAIL: $1" >&2; exit 1; }
assert_contains() { grep -q -- "$1" "$SETTINGS" || fail "$2"; }
assert_absent()   { grep -q -- "$1" "$SETTINGS" && fail "$2" || true; }

# --- install ---------------------------------------------------------------
"$REPO_DIR/install.sh" >/dev/null
assert_contains "obsidian-vault.mjs" "install did not add the obsidian hook"
assert_contains "echo existing"      "install clobbered the pre-existing hook"
[ -f "$CLAUDE_CONFIG_DIR/hooks/obsidian-vault.mjs" ] || fail "hook script was not copied"
echo "ok: install adds hook and preserves existing"

# --- idempotency -----------------------------------------------------------
COUNT_BEFORE="$(grep -c "obsidian-vault.mjs" "$SETTINGS")"
"$REPO_DIR/install.sh" >/dev/null
COUNT_AFTER="$(grep -c "obsidian-vault.mjs" "$SETTINGS")"
[ "$COUNT_BEFORE" = "$COUNT_AFTER" ] || fail "second install duplicated the hook"
echo "ok: re-install is a no-op"

# --- uninstall -------------------------------------------------------------
"$REPO_DIR/uninstall.sh" >/dev/null
assert_absent   "obsidian-vault.mjs" "uninstall left our hook behind"
assert_contains "echo existing"      "uninstall removed the pre-existing hook"
[ -f "$CLAUDE_CONFIG_DIR/hooks/obsidian-vault.mjs" ] && fail "uninstall left the script behind" || true
echo "ok: uninstall removes only our hook"

echo "PASS"
