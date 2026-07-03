# How it works

A deep dive into the mechanism behind `obsidian-vault.mjs`.

## The two modes

The script is invoked in one of two ways:

| Mode | Invocation | Purpose |
|------|-----------|---------|
| `hook` | `node obsidian-vault.mjs hook` | Reads a Claude Code tool payload on stdin. If the written file is a Superpowers plan, registers the plan's repo as a vault. Never blocks the tool. |
| `ensure` | `node obsidian-vault.mjs ensure <dir>` | Registers `<dir>` as an Obsidian vault directly. Idempotent. Prints a JSON result. |

`hook` is what the Claude Code `PostToolUse` hook calls; `ensure` is the reusable core
and is handy to run by hand.

## The hook trigger

The `settings.json` command is deliberately cheap on the hot path — it runs on *every*
`Write`/`Edit`:

```sh
j=$(cat)
printf "%s" "$j" | grep -q "docs/superpowers/plans/" \
  && printf "%s" "$j" | node "$HOME/.claude/hooks/obsidian-vault.mjs" hook 2>/dev/null
true
```

The `grep -q` short-circuits: node only starts for payloads that mention the plans path.
The trailing `true` guarantees the hook exits 0 so it can never fail the triggering tool.
Inside the script, `PLAN_RE` (`/\/docs\/superpowers\/plans\/[^/]+\.md$/`) does the precise
match — `grep` is just a fast pre-filter.

## Resolving the vault root

Given a plan file, the vault root is chosen in this order:

1. **Git repo root** — `git -C <plan-dir> rev-parse --show-toplevel`. This is the normal case.
2. **Nearest `docs/` ancestor** — if the file isn't in a git repo, the path is truncated at
   `/docs`.
3. **The file's own directory** — last resort.

Scoping to the repo root (rather than just `docs/`) means the whole project is browsable in
Obsidian, while the ignore filters below keep it from being noisy.

## Registering the vault

Obsidian stores its known vaults in a single JSON file:

| OS | Path |
|----|------|
| macOS | `~/Library/Application Support/obsidian/obsidian.json` |
| Windows | `%APPDATA%\obsidian\obsidian.json` |
| Linux | `$XDG_CONFIG_HOME/obsidian/obsidian.json` (or `~/.config/obsidian/obsidian.json`) |

Registration writes a new entry into the `vaults` map:

```json
{ "vaults": { "<random-16-hex-id>": { "path": "<absolute-path>", "ts": <ms-epoch> } } }
```

Editing this file directly (rather than using Obsidian's UI or CLI) is what lets the hook
work whether or not Obsidian is currently running. The write is **atomic**: the config is
written to a `.tmp-<pid>` file and then `rename()`d over the original, so a crash mid-write
can't corrupt `obsidian.json`.

### Deduplication

Before adding an entry, the script resolves every existing vault path with
`realpathSync` and compares against the resolved target. If any existing vault points at the
same real folder (even via a different symlink or trailing slash), nothing is added. This is
what makes both `hook` and `ensure` safe to run repeatedly.

## Making the folder a tidy vault

Registering a path isn't quite enough — a first-class vault has a `.obsidian/` folder. The
script creates one with a minimal `app.json`:

```json
{
  "userIgnoreFilters": [
    "node_modules/", ".git/", "dist/", "build/", "coverage/", ".superpowers/"
  ]
}
```

`userIgnoreFilters` keeps build output and dependencies out of Obsidian's file explorer and
graph view, so you see docs and source — not `node_modules`.

## Staying invisible to git

So the new `.obsidian/` folder doesn't show up as an untracked change, the script appends
`.obsidian/` to the repo's **local** git exclude file (`.git/info/exclude`) — only if the
folder is a git repo and the entry isn't already there. This is per-clone and never modifies
a tracked `.gitignore`, so it won't surprise collaborators or show up in a diff.

## Failure philosophy

Every side effect is wrapped so the triggering tool is never affected:

- The git-exclude step is best-effort (`try/catch`, silently skipped on failure).
- `runHook` catches everything around `ensureVault` and always `process.exit(0)`.
- The shell command ends in `true`.

The worst case is that a vault silently isn't registered — never a broken `Write`.
