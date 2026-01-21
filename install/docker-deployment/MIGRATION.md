## Migration from Local to EC2

### Prerequisites on EC2

1. **Launch EC2 instance** (Ubuntu 22.04 recommended, t3.medium or larger)

2. **Install Docker:**
   ```bash
   sudo apt update
   sudo apt install -y docker.io docker-compose-v2
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

3. **Open firewall ports** (Security Group):
   | Port | Service |
   |------|---------|
   | 5001 | API Gateway |
   | 8085 | Verification Adapter |
   | 3001 | Inji Verify UI |
   | 8004 | Agent Admin API |
   | 9004 | Agent Inbound (for wallet connections) |

---

### Step 1: Export on Local Machine

```bash
cd /home/adam/cdpi/credebl/install/docker-deployment
./migrate-export.sh
```

This creates: `migration-package/credebl-migration-YYYYMMDD_HHMMSS.tar.gz`

---

### Step 2: Copy to EC2

```bash
scp migration-package/credebl-migration-*.tar.gz ubuntu@<EC2_IP>:~/
```

---

### Step 3: Import on EC2

```bash
# Extract
tar -xzf credebl-migration-*.tar.gz
cd credebl-migration-*

# Run import with your EC2's public IP
./migrate-import.sh <EC2_PUBLIC_IP>

# Or with a domain name:
./migrate-import.sh yourdomain.com https://yourdomain.com
```

The import script will:
- Update all config files with EC2 IP
- Import the PostgreSQL database (wallet keys, credentials, DIDs)
- Start all services
- Reconnect agent containers

---

### Step 4: Verify

```bash
# Check services
docker ps

# Test verification adapter
curl http://<EC2_IP>:8085/health

# Test API gateway
curl http://<EC2_IP>:5001/api

# Check agent logs
docker logs testa-agent
```

---

### Important Notes

| What Migrates | What Needs Manual Update |
|---------------|-------------------------|
| Wallet private keys (in PostgreSQL) | Agent endpoint URL (if using tunnel) |
| DIDs, issued credentials | External-facing URLs in `.env` |
| Schemas, credential definitions | Keycloak/MinIO if external |
| Agent configurations | |

**If you were using a tunnel (ngrok/localtunnel):**
- The old tunnel URL won't work on EC2
- Either set up a new tunnel, or use EC2's public IP directly with port 9004
- Update the agent endpoint in the config if needed
