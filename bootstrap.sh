#!/usr/bin/env bash

set -euo pipefail

export DOTFILES_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$DOTFILES_ROOT"
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

_use_ssh_submodule=0
for arg in "$@"; do
    case "$arg" in
        --use-ssh-submodule) _use_ssh_submodule=1 ;;
        *) echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# Keep tracked HTTPS URLs portable while using SSH credentials locally.
if [ "$_use_ssh_submodule" -eq 1 ]; then
    while read -r _key _url; do
        case "$_url" in
            https://github.com/*)
                _submodule="${_key#submodule.}"
                _submodule="${_submodule%.url}"
                git config --local "submodule.$_submodule.url" "git@github.com:${_url#https://github.com/}"
                ;;
        esac
    done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.url$')
fi

# Clone external profiles
if [ -n "${DOTFILES_EXTRA_PROFILES:-}" ]; then
    IFS=',' read -ra _extras <<< "${DOTFILES_EXTRA_PROFILES//[[:space:]]/}"
    _extra_names=()
    for entry in "${_extras[@]}"; do
        IFS='=' read -r _name _url <<< "$entry"
        _extra_names+=("$_name")
        _target="$DOTFILES_ROOT/profiles/$_name"
        if [ -d "$_target" ]; then
            echo "[$_name] already exists, skipping clone"
        else
            if [ "$_use_ssh_submodule" -eq 1 ]; then
                case "$_url" in
                    https://github.com/*) _url="git@github.com:${_url#https://github.com/}" ;;
                esac
            fi
            echo "[$_name] cloning from $_url"
            git clone "$_url" "$_target"
            if ! dotfiles_is_profile_dir "$_target"; then
                mv "$_target" "$_target.dotfiles"
                mkdir "$_target"
                mv "$_target.dotfiles" "$_target/dotfiles"
                dotfiles_create_profile "$_name" "External profile (auto-generated)"
            fi
        fi
    done
    # When DOTFILES_PROFILES="*", leave it alone — cloned externals will be
    # picked up by dotfiles_discover_profiles.
    if [ "${DOTFILES_PROFILES:-}" != "*" ]; then
        DOTFILES_PROFILES="${DOTFILES_PROFILES:+$DOTFILES_PROFILES,}$(IFS=,; echo "${_extra_names[*]}")"
    fi
fi

# Pre-create well-known user directories to prevent stow from folding them
# into symlinks when a profile is the first to stow under these paths.
mkdir -p ~/.config ~/.local/bin ~/.local/share ~/.cache

# Install profiles
if [ -n "${DOTFILES_PROFILES:-}" ]; then
    echo "OS: $(dotfiles_current_os)"
    echo ""

    if [ "$DOTFILES_PROFILES" = "*" ]; then
        # "*" means all profiles compatible with the current OS
        sorted=$(dotfiles_resolve_profiles)
    else
        IFS=',' read -ra _profiles <<< "$DOTFILES_PROFILES"
        sorted=$(dotfiles_resolve_profiles "${_profiles[@]}")
    fi
    if [ -n "$sorted" ]; then
        echo "Install order: $sorted"
        echo ""

        for profile in $sorted; do
            status=$(dotfiles_profile_status "$profile")
            if [ "$status" = "installed" ]; then
                echo "[$profile] already installed, skipping"
            else
                dotfiles_install "$profile"
            fi
            echo ""
        done
    else
        echo "No profiles to install for this OS."
        echo ""
    fi
fi

# Install CLI
ln -snf "$DOTFILES_ROOT/scripts/dotfiles-cli.sh" ~/.local/bin/dotfiles

echo "dotfiles CLI installed to ~/.local/bin/dotfiles"
echo ""
echo "To enable shell completion, add to your shell rc:"
echo '  eval "$(dotfiles completion bash)"   # bash'
echo '  eval "$(dotfiles completion zsh)"    # zsh'
