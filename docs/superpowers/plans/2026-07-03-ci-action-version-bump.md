# CI Action Version Bump Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Silence the Node 20 deprecation warning in CI by upgrading the GitHub Actions to their `@v5` releases, without changing what the workflow tests.

**Architecture:** The `test` workflow pins `actions/checkout` and `actions/setup-node` to `@v4`, which GitHub now force-runs on Node 24 while emitting a deprecation annotation. Bumping both to `@v5` (which target Node 24 natively) removes the warning. The round-trip test itself is untouched, so a green run after the bump proves nothing regressed.

**Tech Stack:** GitHub Actions, Bash, Node.js.

## Global Constraints

- The round-trip test (`test/roundtrip.sh`) must continue to pass on both `ubuntu-latest` and `macos-latest`.
- No change to the hook script, installer, or uninstaller — this task touches CI configuration only.
- `node-version` stays at `'20'` for the round-trip (it exercises the *user's* Node, independent of the runner's action runtime).

---

### Task 1: Bump action versions and confirm CI stays green

**Files:**
- Modify: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: the existing `roundtrip` job and `test/roundtrip.sh` (unchanged).
- Produces: nothing downstream depends on this; the deliverable is a warning-free green CI run.

- [x] **Step 1: Establish the failing signal**

Confirm the current deprecation annotation exists so we know what "fixed" looks like.

Run: `gh run view --log | grep -i "Node.js 20 is deprecated" | head -1`
Expected: a line reporting `actions/checkout@v4` and `actions/setup-node@v4` are forced onto Node 24.

- [x] **Step 2: Bump `actions/checkout`**

In `.github/workflows/test.yml`, change:

```yaml
      - uses: actions/checkout@v4
```

to:

```yaml
      - uses: actions/checkout@v5
```

- [x] **Step 3: Bump `actions/setup-node`**

In the same file, change:

```yaml
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
```

to:

```yaml
      - uses: actions/setup-node@v5
        with:
          node-version: '20'
```

- [x] **Step 4: Commit and push**

```bash
git add .github/workflows/test.yml
git commit -m "ci: bump checkout and setup-node to v5"
git push origin main
```

- [x] **Step 5: Verify the run is green and warning-free**

Run: `gh run watch $(gh run list --limit 1 --json databaseId -q '.[0].databaseId') --exit-status`
Expected: both `roundtrip (ubuntu-latest)` and `roundtrip (macos-latest)` pass, and `gh run view --log | grep -i "Node.js 20 is deprecated"` returns nothing.

---

## Self-Review

- **Spec coverage:** The single goal — remove the deprecation warning without altering test behavior — is covered by Task 1 (both action bumps + a green-run gate).
- **Placeholder scan:** No TBD/TODO; every step has the exact YAML and commands.
- **Type consistency:** N/A (no code interfaces); the only cross-references are the two `uses:` lines, both addressed.
