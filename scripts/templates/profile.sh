#!/usr/bin/env bash

export PROFILE_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$PROFILE_ROOT"
if [ -z "$DOTFILES_ROOT" ]; then
    export DOTFILES_ROOT=$(realpath "$PROFILE_ROOT/../..")
fi
export DOTFILES_PACKAGE="${DOTFILES_PACKAGE:-$PROFILE_ROOT/dotfiles}"
export DOTFILES_HOME="${DOTFILES_HOME:-$HOME}"
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

# Profile metadata
name=__NAME__
description="__DESCRIPTION__"
supported_os=(__OS__)  # e.g. (macos linux windows)
depends=()             # required profiles, auto-pulled into profiles to install if missing
after=()               # order current profile after these during install
before=()              # order current profile before these during install

# Install upstream packages/binaries (brew, apt, github-release, etc.)
prepare() {
    :
}

# Assemble files in dotfiles/ before stowing (clone plugins, build artifacts, etc.)
package() {
    :
}

# Stow dotfiles into $DOTFILES_HOME and run post-install setup
install() {
    stow -v -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
}

# Re-prepare and update runtime components
upgrade() {
    prepare
    package
    stow -v -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
}

# Unstow dotfiles from $DOTFILES_HOME and clean up
uninstall() {
    stow -v -D -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
}

if [ "$0" = "$BASH_SOURCE" ]; then
    set -e; "$@"
fi
