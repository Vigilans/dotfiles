#!/usr/bin/env bash

export PROFILE_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$PROFILE_ROOT"
if [ -z "$DOTFILES_ROOT" ]; then
    export DOTFILES_ROOT=$(realpath "$PROFILE_ROOT/../..")
fi
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

name=shell
description="Shell configuration (zsh on macos/linux, pwsh planned for windows) — plugin manager and CLI tooling"
supported_os=(linux macos windows)
depends=()
after=()
before=()

BOOTSTRAP="$PROFILE_ROOT/dotfiles/.config/shell/bootstrap.sh"

prepare() {
    git -C "$DOTFILES_ROOT" submodule update --init --recursive \
        -- "$PROFILE_ROOT/dotfiles/.config/shell"
    bash "$BOOTSTRAP" prepare
}

package() {
    :
}

install() {
    stow -v -d "$PROFILE_ROOT" -t "$HOME" dotfiles
    mkdir -p ~/.config/shell/commands/local ~/.config/shell/profiles/local
    bash "$BOOTSTRAP" install
}

upgrade() {
    local sub="$PROFILE_ROOT/dotfiles/.config/shell"
    local current locked
    current=$(git -C "$sub" rev-parse HEAD)
    locked=$(git -C "$DOTFILES_ROOT" ls-tree HEAD "$sub" | awk '{print $3}')

    # Skip sync if submodule is ahead of the superproject lock —
    # otherwise `submodule update --checkout` would silently rewind
    # commits the user pulled but didn't bump in the superproject yet.
    if [ "$current" != "$locked" ] && \
       git -C "$sub" merge-base --is-ancestor "$locked" "$current"; then
        echo "[shell] submodule is ahead of dotfiles lock — skipping sync." >&2
        echo "[shell] If this is intentional, bump the dotfiles superproject:" >&2
        echo "[shell]     cd \"\$DOTFILES_ROOT\" && git add \"$sub\" && git commit -m 'Bump shell'" >&2
    else
        git -C "$DOTFILES_ROOT" submodule update --init --recursive -- "$sub"
    fi

    bash "$BOOTSTRAP" upgrade
}

uninstall() {
    stow -v -D -d "$PROFILE_ROOT" -t "$HOME" dotfiles
    # Leave $HOME/.zshrc etc. alone — they are user copies that may carry
    # installer/local edits. Remove manually if a full purge is wanted.
}

if [ "$0" = "$BASH_SOURCE" ]; then
    "$@"
fi
