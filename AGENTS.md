# Agent guide

LifePipe is a Go MCP gateway scaffold for a self-hosted Personal Life OS. The current executable is `cmd/life-mcp`; domain service clients and composite workflows are planned, not implemented yet.

## Go development

- Keep the gateway thin: external domain services remain their own systems of record.
- Use `github.com/modelcontextprotocol/go-sdk` for MCP protocol handling.
- Pass `context.Context` through external calls, and use `errgroup` for independent concurrent workflow calls.
- Keep secrets and personal-life data out of logs, tests, and committed configuration.
- Follow the Go skills in `.agents/skills/`: `go-best-practices`, `go-review`, and `go-port`. Apply BeautifulGo's backend-stack-specific rules only if the repository adopts that architecture.

## Build and validation

The module targets Go 1.25. Run from the repository root:

```sh
gofmt -w ./cmd
go test ./...
go vet ./...
go build -o /tmp/life-mcp ./cmd/life-mcp
```

CI caches dependencies using `go.sum`, checks formatting for changed project Go files on pull requests, then runs tests and `go vet`.

## Agent-specific setup

- Copilot: `.github/copilot-instructions.md`
- Claude Code: `CLAUDE.md`, `.claude/settings.json`
- Codex: this file and `.codex/config.toml`
- Hook behavior and troubleshooting: `docs/agent-setup.md`
