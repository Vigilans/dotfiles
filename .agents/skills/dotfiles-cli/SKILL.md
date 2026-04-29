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

`bootstrap.sh` at the repo root:
1. Parses `DOTFILES_EXTRA_PROFILES` (whitespace-tolerant `name=url` pairs) and clones each into `profiles/<name>/`. If the cloned repo isn't a framework profile (verified by `dotfiles_is_profile_dir` grep on `name=` and `supported_os=`), its contents are wrapped under `dotfiles/` and a `profile.sh` is generated from the standard template via `dotfiles_create_profile`. Detection uses grep, not source — remote code only runs at install phase.
2. Appends extra profile names to `DOTFILES_PROFILES`, resolves dependencies and OS filtering via `dotfiles_resolve_profiles`, installs each profile in dependency order.
3. Symlinks the CLI to `~/.local/bin/dotfiles`.

## Current commands

```
Profile management:
  list        List profiles and their status
  create      Create a new profile from template
  remove      Remove a profile from the repository
  import      Import dotfiles into a profile (stow --adopt)

Installation:
  status      Show detailed install status for a profile
  install     Install a profile (prepare + package + resolve conflicts + install)
  uninstall   Uninstall a profile (unstow from $HOME)
  upgrade     Upgrade an installed profile

Self management:
  self update    Pull latest dotfiles repository (and initialized submodules)
  self version   Show framework commit SHA, message, and age

Shell integration:
  completion  Output shell completion script (bash|zsh)
```

## Install flow & conflict resolution

`dotfiles install <profile>` runs four stages: `prepare → package → resolve conflicts → install`.

When existing files in `$HOME` would conflict with stow, `_dotfiles_resolve_conflicts` prompts per file:

- `[d]iff` — preview with `git diff --no-index` (repeatable, returns to prompt)
- `[b]ackup` — move HOME file to `$DOTFILES_ROOT/.backups/<profile>-<timestamp>/`
- `[k]eep` — copy HOME content into dotfiles dir, remove HOME file (git preserves original)
- `[M]erge` (default) — `_dotfiles_resolve_merge` synthesizes a base from common lines (`diff -u | grep '^ '`), runs `git merge-file` to produce conflict markers, opens `$EDITOR` for resolution, writes result to dotfiles dir

After all conflicts are resolved, the profile's `install()` phase runs stow without conflicts.

## Environment loading

`dotfiles-rc.sh` is the single loader, guarded by `DOTFILES_RC_LOADED`:
1. Sets `DOTFILES_ROOT` if not already set
2. Sources `.env` with `set -a` (skips if `.env` doesn't exist — repo ships `.env.example`)
3. Sources `dotfiles-lib.sh`

All profiles also source this file, so lib functions are always available inside lifecycle functions.

## Profile discovery

Profiles live in two places:
- `profiles/<name>/` — tracked in the main repo, or cloned via `DOTFILES_EXTRA_PROFILES` (self-protecting via nested `.git/`)
- `profiles/local/<name>/` — gitignored escape hatch for local-only profiles

`dotfiles_discover_profiles` scans both paths. `dotfiles_profile_dir <name>` resolves a name to a directory by searching the two locations in order, used by every lib function that needs the profile path.

## Template system

`scripts/templates/profile.sh` contains `__NAME__`, `__DESCRIPTION__`, `__OS__` placeholders. `dotfiles_create_profile` replaces them via `sed` and auto-detects the current OS via `dotfiles_current_os`.

## Adding a new command

1. Add a `dotfiles_<verb>()` function in `dotfiles-lib.sh` with all logic.
2. Add a `cmd_<verb>()` wrapper in `dotfiles-cli.sh` that validates args and calls the lib function.
3. Add a `case` entry in the dispatch block.
4. Add it to the help text under the right section.
5. Add it to both completion files (`dotfiles.bash` and `dotfiles.zsh`).

## Conventions

### Library functions

- **Naming**: `dotfiles_<verb>` for public functions, `_dotfiles_<name>` for internal helpers.
- **Profile path resolution**: use `dotfiles_profile_dir <name>` to map a profile name to its directory. It searches `profiles/<name>` then `profiles/local/<name>`. All lib functions that take a profile name use this.
- **Framework profile detection**: `dotfiles_is_profile_dir <dir>` greps for `name=` and `supported_os=` in `<dir>/profile.sh` to verify it's a framework profile (not e.g. a POSIX `profile.sh` that just sets PATH). Used by bootstrap to decide whether a cloned repo needs wrapping. Detection is grep-based rather than source-based to avoid running unintended remote code.
- **Profile loading**: use `dotfiles_run_phase <profile> <function>` to source a profile.sh and call a lifecycle function in a subshell. This isolates side effects (cd, env changes).
- **Metadata reading**: use `dotfiles_load_profile <name>` which sources in a subshell with `set +u` and emits tab-separated fields. Returns non-zero if profile has no `name` variable.
- **Status checking**: `dotfiles_profile_status <name>` returns one of: `installed`, `not installed`, `partial`, `no dotfiles`. It uses `_dotfiles_check_tree` which recursively walks the dotfiles/ directory and checks whether corresponding $HOME paths are symlinks pointing back to the profile (handling stow's directory folding).
- **Profile resolution**: `dotfiles_resolve_profiles [profile...]` takes profile names (or discovers all if none given), filters by current OS, auto-includes dependencies, and returns a topologically sorted list. Used by `bootstrap.sh`; caller is responsible for parsing `DOTFILES_PROFILES` from `.env`.
- **Errors**: print to stderr and `return 1`. The CLI translates non-zero returns to appropriate exit codes.

### CLI

- `set -euo pipefail` at the top.
- DOTFILES_ROOT resolved via `realpath` on `BASH_SOURCE` to handle the `~/.local/bin/dotfiles` symlink.
- Exit code 2 for usage errors, 1 for runtime errors, 0 for success.
- Commands that accept multiple profiles loop over `"$@"`.
- Destructive operations (`remove`) check install status and refuse if installed.
