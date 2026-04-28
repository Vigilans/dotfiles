#!/usr/bin/env bash

set -euo pipefail

export DOTFILES_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$DOTFILES_ROOT"
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

# Install profiles
if [ -n "${DOTFILES_PROFILES:-}" ]; then
    echo "OS: $(dotfiles_current_os)"
    echo ""

    IFS=',' read -ra _profiles <<< "$DOTFILES_PROFILES"
    sorted=$(dotfiles_resolve_profiles "${_profiles[@]}")
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
mkdir -p ~/.local/bin
ln -snf "$DOTFILES_ROOT/scripts/dotfiles-cli.sh" ~/.local/bin/dotfiles

echo "dotfiles CLI installed to ~/.local/bin/dotfiles"
echo ""
echo "To enable shell completion, add to your shell rc:"
echo '  eval "$(dotfiles completion bash)"   # bash'
echo '  eval "$(dotfiles completion zsh)"    # zsh'
