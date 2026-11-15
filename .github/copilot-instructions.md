# Copilot instructions

Read [`AGENTS.md`](../AGENTS.md) for the repository overview, Go conventions, and validation commands. This repository currently contains a Go 1.25 MCP stdio server scaffold; domain integrations are planned rather than implemented.

For Go tasks, use the project skills in `.agents/skills/`, especially `go-best-practices`, `go-review`, and `go-port`, together with the LifePipe-specific guidance in `.agents/skills/lifepipe-go/SKILL.md`. BeautifulGo's backend stack rules are conditional; do not impose its six-file slice architecture unless the project adopts it.

Run `go test ./...` and `go vet ./...` for Go changes. Avoid committing credentials or real personal-life data. Agent hook setup and documentation are in [`docs/agent-setup.md`](../docs/agent-setup.md).
