# Polygon RPC Patch

## Problem

The default Polygon Mainnet RPC (`polygon-rpc.com`) returns 401/403, causing all `did:polygon` credential verification to fail with `NETWORK_ERROR: could not detect network`. The offline verification fallback also fails because the `elliptic` library (needed for secp256k1 signatures) is missing from the verification adapter.

## Affected Components

| Component | Issue |
|-----------|-------|
| **testa-agent** (credo-controller) | `@ayanworks/polygon-did-resolver` hardcodes `polygon-rpc.com` in `build/config.js` |
| **verification-adapter** | `POLYGON_RPC_URL` env var defaults to `polygon-rpc.com`; missing `elliptic` dependency |

## Fix: Verification Adapter

These files have already been patched in the repo:

- `adapter/package.json` — added `elliptic` dependency
- `adapter/Dockerfile` — default `POLYGON_RPC_URL` changed to `polygon-bor-rpc.publicnode.com`
- `adapter/offline-adapter.js` — fallback defaults corrected (RPC URL + registry address)
- `docker-compose.yml` — default `POLYGON_RPC_URL` changed

Rebuild the adapter:

```bash
cd install/docker-deployment
docker compose up -d --no-deps --build verification-adapter
```

## Fix: Credo-TS Agent (testa-agent)

### 1. Add `polygonDid` to the agent config JSON

The agent config file is at the path mounted to `/config` in the container. Add the `polygonDid` block:

```json
{
  "polygonDid": {
    "rpcUrl": "https://polygon-bor-rpc.publicnode.com",
    "didContractAddress": "0x0C16958c4246271622201101C83B9F0Fc7180d15",
    "fileServerUrl": "",
    "schemaManagerContractAddress": "",
    "serverUrl": ""
  }
}
```

Find and edit the config file:

```bash
docker inspect testa-agent --format '{{json .Config.Cmd}}'
# Shows: ["--config", "/config/<uuid>_<name>.json"]
# The host path is shown by:
docker inspect testa-agent --format '{{json .Mounts}}'
```

### 2. Patch the resolver's hardcoded RPC URL

The `@ayanworks/polygon-did-resolver` library has `polygon-rpc.com` hardcoded. Patch it inside the running container:

```bash
docker exec testa-agent sh -c 'cat > /app/node_modules/@ayanworks/polygon-did-resolver/build/config.js << EOF
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.networkConfig = void 0;
exports.networkConfig = {
    testnet: {
        URL: "https://rpc-amoy.polygon.technology",
        CONTRACT_ADDRESS: "0xcB80F37eDD2bE3570c6C9D5B0888614E04E1e49E",
    },
    mainnet: {
        URL: "https://polygon-bor-rpc.publicnode.com",
        CONTRACT_ADDRESS: "0x0C16958c4246271622201101C83B9F0Fc7180d15",
    },
};
EOF'
```

Then restart:

```bash
docker restart testa-agent
```

**Note:** This in-container patch survives `docker restart` but is lost on `docker rm`/`docker compose up --build`. Re-apply after container recreation.

## Verification

```bash
# 1. Agent resolves the DID
TOKEN=$(curl -s -X POST http://localhost:8004/agent/token \
  -H "Authorization: supersecret-that-too-16chars" | jq -r .token)
curl -s "http://localhost:8004/dids/did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd" \
  -H "Authorization: Bearer $TOKEN" | jq .didDocument.id
# Expected: "did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd"

# 2. Adapter has elliptic
docker exec verification-adapter node -e "require('elliptic'); console.log('OK')"

# 3. Adapter RPC is correct
docker exec verification-adapter env | grep POLYGON_RPC_URL
# Expected: https://polygon-bor-rpc.publicnode.com
```

## Alternative Public RPCs

If `polygon-bor-rpc.publicnode.com` goes down, substitute with any of:

| RPC | URL |
|-----|-----|
| PublicNode | `https://polygon-bor-rpc.publicnode.com` |
| MeowRPC | `https://polygon.meowrpc.com` |
| 1RPC | `https://1rpc.io/matic` |
| dRPC | `https://polygon.drpc.org` |
