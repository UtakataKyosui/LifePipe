FROM node:24-alpine AS frontend
WORKDIR /build
ENV PUPPETEER_SKIP_DOWNLOAD=true CYPRESS_INSTALL_BINARY=0
RUN corepack enable
COPY frontend/package.json frontend/pnpm-lock.yaml frontend/pnpm-workspace.yaml ./
RUN pnpm install --frozen-lockfile
COPY frontend ./
ARG VERSION=dev
RUN echo "{\"VERSION\": \"${VERSION}\"}" > src/version.json && pnpm run build

FROM golang:1.27-alpine AS backend
RUN apk add --no-cache build-base
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY main.go ./
COPY pkg ./pkg
COPY frontend/embed.go ./frontend/embed.go
COPY --from=frontend /build/dist ./frontend/dist
ARG VERSION=dev
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=1 go build -p 1 -tags osusergo \
      -ldflags "-s -w -linkmode external -extldflags '-static' -X code.vikunja.io/api/pkg/version.Version=${VERSION}" \
      -o /out/vikunja .

FROM alpine:3
RUN apk add --no-cache ca-certificates tzdata && \
    mkdir -p /app/vikunja/files && chown -R 1000:1000 /app/vikunja
COPY --from=backend /out/vikunja /app/vikunja/vikunja
USER 1000
WORKDIR /app/vikunja
ENV VIKUNJA_SERVICE_ROOTPATH=/app/vikunja/ GODEBUG=multipathtcp=0
VOLUME /app/vikunja/files
EXPOSE 3456
ENTRYPOINT ["/app/vikunja/vikunja"]
