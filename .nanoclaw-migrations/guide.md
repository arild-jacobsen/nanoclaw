# NanoClaw Migration Guide

Generated: 2026-05-15
Base: 934f063 (merge-base with upstream at generation time)
HEAD at generation: c7dcf6e13a1a70c40842aac64f0ca6f57290ecec
Upstream: 975a2f0 (v2.0.63)

## Migration Plan

This fork is on v1.2.x; upstream is on v2.0.x. The channel architecture was
rewritten in v2, so the v1 Discord code is **not** ported directly — Discord is
re-added via the official `/add-discord` skill instead. All other customizations
are small, additive, and independent.

Order of operations during upgrade:
1. Check out clean upstream v2 in the worktree.
2. Run `/add-discord` to reapply the Discord channel (v2-native).
3. Reapply the file-level customizations below (all additive, low conflict risk).
4. Delete the two unwanted upstream workflows.
5. Validate (`npm install && npm run build && npm test`).

Risk area: `start.sh` was written for v1 — verify its commands/paths still hold
on v2 after copying (see customization 4).

## Applied Skills

- **Discord channel** — reapply with the **`/add-discord`** skill (operational
  skill, present in v2 at `.claude/skills/add-discord/`). It is **not** a
  `skill/*` branch merge.
  - The fork's v1 `src/channels/discord.ts` was confirmed **stock** — identical
    to the `discord` remote (`qwibitai/nanoclaw-discord`) apart from Prettier
    reformatting. **No user modifications to carry over.**
  - `/add-discord` handles everything the v1 merge did: the channel module, its
    registration, the `discord.js` dependency, and the `DISCORD_BOT_TOKEN` env
    var. Do not manually port `discord.ts`, `discord.test.ts`,
    `src/channels/index.ts`, `package.json`, or `.env.example` for Discord —
    the skill does it the v2 way.

No custom (user-authored) skills exist.

## Skill Interactions

None. Discord is the only applied channel skill.

## Modifications to Applied Skills

None — the Discord integration was used as-is (stock).

## Customizations

Customizations 1–2 and 4 are brand-new files untouched by upstream; the cleanest
reapplication is `git checkout c7dcf6e -- <path>` from inside the worktree
(c7dcf6e is the pre-migration HEAD recorded above). Customizations 3, 5, 6 are
edits to files that upstream also changed — apply them by hand as described.

### 1. CI: npm vulnerability auto-fix workflow

**Intent:** A GitHub Actions workflow that auto-fixes npm vulnerabilities on push
to `main`.

**Files:** `.github/workflows/fix-vulnerabilities.yml` (new, 63 lines).

**How to apply:** `git checkout c7dcf6e -- .github/workflows/fix-vulnerabilities.yml`

### 2. CI: feature/change issue template

**Intent:** A GitHub issue template for tracking features/changes.

**Files:** `.github/ISSUE_TEMPLATE/feature.md` (new, 28 lines).

**How to apply:** `git checkout c7dcf6e -- .github/ISSUE_TEMPLATE/feature.md`

### 3. CI: remove unwanted upstream workflows

**Intent:** The user does not want upstream's auto version-bump and token-count
workflows. Both still ship in v2 and must be deleted after checkout.

**Files:** `.github/workflows/bump-version.yml`,
`.github/workflows/update-tokens.yml`.

**How to apply:** `git rm .github/workflows/bump-version.yml .github/workflows/update-tokens.yml`
(verify the paths still exist in v2 first; delete whichever are present.)

### 4. OneCLI-aware startup script

**Intent:** `start.sh` is the single entry point — it starts OneCLI via Docker
Compose if not running, waits for its health check (`/api/health`), then
launches NanoClaw in dev or prod mode.

**Files:** `start.sh` (new, 77 lines), `CLAUDE.md` (docs edit).

**How to apply:**
1. `git checkout c7dcf6e -- start.sh`
2. **Verify against v2** before trusting it: confirm v2 still supports
   `npm run dev` and `node dist/index.js`, and that the OneCLI health endpoint
   is still `http://127.0.0.1:10254/api/health`. Adjust `start.sh` if v2 changed
   these.
3. In v2's `CLAUDE.md`, in the Development section, replace the bare
   `npm run dev` line in the commands block with:
   ```bash
   ./start.sh           # Start NanoClaw (prompts for dev/prod mode)
   ./start.sh dev       # Hot reload via npm run dev
   ./start.sh prod      # Compiled via node dist/index.js
   ```
   and add this line after that block:
   > `start.sh` also ensures OneCLI is running before starting NanoClaw. Use it
   > as the single entry point in sandbox environments.

### 5. Install `gh` CLI in the agent container

**Intent:** The GitHub CLI is available inside agent containers.

**Files:** `container/Dockerfile`.

**How to apply:** In the `apt-get install -y` block, add `gh` to the package
list (the v1 change added it right after `git`). Verify v2's Dockerfile still
uses an apt-based image; if v2 restructured the Dockerfile, add `gh` wherever
system packages are installed.

### 6. Ignore `*.db` files

**Intent:** SQLite database files should not be committed.

**Files:** `.gitignore`.

**How to apply:** Add a `*.db` line (the v1 change placed it under the
`# Temp files` section). Skip if v2 already ignores `*.db`.

## Intentionally Dropped (do NOT reapply)

These existed on v1 `main` but the user chose to drop them during this migration:

- `docs/sandbox-attempt-summary.md` — record of a shelved Docker Sandbox
  experiment. Still preserved on the `docker-sandbox` branch.
- `.claude/settings.json` sandbox `allowedDomains` tweak — let v2's default
  `.claude/settings.json` stand.

The full Docker Sandbox attempt lives on the `docker-sandbox` branch
(`origin/docker-sandbox`) if ever needed again.
