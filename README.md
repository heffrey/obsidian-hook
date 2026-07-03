# obsidian-hook

Automatically open your [Superpowers](https://github.com/obra/superpowers) plans in
[Obsidian](https://obsidian.md) — no copying, no manual setup.

When Superpowers writes a plan to `docs/superpowers/plans/*.md`, a Claude Code
`PostToolUse` hook registers that plan's repo as an Obsidian vault. The next time you
open Obsidian, the repo is right there in your vault switcher, and you're editing the
real, git-tracked Markdown — not a disconnected copy.

## Why

Obsidian works on *vaults* (folders), not individual files, so viewing a plan normally
means either copying it into a default vault (edits don't sync back) or manually adding
the repo as a vault every time. This hook does the manual step for you, the moment a
plan is written, for any repo.

## How it works

- A single Node script, [`hooks/obsidian-vault.mjs`](hooks/obsidian-vault.mjs), runs on
  every Claude Code `Write`/`Edit`. It exits immediately unless the written file matches
  `docs/superpowers/plans/<name>.md`.
- For a matching plan, it resolves the repo root (via `git rev-parse`, falling back to the
  nearest `docs/` ancestor) and registers it as a vault by editing Obsidian's
  `obsidian.json` directly — so it works whether or not Obsidian is running.
- Registration is **idempotent**: dedupe is by resolved real path, so a repo is never
  added twice. It also writes a minimal `.obsidian/app.json` that ignores `node_modules/`,
  `.git/`, `dist/`, `build/`, `coverage/`, and `.superpowers/` so Obsidian's file explorer
  and graph aren't cluttered with source, and adds `.obsidian/` to the repo's local git
  exclude (never touching tracked files).
- The hook **never blocks or fails the triggering tool** — any error is swallowed.

See [docs/how-it-works.md](docs/how-it-works.md) for the full mechanism.

## Requirements

- [Node.js](https://nodejs.org) (any recent version) on your `PATH`
- [Obsidian](https://obsidian.md)
- [Claude Code](https://claude.com/claude-code) with the
  [Superpowers](https://github.com/obra/superpowers) plugin (or any workflow that writes to
  `docs/superpowers/plans/`)

## Install

```sh
git clone https://github.com/heffrey/obsidian-hook.git
cd obsidian-hook
./install.sh
```

The installer copies the script to `~/.claude/hooks/` and merges the hook into
`~/.claude/settings.json` (backing it up to `settings.json.bak` first). It's idempotent —
re-run it any time to update the script.

Then **restart Obsidian** so it picks up newly registered vaults.

### Manual install

If you'd rather not run the script, copy the hook yourself:

```sh
cp hooks/obsidian-vault.mjs ~/.claude/hooks/
```

and add this entry under `hooks.PostToolUse` in `~/.claude/settings.json` (replace the
node path with your own — `command -v node`):

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    {
      "type": "command",
      "command": "j=$(cat); printf \"%s\" \"$j\" | grep -q \"docs/superpowers/plans/\" && printf \"%s\" \"$j\" | /opt/homebrew/bin/node \"$HOME/.claude/hooks/obsidian-vault.mjs\" hook 2>/dev/null; true"
    }
  ]
}
```

## Usage

Just work. When Superpowers writes a plan, you'll see a one-line confirmation
(`Obsidian: registered vault "<repo>" for this repo`) the first time each repo is
registered. Restart Obsidian and open the repo from the vault switcher.

You can also register any folder manually:

```sh
node ~/.claude/hooks/obsidian-vault.mjs ensure /path/to/folder
```

## Customizing the trigger

The hook only reacts to Superpowers plan paths. To vault-register on a different path,
edit the `PLAN_RE` regex near the top of `obsidian-vault.mjs`:

```js
const PLAN_RE = /\/docs\/superpowers\/plans\/[^/]+\.md$/;
```

For example, `/\/docs\/[^/]+\.md$/` would register a repo whenever any Markdown file is
written directly under its `docs/` folder.

## Uninstall

```sh
./uninstall.sh
```

Removes the hook entry from `settings.json` (with a backup) and deletes the script. Vaults
it already registered are left in place — remove them from Obsidian's vault switcher if you
want them gone.

## License

[MIT](LICENSE)
