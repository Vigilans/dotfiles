# agents

Cross-tool config for AGENTS.md-aware coding agents (Claude Code, Codex, opencode, ...). Stows a single source of rules, skills, and agent definitions under `~/.agents/`, and links each tool's expected paths into it.

Self-authored content — sub-agent definitions under `agents/` and any first-party skills under `skills/` — is stowed directly from dotfiles. The `AGENTS.md` rules file lives in [Vigilans/agents](https://github.com/Vigilans/agents), pulled in as a submodule at [dotfiles/.local/share/agents/](dotfiles/.local/share/agents/). Vendor skills are not committed: they're declared in `.skill-lock.json` and restored by `npx skills add` at `install` time, so the lock is the source of truth for which third-party skills are pinned.

Per-tool config that can't be shared (Claude Code's `settings.json`, Codex's `auth.json` / `config.toml` / `models.json`) is rendered at `package` time from [templates/](templates/), interpolating values from the `.env` channel.

`prepare` installs runtime dependencies (`jq`, `node`). `package` also exports a Codex model catalog prototype into `build/`. `install` also runs `claude plugin install` for plugins enabled in `settings.json`. Both `npx skills add` and plugin install are idempotent.

The rendered `settings.json`, `config.toml`, `models.json`, and `auth.json` are `.gitignore`'d so runtime mutations (Claude Code's `/effort`, Codex's model picker, etc.) don't produce diffs in dotfiles.

## Inputs from other profiles

Endpoint and models are declared once, in a tool-agnostic schema this profile owns, and each tool's template adapts them into its own config format. A private `secrets` profile publishes them through the [`.env` channel](../README.md#env-channel):

| Variable | Meaning |
|---|---|
| `AGENTS_BASE_URL` | Gateway endpoint every agent talks to. |
| `AGENTS_API_KEY` | Credential for that endpoint. |
| `AGENTS_MODEL_PROVIDER` | Provider name, for tools that require one. |
| `AGENTS_CLAUDE_SUBSCRIPTION_LOGIN` | Set to `true` to retain Claude subscription authentication if the configured provider supports a separate authentication method. |
| `AGENTS_CODEX_CHATGPT_LOGIN` | Set to `true` to require a Codex ChatGPT/API-key login while keeping the gateway credential provider-scoped. |
| `AGENTS_<ALIAS>_MODEL` | Canonical model ID. Declaring one is what registers `<ALIAS>`. A trailing `[1m]` marks a 1M-context deployment. |
| `AGENTS_<ALIAS>_MODEL_DESCRIPTION` | Display name shown in model pickers. |
| `AGENTS_<ALIAS>_REASONING_EFFORT` | Default effort for the model: `minimal`, `low`, `medium`, `high`, `xhigh`, or `max`. |
| `AGENTS_MODEL_SUPPORTS_EFFORT_SUFFIX` | Set to `true` for gateways that select effort through the model name rather than a request parameter. |

`{% if VAR %}` guards drop the line when a variable is unset, so omitting the `secrets` profile just yields configs pointing at each tool's official endpoint.

Codex rewrites its own `config.toml` at runtime — selected model and effort, marketplaces, plugin state, MCP paths, trusted projects — so [`templates/.codex/config.toml.j2`](templates/.codex/config.toml.j2) parses the existing file, patches only the keys it owns, and writes the whole document back.
