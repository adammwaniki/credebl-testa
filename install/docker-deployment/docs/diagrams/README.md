# Architecture Diagrams

This directory contains Mermaid diagram files for the CREDEBL + Inji Verify Offline Verification PoC.

## Diagram Files

| File | Description | Type |
|------|-------------|------|
| `01-storyboard-flow.mmd` | High-level credential lifecycle phases | Flowchart |
| `02-entity-relationship.mmd` | Database entity relationships | ERD |
| `03-dfd-online-verification.mmd` | Online verification data flow | DFD |
| `04-dfd-offline-verification.mmd` | Offline verification data flow | DFD |
| `05-dfd-issuer-sync.mmd` | Issuer cache sync data flow | DFD |
| `06-adapter-architecture.mmd` | Verification adapter internal architecture | Flowchart |
| `07-sequence-online-verification.mmd` | Online verification sequence | Sequence |
| `08-sequence-offline-verification.mmd` | Offline verification sequence | Sequence |
| `09-sequence-credential-issuance.mmd` | Credential issuance sequence | Sequence |
| `10-sequence-issuer-sync.mmd` | Issuer sync sequence | Sequence |
| `11-deployment-architecture.mmd` | Container deployment layout | Flowchart |
| `12-complete-lifecycle.mmd` | Complete system lifecycle overview | Flowchart |

## Viewing Diagrams

### Option 1: GitHub / GitLab
Both platforms render `.mmd` files automatically. Just view the file in the web interface.

### Option 2: VS Code
Install the "Markdown Preview Mermaid Support" extension:
```bash
code --install-extension bierner.markdown-mermaid
```

### Option 3: Mermaid Live Editor
1. Go to https://mermaid.live
2. Paste the diagram content
3. Export as SVG/PNG

### Option 4: Command Line (mermaid-cli)
```bash
# Install
npm install -g @mermaid-js/mermaid-cli

# Convert to SVG
mmdc -i 01-storyboard-flow.mmd -o 01-storyboard-flow.svg

# Convert to PNG
mmdc -i 01-storyboard-flow.mmd -o 01-storyboard-flow.png

# Convert all diagrams
for f in *.mmd; do mmdc -i "$f" -o "${f%.mmd}.svg"; done
```

### Option 5: Include in Markdown
```markdown
​```mermaid
flowchart LR
    A --> B
​```
```

## Diagram Descriptions

### Storyboard Flow (01)
Shows the four main phases of the credential lifecycle:
1. **Setup** - Platform, organization, agent configuration
2. **Issuance** - Credential creation and signing
3. **Holding** - QR code generation and storage
4. **Verification** - Online and offline verification paths

### Entity Relationship Diagram (02)
Shows database entities and their relationships:
- User, Organization, Wallet, Agent
- Schema, Credential Definition, Credential
- Holder, Issuer Cache, Context Cache

### Data Flow Diagrams (03-05)
Shows how data moves through the system:
- **Online Verification** - Full path through backends to blockchain
- **Offline Verification** - Local cache-based verification
- **Issuer Sync** - Populating the cache before going offline

### Adapter Architecture (06)
Internal structure of the verification adapter:
- HTTP endpoints
- Core components (parser, router, connectivity detector)
- Verification strategies (online, offline, hybrid)
- Cache storage

### Sequence Diagrams (07-10)
Step-by-step message flows:
- **Online Verification** - Credential → Adapter → Agent → Polygon → Result
- **Offline Verification** - Credential → Adapter → Cache → Result
- **Credential Issuance** - Request → Agent → Sign → Deliver
- **Issuer Sync** - Request → Resolve DID → Cache

### Deployment Architecture (11)
Docker container layout showing:
- Frontend layer (UI, Inji Verify)
- Gateway layer (API Gateway, Adapter)
- Services layer (microservices)
- Agent layer (Credo, Inji Verify Service)
- Data layer (PostgreSQL, Redis, NATS, etc.)

### Complete Lifecycle (12)
Comprehensive view combining all phases with online/offline paths.

## Color Coding

| Color | Meaning |
|-------|---------|
| Blue (#3B82F6) | CREDEBL Platform components |
| Purple (#6366F1) | Agent/Credo components |
| Green (#10B981) | Verification Adapter |
| Yellow (#F59E0B) | Offline/Cache components |
| Pink (#DB2777) | Verification phase |
| Red (#DC2626) | Errors/Failures |

## Updating Diagrams

1. Edit the `.mmd` file
2. Preview using one of the methods above
3. Regenerate images if needed
4. Commit changes

## Related Documentation

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Full architectural documentation
- [demo-offline-verification.sh](../../demo-offline-verification.sh) - Demo script
- [test-offline-verification.sh](../../test-offline-verification.sh) - Test script
