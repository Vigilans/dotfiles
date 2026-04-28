# AGENTS.md

This file provides guidance to Coding agents when working with code in this repository.

## Project overview

Profile-based dotfiles repository, PKGBUILD-inspired. Each profile is a self-contained unit that bundles configuration files plus an installation lifecycle, and is wired into `$HOME` via GNU Stow symlinks. There are no daemons or background sync — installation and updates are explicit, manual operations.

## Repository layout

```
dotfiles/
├── bootstrap.sh                        # One-click setup: install profiles from .env, then install CLI
├── .env.example                        # Template for .env (DOTFILES_PROFILES, etc.)
├── scripts/
│   ├── dotfiles-cli.sh                 # CLI entrypoint (executable as `dotfiles`)
│   ├── dotfiles-lib.sh                 # Library functions (profile management, stow helpers)
│   ├── dotfiles-rc.sh                  # Loads .env and lib, idempotent (DOTFILES_RC_LOADED guard)
│   ├── templates/
│   │   └── profile.sh                  # Template for `dotfiles create`
│   └── completions/
│       ├── dotfiles.bash               # Bash completion
│       └── dotfiles.zsh                # Zsh completion
└── profiles/
    ├── {name}/
    │   ├── profile.sh                  # Lifecycle script (see below)
    │   ├── dotfiles/                   # Mirrors $HOME — stowed into ~ on install
    │   │   └── .config/{app}/...
    │   └── build/                      # Profile-local build artifacts (gitignored)
    └── ...
```

## CLI (`dotfiles`)

The `dotfiles` CLI is the primary interface. Install via `bash ./bootstrap.sh` (resolves profiles from `.env`, installs them, then symlinks CLI to `~/.local/bin/dotfiles`).

```bash
# Profile management
dotfiles list                           # List profiles and their status
dotfiles create <name> [description]    # Create profile from template
dotfiles remove <name>                  # Delete profile directory
dotfiles import <name> <path>...        # Import existing dotfiles (stow --adopt)

# Installation
dotfiles status <name>                  # Show detailed install status
dotfiles install <name>...              # prepare + package + resolve conflicts + install
dotfiles uninstall <name>...            # Unstow from $HOME
dotfiles upgrade <name>...              # Upgrade installed profile

# Shell integration
dotfiles completion <bash|zsh>          # Output completion script
# Usage: eval "$(dotfiles completion zsh)"
```

## Profile lifecycle (`profile.sh`)

Each profile declares metadata and defines lifecycle functions:

- `name`, `description`, `supported_os=(...)`, `depends=(...)`
- `prepare()` — install upstream packages (brew, apt, pacman, github-release)
- `package()` — assemble files in `dotfiles/` from `build/` artifacts before stowing
- `install()` — `stow -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles`, then start services
- `upgrade()` — re-run `prepare`, update plugins, reload configs
- `uninstall()` — stop services, then `stow -v -D -d "$PROFILE_ROOT" -t "$HOME" dotfiles`

The trailing `if [ "$0" = "$BASH_SOURCE" ]; then "$@"; fi` makes phases invokable directly: `./profile.sh prepare`.

Reference: [profiles/tmux/profile.sh](profiles/tmux/profile.sh).

## Configuration

`.env` (gitignored, copy from `.env.example`) drives behavior; auto-exported via `set -a` in `dotfiles-rc.sh`.

- `DOTFILES_PROFILES` — comma-separated profile list
- `HOMEBREW_NO_AUTO_UPDATE` — skip Homebrew auto-update during installs
- Profile-specific vars: prefix with profile name (e.g. `YABAI_*`)

Runtime exports (set by the framework, not `.env`):
- `DOTFILES_ROOT` — absolute path to repo root
- `DOTFILES_RC_LOADED` — single-load guard
- `PROFILE_ROOT` — set inside each `profile.sh`

## Stow conventions

Standard invocation uses `dotfiles` as the package name, `$PROFILE_ROOT` as the stow directory:

```bash
stow -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles      # install
stow -v -D -d "$PROFILE_ROOT" -t "$HOME" dotfiles    # uninstall
stow --adopt -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles  # import
```

Stow creates directory-level symlinks (folding), so edits under `profiles/{name}/dotfiles/` are reflected immediately in `$HOME` — no re-stow needed. Re-stow is only required when adding a new top-level path.

## Working in the repo

- `tmp/`, `build/`, and `.backups/` are gitignored. Per-profile `.gitignore` files exclude build outputs (e.g. `dotfiles/.config/tmux/plugins/`).
- `.env` is gitignored; `.env.example` is committed.
- There is no test suite, linter config, or CI in this repo.

## Project skills

When working on specific aspects of this repo, the following skills exist under `.agents/skills/`:
- `dotfiles-cli` — extending the CLI, library functions, completions, templates, framework code
- `dotfiles-profile` — creating or modifying profiles, stow layout, lifecycle conventions
