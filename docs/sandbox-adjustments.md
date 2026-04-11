# Sandbox Adjustments

Patches needed to run NanoClaw inside a Claude Code Docker Sandbox.

## Environment (verified empirically)

The sandbox provides:
- `HTTPS_PROXY=http://gateway.docker.internal:3128` (MITM proxy for API key injection)
- `NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt` (proxy CA cert)
- Hostname: `nanoclaw`
- Docker-in-Docker works (Docker Engine v29.4.0)
- Network policy enforcement: proxy blocks connections to domains not in the allowed list

### DinD networking (key discovery)

DinD containers do NOT have transparent proxy access. Direct HTTPS fails with `ECONNRESET`.
They must explicitly route through the proxy via HTTP CONNECT.

From inside DinD containers:
- `gateway.docker.internal` resolves to `172.17.0.0` (Docker embedded DNS, where the proxy lives)
- `host.docker.internal` resolves to `169.254.1.1` (NOT the proxy)
- Do NOT override `gateway.docker.internal` with `--add-host` — Docker DNS resolves it correctly

Verified working: `HTTPS_PROXY=http://gateway.docker.internal:3128` + `NODE_EXTRA_CA_CERTS` +
`ANTHROPIC_API_KEY=proxy-managed` → proxy injects real API key and returns 200 from `api.anthropic.com`.

## What doesn't need changing

- **Discord channel** — Tested: both `https.get()` and `fetch()` (undici) work through the transparent proxy from the host process. `NODE_EXTRA_CA_CERTS` is respected in Node.js 20.
- **`cleanupOrphans()` self-termination** — Not an issue. The filter is `name=nanoclaw-` (with dash); the sandbox hostname is `nanoclaw` (no dash). Also, DinD's Docker daemon doesn't see the sandbox container at all.
- **OneCLI for credential injection** — Not needed. OneCLI is not running (`localhost:10254` connection refused), but the sandbox proxy handles API key injection. Agent containers need `ANTHROPIC_API_KEY=proxy-managed` and `HTTPS_PROXY` set instead.

## Changes needed

### 1. `container/Dockerfile` — proxy build args

`npm install` during `docker build` fails with `SELF_SIGNED_CERT_IN_CHAIN` because the proxy MITMs HTTPS.

Add after `FROM node:22-slim`:

```dockerfile
ARG http_proxy
ARG https_proxy
ARG no_proxy
ARG NODE_EXTRA_CA_CERTS
ARG npm_config_strict_ssl=true
RUN npm config set strict-ssl ${npm_config_strict_ssl}
```

And after the last `RUN npm install` (line 43, before `COPY agent-runner/ ./`):

```dockerfile
RUN npm config set strict-ssl true
```

### 2. `container/build.sh` — forward proxy args to docker build

Add `--build-arg` flags to the `docker build` call (line 16):

```bash
${CONTAINER_RUNTIME} build \
  --build-arg http_proxy="${http_proxy:-$HTTP_PROXY}" \
  --build-arg https_proxy="${https_proxy:-$HTTPS_PROXY}" \
  --build-arg no_proxy="${no_proxy:-$NO_PROXY}" \
  --build-arg NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS}" \
  --build-arg npm_config_strict_ssl=false \
  -t "${IMAGE_NAME}:${TAG}" .
```

### 3. `src/container-runner.ts` — three changes

**a. Replace `/dev/null` shadow mount** (line 86)

Docker Sandbox rejects `/dev/null` bind mounts ("path not shared"). Replace with an empty file:

```typescript
const emptyEnvPath = path.join(DATA_DIR, 'empty-env');
if (!fs.existsSync(emptyEnvPath)) fs.writeFileSync(emptyEnvPath, '');
// Use emptyEnvPath instead of '/dev/null' in the mount
```

**b. Forward proxy env vars and set `ANTHROPIC_API_KEY` fallback** in `buildContainerArgs()`

Agent containers need explicit proxy config (DinD has no transparent proxy access).
When OneCLI is unavailable but proxy env vars are set, inject `ANTHROPIC_API_KEY=proxy-managed`
so Claude Code routes traffic through the proxy and gets the real key injected.

```typescript
// Forward proxy env vars to agent containers
for (const key of ['HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy']) {
  if (process.env[key]) args.push('-e', `${key}=${process.env[key]}`);
}

// When OneCLI is unavailable but we're behind a proxy, set a placeholder API key.
// The sandbox proxy replaces "proxy-managed" with the real key automatically.
if (!onecliApplied && process.env.HTTPS_PROXY) {
  args.push('-e', 'ANTHROPIC_API_KEY=proxy-managed');
}
```

**c. Mount CA cert** in `buildContainerArgs()`

The proxy CA cert must be inside the container for TLS verification to succeed.

```typescript
const caCertSrc = process.env.NODE_EXTRA_CA_CERTS || process.env.SSL_CERT_FILE;
if (caCertSrc && fs.existsSync(caCertSrc)) {
  const certDir = path.join(DATA_DIR, 'ca-cert');
  fs.mkdirSync(certDir, { recursive: true });
  const certDest = path.join(certDir, 'proxy-ca.crt');
  fs.copyFileSync(caCertSrc, certDest);
  args.push('-v', `${certDir}:/workspace/ca-cert:ro`);
  args.push('-e', 'NODE_EXTRA_CA_CERTS=/workspace/ca-cert/proxy-ca.crt');
}
```

### 4. `setup/container.ts` — proxy build args

The setup step's `execSync` build command (line 106) also needs proxy `--build-arg` flags:

```typescript
const proxyArgs = [
  `--build-arg http_proxy="${process.env.http_proxy || process.env.HTTP_PROXY || ''}"`,
  `--build-arg https_proxy="${process.env.https_proxy || process.env.HTTPS_PROXY || ''}"`,
  `--build-arg no_proxy="${process.env.no_proxy || process.env.NO_PROXY || ''}"`,
  `--build-arg NODE_EXTRA_CA_CERTS="${process.env.NODE_EXTRA_CA_CERTS || ''}"`,
  `--build-arg npm_config_strict_ssl=false`,
].join(' ');

execSync(`${buildCmd} ${proxyArgs} -t ${image} .`, {
  cwd: path.join(projectRoot, 'container'),
  stdio: ['ignore', 'pipe', 'pipe'],
});
```

## Differences from original `docker-sandboxes.md` guide

| Guide step | Status | Notes |
|---|---|---|
| 4a. Dockerfile proxy args | **Needed** | Same as guide |
| 4b. build.sh proxy args | **Needed** | Same as guide |
| 4c. container-runner /dev/null | **Needed** | Same as guide |
| 4c. container-runner proxy vars | **Needed** | Plus `ANTHROPIC_API_KEY=proxy-managed` fallback |
| 4c. container-runner CA cert | **Needed** | Same as guide |
| 4d. cleanupOrphans self-kill | **Not needed** | Filter already excludes sandbox container |
| 4e. credential-proxy.ts | **Not needed** | File doesn't exist; OneCLI not needed; sandbox proxy handles it |
| 4f. setup/container.ts proxy | **Needed** | Same as guide |
