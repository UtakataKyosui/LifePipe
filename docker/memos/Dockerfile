FROM node:24-alpine@sha256:116b800c3754b440ee0aa3ed2f20f5bf3d99a554bfd9adeea09ea8017f6e85f5 AS frontend
WORKDIR /build/web
RUN corepack enable
COPY web/package.json web/pnpm-lock.yaml web/pnpm-workspace.yaml ./
COPY web/patches ./patches
RUN pnpm install --frozen-lockfile
COPY web ./
RUN pnpm release

FROM golang:1.27.4-alpine@sha256:0a5f7fe796599ff487605987432e7619ae45beeb2fba4c2ce0b907879932aebf AS backend
WORKDIR /build
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY cmd ./cmd
COPY core ./core
COPY filter ./filter
COPY internal ./internal
COPY markdown ./markdown
COPY proto ./proto
COPY provider ./provider
COPY server ./server
COPY store ./store
COPY --from=frontend /build/server/frontend/dist ./server/frontend/dist
ARG VERSION=26.11.0
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -p 1 -trimpath \
      -ldflags="-s -w -X github.com/usememos/memos/internal/version.Version=${VERSION}" \
      -tags netgo,osusergo -o /out/memos ./cmd/memos

FROM alpine:3.21@sha256:bc21487101ae47172509130ee1092cc273a831968d64b617776d1f69c81e42ab
RUN apk add --no-cache tzdata ca-certificates su-exec && \
    addgroup -g 10001 -S nonroot && \
    adduser -u 10001 -S -G nonroot -h /var/opt/memos nonroot && \
    mkdir -p /var/opt/memos /usr/local/memos && \
    chown -R nonroot:nonroot /var/opt/memos
COPY --from=backend /out/memos /usr/local/memos/memos
COPY --chmod=755 scripts/entrypoint.sh /usr/local/memos/entrypoint.sh
WORKDIR /var/opt/memos
VOLUME /var/opt/memos
ENV TZ=UTC MEMOS_PORT=5230
EXPOSE 5230
ENTRYPOINT ["/usr/local/memos/entrypoint.sh", "/usr/local/memos/memos"]
