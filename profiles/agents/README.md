# agents

Cross-tool config for AGENTS.md-aware coding agents (Claude Code, Codex, OpenCode, ...). Stows shared rules and skills under `~/.agents/`, and renders agent definitions into each tool's own directory.

First-party skills under `skills/` are stowed directly from dotfiles. The `AGENTS.md` rules file lives in [Vigilans/agents](https://github.com/Vigilans/agents), pulled in as a submodule at [dotfiles/.local/share/agents/](dotfiles/.local/share/agents/). Vendor skills are not committed: they're declared in `.skill-lock.json` and restored by `npx skills add` at `install` time, so the lock is the source of truth for which third-party skills are pinned.

Per-tool config that can't be shared (Claude Code's `settings.json`, Codex's `config.toml` / `models.json`, OpenCode's `opencode.json`) is rendered at `package` time from [templates/](templates/), interpolating values from the `.env` channel.

`prepare` installs runtime dependencies (`jq`, `node`, `ripgrep`) and installs or updates the standalone Codex CLI on Linux and macOS. `package` exports a Codex model catalog prototype into `build/`. `install` restores vendor skills, ensures Claude Code is available, and syncs configured plugins. `upgrade` updates Codex, vendor skills, Claude plugins, and ClawGod when selected.

The rendered agent files, `settings.json`, `config.toml`, `models.json`, and `opencode.json` are `.gitignore`'d so generated output and runtime mutations (Claude Code's `/effort`, Codex's model picker, etc.) don't produce diffs in dotfiles. Codex's runtime-owned `auth.json` is ignored separately.

## Inputs from other profiles

Endpoint and models are declared once, in a tool-agnostic schema this profile owns, and each tool's template adapts them into its own config format. A private `secrets` profile publishes them through the [`.env` channel](../README.md#env-channel):

| Variable | Meaning |
|---|---|
| `AGENTS_BASE_URL` | Gateway endpoint every agent talks to. |
| `AGENTS_API_KEY` | Credential for that endpoint. |
| `AGENTS_MODEL_PROVIDER` | Provider name, for tools that require one. |
| `AGENTS_<ALIAS>_MODEL` | Canonical model ID. Declaring one is what registers `<ALIAS>`. A trailing `[1m]` marks a 1M-context deployment. |
| `AGENTS_<ALIAS>_MODEL_DESCRIPTION` | Display name shown in model pickers. |
| `AGENTS_<ALIAS>_REASONING_EFFORT` | Default effort for the model: `minimal`, `low`, `medium`, `high`, `xhigh`, or `max`. |
| `AGENTS_<ALIAS>_MODEL_VISION` | Set to `false` for a model that cannot see. Its Codex prompt then carries a rule to delegate visual inspection to the `vision` sub-agent. |
| `AGENTS_MODEL_SUPPORTS_EFFORT_SUFFIX` | Set to `true` for gateways that select effort through the model name rather than a request parameter. |
| `AGENTS_SUBAGENT_<ROLE>_MODEL` | Shared subagent model: a registered alias or a concrete model ID. |
| `AGENTS_SUBAGENT_<ROLE>_REASONING_EFFORT` | Shared subagent effort override. |
| `<CLIENT>_SUBAGENT_<ID>_MODEL` | Client-specific model override; clients are `CODEX`, `CLAUDE_CODE`, and `OPENCODE`. |
| `<CLIENT>_SUBAGENT_<ID>_REASONING_EFFORT` | Client-specific effort override. |
| `AGENTS_CLAUDE_CODE_SUBSCRIPTION_LOGIN` | Set to `true` to retain Claude subscription authentication if the configured provider supports a separate authentication method. |
| `AGENTS_CLAUDE_CODE_ENABLED_MODELS` | Comma-separated model aliases enabled for Claude Code. Matching is case-insensitive; all registered aliases are enabled when unset. |
| `AGENTS_CODEX_CHATGPT_LOGIN` | Set to `true` to require a Codex ChatGPT/API-key login while keeping the gateway credential provider-scoped. |
| `AGENTS_CODEX_ENABLED_MODELS` | Comma-separated model aliases enabled for Codex. Matching is case-insensitive; all registered aliases are enabled when unset. |
| `AGENTS_CODEX_AUTO_COMPACT_LIMIT_1M` | Auto-compact token limit for Codex models marked `[1m]`. |
| `AGENTS_CODEX_MULTI_AGENT_VERSION` | Codex multi-agent backend: `v1` or `v2`, defaulting to `v2`. Sets both the catalog's per-model version and the matching feature flag. |
| `AGENTS_OPENCODE_ENABLED_MODELS` | Comma-separated model aliases enabled for opencode. Matching is case-insensitive; all registered aliases are enabled when unset. |

`{% if VAR %}` guards drop the line when a variable is unset, so omitting the `secrets` profile just yields configs pointing at each tool's official endpoint.

Codex rewrites its own `config.toml` at runtime — selected model and effort, marketplaces, plugin state, MCP paths, trusted projects — so [`templates/.codex/config.toml.j2`](templates/.codex/config.toml.j2) parses the existing file, patches only the keys it owns, and writes the whole document back.

## Custom agents

Claude Code, Codex, and OpenCode share one template per custom agent. Configure its model and reasoning effort once for all three, with per-client overrides.

```sh
AGENTS_SUBAGENT_EXPLORER_MODEL=DEEPSEEK_FLASH
CODEX_SUBAGENT_EXPLORER_MODEL=GPT_LUNA
CODEX_SUBAGENT_EXPLORER_REASONING_EFFORT=max
```

Models accept registered alias or concrete model ID. Client settings override shared settings; an explicit effort overrides the selected alias's effort. An agent's ID is determined by its symlink name in each coding agent. For example, the explorer template is named general-explorer in Claude Code/OpenCode, and the per-client model variable for claude code is CLAUDE_CODE_SUBAGENT_GENERAL_EXPLORER_MODEL.

Edit an agent's [definition](templates/.agents/agents/) to change its instructions.
