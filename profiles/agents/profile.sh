#!/usr/bin/env bash

export PROFILE_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$PROFILE_ROOT"
if [ -z "$DOTFILES_ROOT" ]; then
    export DOTFILES_ROOT=$(realpath "$PROFILE_ROOT/../..")
fi
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

# Profile metadata
name=agents
description="Coding agent configs (rules, skills) for Claude Code, Codex, opencode, and other AGENTS.md-aware tools"
supported_os=(linux macos windows)
depends=(shell)             # required profiles, auto-pulled into profiles to install if missing
after=()                    # order current profile after these during install
before=()                   # order current profile before these during install

# Install upstream packages/binaries (brew, apt, github-release, etc.)
prepare() {
    if ! command -v jq &>/dev/null || ! command -v node &>/dev/null; then
        if command -v brew &>/dev/null; then
            brew install jq node
        elif command -v apt &>/dev/null; then
            sudo apt install -y jq nodejs
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y jq nodejs
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq nodejs
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm jq nodejs
        elif command -v apk &>/dev/null; then
            sudo apk add -q jq nodejs npm
        elif command -v winget &>/dev/null; then
            winget install -e --id jqlang.jq --id OpenJS.NodeJS.LTS
        else
            echo "[agents] No supported package manager found" >&2
            return 1
        fi
    fi
}

# Assemble files in dotfiles/ before stowing (clone plugins, build artifacts, etc.)
package() {
    render_templates_nunjucks "$PROFILE_ROOT/templates" "$PROFILE_ROOT/dotfiles"
}

# Stow dotfiles into $HOME and run post-install setup
install() {
    # Skills link runs first so $HOME/.agents/skills and each target's parent
    # exist as real dirs before stow — otherwise stow would fold those paths
    # into symlinks pointing at the repo, redirecting npx skills' real-dir
    # writes and Claude Code's runtime state into the dotfiles tree.
    _install_skills_link "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.config/opencode/skills"
    stow -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles
    _install_vendor_skills
    _install_claude_plugins
}

# Re-prepare and update runtime components
upgrade() {
    prepare
    npx -y skills update -g -y
    _install_claude_plugins
}

# Unstow dotfiles from $HOME and clean up
uninstall() {
    stow -v -D -d "$PROFILE_ROOT" -t "$HOME" dotfiles
}

# Symlink each agent's skills dir to the shared ~/.agents/skills, so all agents
# see both vendor (real dirs from npx skills) and own (stowed) skills without
# each maintaining its own copy.
_install_skills_link() {
    local source="$1"
    shift
    mkdir -p "$source"
    local target relative
    for target in "$@"; do
        relative=$(realpath -s --relative-to="$(dirname "$target")" "$source")

        [ -L "$target" ] && [ "$(readlink "$target")" = "$relative" ] && continue

        if [ -d "$target" ] && [ ! -L "$target" ] && [ -n "$(ls -A "$target")" ]; then
            echo "[agents] $target is a non-empty directory."
            read -rp "  Move contents into $source/ and replace with symlink? [Y/n] " ans
            case "$ans" in
                [nN]*) echo "[agents] aborted; resolve $target manually" >&2; return 1 ;;
                *)
                    mkdir -p "$source"
                    ( shopt -s dotglob; mv "$target"/* "$source/" )
                    ;;
            esac
        fi

        mkdir -p "$(dirname "$target")"
        rm -rf "$target"
        ln -s "$relative" "$target"
    done
}

# Restore vendor skills declared in ~/.agents/.skill-lock.json that aren't
# already on disk. Idempotent: existing skill folders are skipped.
_install_vendor_skills() {
    local lock="$HOME/.agents/.skill-lock.json"
    [ -f "$lock" ] || return 0

    local skill source
    while IFS=$'\t' read -r skill source; do
        [ -d "$HOME/.agents/skills/$skill" ] && continue
        echo "[agents] installing skill $skill from $source"
        npx -y skills add -g -y "$source" -s "$skill"
    done < <(jq -r '.skills | to_entries[] | "\(.key)\t\(.value.source)"' "$lock")
}

# Install Claude Code plugins enumerated in ~/.claude/settings.json's
# enabledPlugins block. Settings.json is the declarative source of truth;
# Claude Code's installed_plugins.json is just a state log we don't track.
# Idempotent: already-installed plugins are skipped.
_install_claude_plugins() {
    local settings="$HOME/.claude/settings.json"
    [ -f "$settings" ] || return 0
    command -v claude &>/dev/null || {
        echo "[agents] claude CLI not on PATH, skipping plugin install" >&2
        return 0
    }

    local registry="$HOME/.claude/plugins/installed_plugins.json"
    local plugin
    while IFS= read -r plugin; do
        [ -z "$plugin" ] && continue
        if [ -f "$registry" ] && jq -e --arg p "$plugin" '.plugins[$p] // empty | length > 0' "$registry" >/dev/null; then
            continue
        fi
        echo "[agents] installing plugin $plugin"
        claude plugin install "$plugin" || echo "[agents] failed to install $plugin" >&2
    done < <(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$settings")
}

if [ "$0" = "$BASH_SOURCE" ]; then
    "$@"
fi
