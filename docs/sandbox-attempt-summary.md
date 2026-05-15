# Docker Sandbox Attempt — Change Inventory

A consolidated record of every change made while trying to run NanoClaw inside a
Claude Code Docker Sandbox. The attempt was shelved (too many frustrations).
This file exists to support cleanup — it lists what was touched, why, and which
commit it came from, so changes can be reverted or kept deliberately.

## Source commits (authored by Arild — now on the `docker-sandbox` branch)

| Commit | Date | Title |
|--------|------|-------|
| `52798c1` | 2026-04-11 16:46 | fix: sandbox compatibility for Docker Sandbox environments |
| `80eff65` | 2026-04-11 16:55 | Modified to run in Docker Sandbox |
| `aa26ce7` | 2026-04-14 19:13 | feat(sandbox): add start.sh for OneCLI-aware NanoClaw startup |

A fourth commit added two previously-uncommitted bug fixes — the OneCLI
proxy-clobber guard in `src/container-runner.ts` and the `/api/health` fix in
`start.sh` — plus this summary file.

**Branch layout:** the full sandbox attempt (all four commits above) is preserved
on the **`docker-sandbox`** branch. `main` has been cleaned: an interactive
rebase dropped `52798c1` (the core sandbox-compat commit). `aa26ce7` was kept
because `start.sh` is useful outside a sandbox; `80eff65` was kept (it is only
Prettier reformatting once its sandbox hunks are gone). The `container-runner.ts`
proxy-clobber guard also stayed on `docker-sandbox` only — it is moot without the
sandbox proxy code — so on `main` the fourth commit carries just the `start.sh`
fix and this file. This file itself stays on `main` as the record of what was
removed and where it now lives.

The original analysis doc `docs/sandbox-adjustments.md` (created in `52798c1`, so
now on the `docker-sandbox` branch only) is the empirical writeup of how the
sandbox environment behaves; this file is the change ledger.

## Why the changes were needed

A Claude Code Docker Sandbox runs NanoClaw behind a MITM proxy that injects API
keys and enforces a network allowlist. Two consequences drove every change:

1. **TLS interception** — the proxy re-signs HTTPS with its own CA, so `npm install`
   during image build and any HTTPS from agent containers fail unless the proxy
   CA is trusted.
2. **Docker-in-Docker has no transparent proxy** — agent containers spawned inside
   the sandbox can't reach the proxy implicitly; proxy settings must be passed
   explicitly as env vars.

## Changes by file

### `container/Dockerfile` — `52798c1` (substantive)
Added `ARG http_proxy / https_proxy / no_proxy / NODE_EXTRA_CA_CERTS` and an
`npm_config_strict_ssl` arg. Toggles `npm config set strict-ssl` off for the
install step (to survive the MITM cert) and back on afterward.
**Purpose:** let `docker build` run `npm install` behind the MITM proxy.

### `container/build.sh` — `52798c1` (substantive)
Forwards `http_proxy/https_proxy/no_proxy/NODE_EXTRA_CA_CERTS` as `--build-arg`
flags, with `npm_config_strict_ssl=false`.
**Purpose:** plumb host proxy env into the Dockerfile args above.

### `setup/container.ts` — `52798c1` (substantive)
Same proxy `--build-arg` flags added to the `execSync` build command used by the
`/setup` skill.
**Purpose:** the setup-driven build path needs the same proxy plumbing as `build.sh`.

### `src/container-runner.ts` — `52798c1` + bug-fix commit (substantive)
Three changes from `52798c1`:
- **Empty-file `.env` shadow** — replaced the `/dev/null` bind mount with an empty
  file at `DATA_DIR/empty-env`, because Docker Sandbox rejects `/dev/null` mounts
  ("path not shared"). Still shadows `.env` so agents can't read host secrets.
- **Proxy env forwarding** — forwards `HTTP(S)_PROXY/NO_PROXY` (both cases) into
  agent containers, since DinD has no transparent proxy.
- **CA cert + API-key fallback** — copies the proxy CA into `DATA_DIR/ca-cert`,
  mounts it read-only into the container, sets `NODE_EXTRA_CA_CERTS`, and (when
  OneCLI is absent) sets `ANTHROPIC_API_KEY=proxy-managed` so the proxy injects
  the real key.

**Refinement (bug-fix commit):** the proxy-forwarding + API-key + CA-cert block is
now wrapped in `if (!onecliApplied)`. Reason: when OneCLI *is* applied, its
gateway is the sole proxy. Forwarding the sandbox proxy as well would add
duplicate `-e` flags, and Docker keeps the last `-e` for a duplicate key —
silently overriding OneCLI's env and bypassing its credential injection.

### `start.sh` — `aa26ce7` + bug-fix commit (substantive)
New file. Single entry point for sandbox environments: prompts for (or accepts)
dev/prod mode, starts OneCLI via `docker compose` if not already running, waits
for its health check, then launches NanoClaw.
**Follow-up fix (bug-fix commit):** health-check URL corrected from `/health` to
`/api/health`.

### `CLAUDE.md` — `aa26ce7` (substantive)
Development section updated to document `./start.sh` as the entry point instead of
`npm run dev`.

### `.claude/settings.json` — `aa26ce7` (config)
Removed `us.i.posthog.com` from the sandbox `allowedDomains` network allowlist.
(`npm.registry.com` retained.)

### `src/channels/discord.ts`, `src/channels/discord.test.ts` — `80eff65` (NOISE)
Prettier reformatting only — no logic change. Multi-line wrapping of imports,
`.map()` callbacks, and function-call arguments.

### `src/container-runner.ts` (in `80eff65`) — (NOISE)
Prettier reformatting only — same proxy-key array and `caCertSrc` line wrapped
across multiple lines. No behavior change.

### `package-lock.json` — `80eff65` (incidental)
Added the `discord.js` dependency tree (~296 lines). Almost certainly a side
effect of running `npm install` inside the sandbox, syncing the lockfile to an
already-present `package.json` entry. Not a sandbox change per se.

## Summary for cleanup

- **`52798c1`** — entirely sandbox-specific. The core of the attempt. Revert this
  to remove sandbox build/proxy support (also removes `docs/sandbox-adjustments.md`).
- **`80eff65`** — *mislabeled.* Contains no sandbox logic: only Prettier
  reformatting plus a lockfile sync. The reformatting is harmless to keep; the
  commit title is misleading.
- **`aa26ce7`** — `start.sh` + docs + the posthog allowlist tweak. `start.sh` is
  generally useful (OneCLI-aware startup) even outside a sandbox; the
  `CLAUDE.md` update depends on keeping it.
- **Bug-fix commit** — two genuine bug fixes (OneCLI proxy-clobber guard;
  `/api/health` endpoint). Worth keeping on `main` regardless of whether the
  sandbox attempt is abandoned, since they also matter for the OneCLI path.
