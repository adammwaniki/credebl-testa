# Stage 1: Build Go binary
FROM golang:1.22-alpine AS go-build
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -o testa-edu-ui .

# Stage 2: Install Node.js dependencies
FROM node:20-alpine AS node-deps
WORKDIR /deps
COPY scripts/package.json scripts/package-lock.json* ./
RUN npm install --production

# Stage 3: Final image
FROM node:20-alpine

WORKDIR /app

# Copy Go binary
COPY --from=go-build /build/testa-edu-ui /app/testa-edu-ui

# Copy Node.js dependencies and script
COPY --from=node-deps /deps/node_modules /app/scripts/node_modules
COPY scripts/qr-encode.js /app/scripts/
COPY scripts/package.json /app/scripts/

# Copy templates, static assets, and data
COPY templates/ /app/templates/
COPY static/ /app/static/
COPY templates-data/ /app/templates-data/

ENV PORT=3002
ENV AGENT_URL=http://host.docker.internal:8004
ENV API_KEY=supersecret-that-too-16chars
ENV ISSUER_DID=did:polygon:0xD3A288e4cCeb5ADE57c5B674475d6728Af3bD9Fd
ENV NODE_BIN=node
ENV SCRIPTS_DIR=/app/scripts

EXPOSE 3002

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q --spider http://localhost:3002/health || exit 1

CMD ["/app/testa-edu-ui"]
