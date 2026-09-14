---
name: dotfiles-profile
description: Use this skill when creating or modifying profiles under `profiles/`, changing `profile.sh` lifecycle or metadata, laying out files for Stow, selecting custom dotfiles stow package or home roots, debugging Stow conflicts and directory folding, or deciding profile boundaries. Prefer `dotfiles create NAME` over manual scaffolding.
---

# Dotfiles profile authoring

A profile is a self-contained unit that bundles configuration files plus an installation lifecycle. It owns everything specific to one app (or one cohesive group of apps) and can be installed, upgraded, and uninstalled independently.

## Creating a profile

Use the CLI rather than manual scaffolding:

```bash
dotfiles create myapp "One-line description"
```

This generates `profiles/myapp/profile.sh` from the template with metadata pre-filled (name, description, current OS). Populate the canonical dotfiles stow package source at `profiles/myapp/dotfiles/` with files mirroring the target home layout.

To import existing dotfiles from `$HOME` into a profile:

```bash
dotfiles import myapp ~/.config/myapp/config.toml
```

This moves the file into the profile's `dotfiles/` tree and replaces it with a stow symlink.

## Profile structure

```
profiles/{name}/
├── profile.sh              # Lifecycle script (executable)
├── .env                    # Optional: env vars exported during install
├── dotfiles/               # Canonical dotfiles stow package source
│   └── .config/{app}/...
├── build/                  # Downloaded artifacts (gitignored)
└── .gitignore              # Exclude build outputs, plugin dirs, etc.
```

## profile.sh lifecycle

```bash
export PROFILE_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$PROFILE_ROOT"
if [ -z "$DOTFILES_ROOT" ]; then
    export DOTFILES_ROOT=$(realpath "$PROFILE_ROOT/../..")
fi
export DOTFILES_PACKAGE="${DOTFILES_PACKAGE:-$PROFILE_ROOT/dotfiles}"
export DOTFILES_HOME="${DOTFILES_HOME:-$HOME}"
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

name=myapp
description="What this profile installs"
supported_os=(macos)    # linux, macos, windows; auto-filled by `dotfiles create`
depends=()              # required profiles, auto-pulled into profiles to install if missing
after=()                # order current profile after these during install
before=()               # order current profile before these during install

# Install upstream packages/binaries
prepare() { ... }

# Generate files in the selected dotfiles stow package
package() { ... }

# Stow the selected dotfiles stow package into DOTFILES_HOME
install() {
    stow -v -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
}

# Re-prepare and update runtime components
upgrade() { ... }

# Unstow the selected dotfiles stow package
uninstall() {
    stow -v -D -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
}

if [ "$0" = "$BASH_SOURCE" ]; then
    set -e; "$@"
}
```

The trailing conditional makes phases directly invokable while enabling `errexit` only for direct execution. Framework sourcing does not inherit it.

### Phase semantics

| Phase | Purpose | Idempotent? |
|---|---|---|
| `prepare` | Install system dependencies (brew, apt, pacman; winget via `_dotfiles_winget_install` on Windows) | Yes (package managers handle this) |
| `package` | Generate files in `DOTFILES_PACKAGE`: build artifacts, clone plugins, render `.j2` templates | Yes |
| `install` | Resolve conflicts, then stow the selected dotfiles stow package and run setup | Yes |
| `upgrade` | Rebuild and redeploy the selected dotfiles stow package, then update runtime components | Yes |
| `uninstall` | Stop services + `stow -D` to unlink | Yes |

## Dotfiles stow package paths

`$PROFILE_ROOT/dotfiles` is always the canonical source. `DOTFILES_PACKAGE` is the assembled dotfiles stow package used by generation, status, conflict resolution, Stow, and unstow. `DOTFILES_HOME` is the Stow destination.

Precedence is CLI option, environment variable, then profile default:

```text
dotfiles package [--package DIR] [--home DIR] PROFILE
dotfiles install [--package DIR] [--home DIR] PROFILE...
dotfiles upgrade [--package DIR] [--home DIR] PROFILE...
```

