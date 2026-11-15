---
name: lifepipe-go
description: >-
  Develop and review Go code in LifePipe, especially the MCP gateway, service
  adapters, and composite workflows. Use for Go files, dependency changes,
  tests, MCP tools, context propagation, and concurrency.
---

# LifePipe Go development

- Keep the gateway as a thin integration layer over the domain services described in the README. Do not duplicate their systems of record.
- Use `github.com/modelcontextprotocol/go-sdk` for MCP protocol handling; do not implement MCP framing or transport by hand.
- Keep external service access behind small, focused clients. Pass `context.Context` through requests and respect cancellation and deadlines.
- For independent workflow calls, use structured concurrency with `errgroup`; return errors with enough context and do not silently discard partial failures.
- Keep secrets and personal-life data out of logs, tests, and committed configuration. Read credentials from runtime configuration.
- Prefer focused tests with fake clients over tests that require live services or credentials.
- Before finishing Go changes, run `gofmt`, `go test ./...`, and `go vet ./...`.

The upstream Go best-practices skill that informed these guidelines is available at
[Facta-Dev/beautifulgo](https://github.com/Facta-Dev/beautifulgo/tree/f18da804ac146023e08c1d47601288c8aa6c5850/skills/go-best-practices).
