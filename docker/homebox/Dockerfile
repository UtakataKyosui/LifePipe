FROM node:22-alpine AS frontend
WORKDIR /app
RUN npm install -g pnpm@10
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY frontend ./
RUN pnpm build

FROM golang:alpine AS backend
WORKDIR /go/src/app
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend ./
COPY --from=frontend /app/.output/public ./app/api/static/public
ARG VERSION=dev
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -ldflags "-s -w -X main.version=${VERSION}" -o /out/api ./app/api/*.go

FROM alpine:3
RUN apk add --no-cache ca-certificates wget
COPY --from=backend /out/api /app/api
ENV HBOX_MODE=production \
    HBOX_STORAGE_CONN_STRING=file:///?no_tmp_dir=true \
    HBOX_STORAGE_PREFIX_PATH=data
WORKDIR /app
EXPOSE 7745
VOLUME /data
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:7745/api/v1/status >/dev/null || exit 1
ENTRYPOINT ["/app/api"]
