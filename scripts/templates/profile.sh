#!/usr/bin/env bash

export PROFILE_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$PROFILE_ROOT"
if [ -z "$DOTFILES_ROOT" ]; then
    export DOTFILES_ROOT=$(realpath "$PROFILE_ROOT/../..")
fi
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

# Profile metadata
name=__NAME__
description="__DESCRIPTION__"
supported_os=(__OS__)  # e.g. (macos linux windows)
depends=()

# Install upstream packages/binaries (brew, apt, github-release, etc.)
prepare() {
    :
}

# Assemble files in dotfiles/ before stowing (clone plugins, build artifacts, etc.)
package() {
    :
}

# Stow dotfiles into $HOME and run post-install setup
install() {
    stow -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles
}

# Re-prepare and update runtime components
upgrade() {
    prepare
}

# Unstow dotfiles from $HOME and clean up
uninstall() {
    stow -v -D -d "$PROFILE_ROOT" -t "$HOME" dotfiles
}

if [ "$0" = "$BASH_SOURCE" ]; then
    "$@"
fi
