#!/usr/bin/env bash

export PROFILE_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$PROFILE_ROOT"
if [ -z "$DOTFILES_ROOT" ]; then
    export DOTFILES_ROOT=$(realpath "$PROFILE_ROOT/../..")
fi
export DOTFILES_PACKAGE="${DOTFILES_PACKAGE:-$PROFILE_ROOT/dotfiles}"
export DOTFILES_HOME="${DOTFILES_HOME:-$HOME}"
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

name=shell
description="Shell configuration (zsh on macos/linux, pwsh planned for windows) — plugin manager and CLI tooling"
supported_os=(linux macos windows)
depends=()
after=()
before=()

BOOTSTRAP="$PROFILE_ROOT/dotfiles/.config/shell/bootstrap.sh"

prepare() {
    dotfiles_submodule_checkout "$PROFILE_ROOT/dotfiles/.config/shell"
    bash "$BOOTSTRAP" prepare
}

package() {
    :
}

install() {
    stow -v -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
    mkdir -p ~/.config/shell/commands/local ~/.config/shell/profiles/local
    bash "$BOOTSTRAP" install
}

upgrade() {
    dotfiles_submodule_checkout "$PROFILE_ROOT/dotfiles/.config/shell"
    bash "$BOOTSTRAP" upgrade
}

uninstall() {
    stow -v -D -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
    # Leave $HOME/.zshrc etc. alone — they are user copies that may carry
    # installer/local edits. Remove manually if a full purge is wanted.
}

if [ "$0" = "$BASH_SOURCE" ]; then
    set -e; "$@"
fi
