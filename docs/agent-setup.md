# Coding agent setup

This repository provides shared guidance and optional formatting hooks for GitHub Copilot, Claude Code, and OpenAI Codex.

## Shared guidance

[`AGENTS.md`](../AGENTS.md) is the common entry point for repository layout, Go development rules, and validation commands. Copilot also reads [`.github/copilot-instructions.md`](../.github/copilot-instructions.md); Claude Code imports the shared guide through [`CLAUDE.md`](../CLAUDE.md). The project-specific Go skills live in `.agents/skills/`.

## Hooks

Claude Code uses [`.claude/settings.json`](../.claude/settings.json), and Codex uses [`.codex/config.toml`](../.codex/config.toml). Both configure a `PostToolUse` hook for file editing tools. The shared script `.agent-hooks/format-go.py` reads the hook event and runs `gofmt -w` only when the edited file is:

- a `.go` file inside this repository,
- a regular file (not a path outside the repository), and
- not an example under `.agents/skills/`.

The hook does not run tests, access the network, or read environment secrets. It is intentionally limited to formatting; CI remains responsible for tests and `go vet`.

Codex project hooks run only after the project configuration is trusted. To disable them in Codex, override `[features] hooks = false` in your user configuration. To disable Claude Code project hooks, set `"disableAllHooks": true` in applicable Claude settings. Review hook changes like any executable project configuration.

If Python 3 or `gofmt` is unavailable, the hook reports an error for a Go file and can be disabled as above. Format and validate manually with:

```sh
gofmt -w ./cmd
go test ./...
go vet ./...
```

## Copilot

Copilot's repository-wide instructions are in `.github/copilot-instructions.md`; the shared `AGENTS.md` is also available to agents that support that convention. Skills are stored in `.agents/skills/`, tracked in `skills-lock.json`, and can be refreshed with:

```sh
npx skills update
```

Use the Go skills alongside LifePipe's guidance. BeautifulGo includes rules for a particular backend stack; those rules are conditional and should not be imposed on this gateway unless the architecture adopts that stack.

## References

- [OpenAI Codex hooks](https://developers.openai.com/codex/hooks/)
- [Claude Code hooks guide](https://code.claude.com/docs/en/hooks-guide)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [GitHub Copilot repository custom instructions](https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/add-custom-instructions/add-repository-instructions)
- [GitHub Copilot Agent Skills](https://docs.github.com/en/copilot/concepts/customizations/agent-skills)
