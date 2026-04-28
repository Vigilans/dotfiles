---
name: dotfiles-cli
description: Use this skill when adding or modifying CLI commands in `scripts/dotfiles-cli.sh`, extending library functions in `scripts/dotfiles-lib.sh`, updating shell completions in `scripts/completions/`, modifying the profile template in `scripts/templates/profile.sh`, or changing how `bootstrap.sh` or `scripts/dotfiles-rc.sh` initializes the environment. Triggers whenever work touches `scripts/` — the framework layer that profiles depend on. Also use when deciding whether logic belongs in the CLI/lib versus inside a profile.
---

# Dotfiles CLI

The `dotfiles` CLI (`scripts/dotfiles-cli.sh`) is the primary interface for managing profiles — for both humans and AI agents. Library functions live in `scripts/dotfiles-lib.sh`; the CLI is a thin wrapper that parses arguments, calls lib functions, and formats output.

## Architecture

```
scripts/
├── dotfiles-cli.sh            # CLI entrypoint (arg parsing + output)
├── dotfiles-lib.sh            # Library functions (all logic lives here)
├── dotfiles-rc.sh             # Environment loader (sources .env + lib)
├── templates/
│   └── profile.sh             # Template for `dotfiles create`
└── completions/
    ├── dotfiles.bash           # Bash completion
    └── dotfiles.zsh            # Zsh completion
```

`bootstrap.sh` at the repo root reads `DOTFILES_PROFILES` from `.env`, resolves dependencies and OS filtering via `dotfiles_resolve_profiles`, installs each profile, then symlinks the CLI to `~/.local/bin/dotfiles`.

## Current commands

```
Profile management:
  list        List profiles and their status
  create      Create a new profile from template
  remove      Remove a profile from the repository
  import      Import dotfiles into a profile (stow --adopt)

Installation:
  status      Show detailed install status for a profile
  install     Install a profile (prepare + package + stow)
  uninstall   Uninstall a profile (unstow from $HOME)
  upgrade     Upgrade an installed profile

Self management:
  self update    Pull latest dotfiles repository (and initialized submodules)
  self version   Show framework commit SHA, message, and age

Shell integration:
  completion  Output shell completion script (bash|zsh)
```

## Adding a new command

1. Add a `dotfiles_<verb>()` function in `dotfiles-lib.sh` with all logic.
2. Add a `cmd_<verb>()` wrapper in `dotfiles-cli.sh` that validates args and calls the lib function.
3. Add a `case` entry in the dispatch block.
4. Add it to the help text under the right section.
5. Add it to both completion files (`dotfiles.bash` and `dotfiles.zsh`).

## Library function conventions

- **Naming**: `dotfiles_<verb>` for public functions, `_dotfiles_<name>` for internal helpers.
- **Profile loading**: use `dotfiles_run_phase <profile> <function>` to source a profile.sh and call a lifecycle function in a subshell. This isolates side effects (cd, env changes).
- **Metadata reading**: use `dotfiles_load_profile <name>` which sources in a subshell with `set +u` and emits tab-separated fields. Returns non-zero if profile has no `name` variable.
- **Status checking**: `dotfiles_profile_status <name>` returns one of: `installed`, `not installed`, `partial`, `no dotfiles`. It uses `_dotfiles_check_tree` which recursively walks the dotfiles/ directory and checks whether corresponding $HOME paths are symlinks pointing back to the profile (handling stow's directory folding).
- **Profile resolution**: `dotfiles_resolve_profiles [profile...]` takes profile names (or discovers all if none given), filters by current OS, auto-includes dependencies, and returns a topologically sorted list. Used by `bootstrap.sh`; caller is responsible for parsing `DOTFILES_PROFILES` from `.env`.
- **Errors**: print to stderr and `return 1`. The CLI translates non-zero returns to appropriate exit codes.

## CLI conventions

- `set -euo pipefail` at the top.
- DOTFILES_ROOT resolved via `realpath` on `BASH_SOURCE` to handle the `~/.local/bin/dotfiles` symlink.
- Exit code 2 for usage errors, 1 for runtime errors, 0 for success.
- Commands that accept multiple profiles loop over `"$@"`.
- Destructive operations (`remove`) check install status and refuse if installed.

## Environment loading

`dotfiles-rc.sh` is the single loader, guarded by `DOTFILES_RC_LOADED`:
1. Sets `DOTFILES_ROOT` if not already set
2. Sources `.env` with `set -a` (skips if `.env` doesn't exist — repo ships `.env.example`)
3. Sources `dotfiles-lib.sh`

All profiles also source this file, so lib functions are always available inside lifecycle functions.

## Template system

`scripts/templates/profile.sh` contains `__NAME__`, `__DESCRIPTION__`, `__OS__` placeholders. `dotfiles_create_profile` replaces them via `sed` and auto-detects the current OS via `dotfiles_current_os`.
