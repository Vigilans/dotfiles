---
name: dotfiles-profile
description: Use this skill when creating a new profile under `profiles/`, modifying an existing profile's `profile.sh` lifecycle, adjusting profile metadata (name/description/supported_os/depends), laying out files under `dotfiles/` for stow, or deciding how a config path should be structured so stow links it cleanly. Also triggers when debugging stow conflicts, understanding directory folding behavior, or deciding whether something should be a standalone profile versus part of an existing one. Prefer `dotfiles create <name>` over manually scaffolding.
---

# Dotfiles profile authoring

A profile is a self-contained unit that bundles configuration files plus an installation lifecycle. It owns everything specific to one app (or one cohesive group of apps) and can be installed, upgraded, and uninstalled independently.

## Creating a profile

Use the CLI rather than manual scaffolding:

```bash
dotfiles create myapp "One-line description"
```

This generates `profiles/myapp/profile.sh` from the template with metadata pre-filled (name, description, current OS). Then populate `profiles/myapp/dotfiles/` with files mirroring their `$HOME` layout.

To import existing dotfiles from `$HOME` into a profile:

```bash
dotfiles import myapp ~/.config/myapp/config.toml
```

This moves the file into the profile's `dotfiles/` tree and replaces it with a stow symlink.

## Profile structure

```
profiles/{name}/
├── profile.sh              # Lifecycle script (executable)
├── dotfiles/               # Mirrors $HOME — stowed into ~ on install
│   └── .config/{app}/...
├── build/                  # Downloaded artifacts (gitignored)
└── .gitignore              # Exclude build outputs, plugin dirs, etc.
```

## profile.sh lifecycle

```bash
name=myapp
description="What this profile installs"
supported_os=(macos)    # auto-filled by `dotfiles create`
depends=()              # other profile names this requires

# Install upstream packages/binaries
prepare() { ... }

# Assemble files in dotfiles/ before stowing (clone plugins, build artifacts)
package() { ... }

# Stow dotfiles into $HOME and run post-install setup
install() {
    stow -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles
}

# Re-prepare and update runtime components
upgrade() { ... }

# Unstow dotfiles from $HOME and clean up
uninstall() {
    stow -v -D -d "$PROFILE_ROOT" -t "$HOME" dotfiles
}
```

The trailing `if [ "$0" = "$BASH_SOURCE" ]; then "$@"; fi` makes phases invokable directly: `./profile.sh prepare`.

### Phase semantics

| Phase | Purpose | Idempotent? |
|---|---|---|
| `prepare` | Install system dependencies (brew, apt, pacman) | Yes (package managers handle this) |
| `package` | Populate `dotfiles/` from `build/` artifacts, clone plugins | Yes (skip if exists) |
| `install` | CLI resolves stow conflicts first (d/b/k/m prompt), then profile's `stow` + start services | Re-run safe, stow is idempotent || `upgrade` | Re-prepare + update plugins + reload configs | Yes |
| `uninstall` | Stop services + `stow -D` to unlink | Yes |

## Stow conventions

### Standard invocation

```bash
# Install — package name is "dotfiles", stow dir is profile root
stow -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles

# Uninstall
stow -v -D -d "$PROFILE_ROOT" -t "$HOME" dotfiles

# Import existing files into profile
stow --adopt -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles
```

### Directory folding

Stow links at the highest directory level it can:

- `~/.config/myapp/` doesn't exist → stow creates one symlink: `~/.config/myapp → <repo>/profiles/myapp/dotfiles/.config/myapp`
- `~/.config/myapp/` exists as real dir → stow descends and links individual files inside

Folded directories are why new files added inside an already-stowed directory appear in `$HOME` automatically without re-running stow.

### When to re-stow

- Added a new top-level path in `dotfiles/` → re-stow needed
- Added files inside an already-folded directory → no action needed
- Renamed/moved files → `stow -R` (restow) to clean old links

### Conflict resolution

When `dotfiles install` detects existing files that would conflict with stow, it prompts per file before the profile's `install()` runs:

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

- [profiles/tmux/profile.sh](../../../profiles/tmux/profile.sh) — clean single-app example with TPM plugin management
- [profiles/yabai/profile.sh](../../../profiles/yabai/profile.sh) — composite profile with services, fonts, and `package` step
- [scripts/templates/profile.sh](../../../scripts/templates/profile.sh) — the template used by `dotfiles create`