When `DOTFILES_PACKAGE` is selected through the environment or `--package`, `dotfiles package` overlays canonical static files into that external dotfiles stow package. Install and upgrade use it as-is; run `dotfiles package` first after static source changes. A selected external dotfiles stow package accepts one profile and install does not add its dependencies; `--home` may apply to multiple profiles.

The external overlay copies files and symlinks recursively, excludes `.git`, and does not delete unmanaged destination files.

Render generated files into `DOTFILES_PACKAGE`. The Codex template reads runtime-managed configuration from `DOTFILES_HOME` first and falls back to the dotfiles stow package destination.

## Stow conventions

### Standard invocation

```bash
# Install the selected dotfiles stow package
stow -v -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .

# Uninstall
stow -v -D -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .

# Import existing files into profile
stow --adopt -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles
```

### Directory folding

Stow links at the highest directory level it can:

- `$DOTFILES_HOME/.config/myapp/` doesn't exist → Stow may fold it into one symlink pointing into `DOTFILES_PACKAGE`.
- `$DOTFILES_HOME/.config/myapp/` exists as a real directory → Stow descends and links individual files inside.

Folded directories are why new files inside an already-stowed directory may appear in `DOTFILES_HOME` without re-running Stow.

### When to re-stow

- Added a new top-level path in the dotfiles stow package → re-stow needed
- Added files inside an already-folded directory → no action needed
- Renamed/moved files → `stow -R` (restow) to clean old links

### Conflict resolution

When `dotfiles install` detects files in `DOTFILES_HOME` that conflict with the selected dotfiles stow package, it prompts per file before the profile's `install()` runs:

- `[d]iff` — preview differences with `git diff --no-index` (repeatable)
- `[b]ackup` — move HOME file to `$DOTFILES_ROOT/.backups/<profile>-<timestamp>/`
- `[k]eep` — copy HOME content into dotfiles dir, remove HOME file (original dotfiles version preserved in git)
- `[M]erge` (default) — three-way merge using a synthetic base (common lines extracted via `diff -u`), produces conflict markers, opens `$EDITOR` for resolution, writes result to dotfiles dir

After resolution, stow runs without conflicts. Manual troubleshooting is only needed for edge cases outside the installer flow (e.g. stale symlinks from another profile).

## Profile placement

Profiles can live in three locations, all discoverable by `dotfiles list` and the lifecycle commands:

- **`profiles/<name>/`** — tracked in the main repo. Default for `dotfiles create`.
- **`profiles/local/<name>/`** — gitignored. Use for machine-only profiles you don't want committed.
- **External clone** — set `DOTFILES_EXTRA_PROFILES="<name>=<git-url>"` in `.env` and `bootstrap.sh` clones into `profiles/<name>/`. The cloned `.git/` self-protects from the parent repo. Useful for managing secrets in a separate **private** repo without the URL ever entering the public dotfiles tree.

If the cloned external repo isn't already a framework profile (no `name=` and `supported_os=` in its `profile.sh`), bootstrap wraps its contents under `dotfiles/` and auto-generates a `profile.sh` from the standard template.

## Profile categories

- **System** — OS-level settings (`macos`, `linux`)
- **Application** — single app config (`shell`, `tmux`)
- **Composite** — multiple related apps as a unit (`yabai` = yabai + skhd + sketchybar)

## Profile isolation

- Self-contained: every file lives under its own profile directory
- Independent: install/uninstall of one profile must not break others
- No reaching into sibling profiles' directories
- Declare genuine dependencies via `depends=(...)`

## Reference

- [profiles/README.md](../../../profiles/README.md) — full reference
- [profiles/tmux/profile.sh](../../../profiles/tmux/profile.sh) — clean single-app example with TPM plugin management
- [profiles/yabai/profile.sh](../../../profiles/yabai/profile.sh) — composite profile with services, fonts, and a `package()` phase
- [scripts/templates/profile.sh](../../../scripts/templates/profile.sh) — the template used by `dotfiles create`
