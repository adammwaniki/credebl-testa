FROM node:20-alpine

LABEL maintainer="CREDEBL"
LABEL description="Adapter service bridging Inji Verify to CREDEBL for did:polygon credential verification"

WORKDIR /app

# Copy application files
COPY package.json .
COPY adapter.js .

# No npm install needed - adapter uses only Node.js built-ins

# Create non-root user
RUN addgroup -g 1001 -S adapter && \
    adduser -u 1001 -S adapter -G adapter && \
    chown -R adapter:adapter /app

USER adapter

# Environment variables with defaults
ENV ADAPTER_PORT=8085
ENV CREDEBL_AGENT_URL=http://localhost:8004
ENV CREDEBL_API_KEY=

EXPOSE 8085

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD node -e "const http = require('http'); http.get('http://localhost:' + process.env.ADAPTER_PORT + '/health', (r) => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "adapter.js"]
