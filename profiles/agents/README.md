# agents

Cross-tool config for AGENTS.md-aware coding agents (Claude Code, Codex, opencode, ...). Stows a single source of rules, skills, and agent definitions under `~/.agents/`, and links each tool's expected paths into it.

Self-authored content — the `AGENTS.md` rules file, sub-agent definitions under `agents/`, and any first-party skills under `skills/` — is stowed directly from dotfiles. Vendor skills are not committed: they're declared in `.skill-lock.json` and restored by `npx skills add` at `install` time, so the lock is the source of truth for which third-party skills are pinned.

Per-tool config that can't be shared (Claude Code's `settings.json`, hooks) is rendered at `package` time from [templates/](templates/), interpolating values from the `.env` channel.

`prepare` installs runtime dependencies (`jq`, `node`). `install` also runs `claude plugin install` for plugins enabled in `settings.json`. Both `npx skills add` and plugin install are idempotent.

The rendered `settings.json` is `.gitignore`'d so runtime mutations (Claude Code's `/effort`, etc.) don't produce diffs in dotfiles.

## Inputs from other profiles

[`templates/.claude/settings.json.j2`](templates/.claude/settings.json.j2) consumes env vars from the [`.env` channel](../README.md#env-channel) — e.g. a private `secrets` profile can contribute `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, etc. `{% if VAR %}` guards drop the line when a variable is unset, so omitting the `secrets` profile just yields a `settings.json` that uses Anthropic official endpoint.
