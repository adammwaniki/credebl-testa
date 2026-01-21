FROM node:20-alpine

LABEL maintainer="CREDEBL"
LABEL description="Verification adapter for did:polygon credentials with upstream forwarding"

WORKDIR /app

# Copy adapter
COPY adapter.js .

# Environment variables with defaults
ENV ADAPTER_PORT=8085
ENV CREDEBL_AGENT_URL=http://localhost:8004
ENV CREDEBL_API_KEY=supersecret-that-too-16chars
ENV UPSTREAM_VERIFY_SERVICE=http://verify-service:8080

EXPOSE 8085

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8085/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1))"

CMD ["node", "adapter.js"]
