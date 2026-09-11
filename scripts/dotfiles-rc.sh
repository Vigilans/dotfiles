if [ -z "${DOTFILES_ROOT:-}" ]; then
    export DOTFILES_ROOT=$(cd "$(dirname -- "${BASH_SOURCE:-$0}")/.." >/dev/null 2>&1 && pwd)
fi

# Guard prevents re-sourcing within the same shell. The guard is intentionally
# NOT exported, so each profile invocation gets a fresh read of all .env files
# from disk. A full install keeps its phases in that same shell.
if [ -z "${DOTFILES_RC_LOADED:-}" ]; then
    # Values already in the environment win over the .env channel, so a one-off
    # `VAR=value dotfiles ...` overrides a published one. PATH is exempt:
    # profile .env files extend it for downstream phases.
    _dotfiles_caller_env=$(export -p)

    # Load bootstrap .env (user's main config, gitignored)
    set -a
    [ -f "$DOTFILES_ROOT/.env" ] && source "$DOTFILES_ROOT/.env"
    set +a

    # Load each profile's .env (profile-contributed env vars / PATH for downstream)
    set -a
    for f in "$DOTFILES_ROOT"/profiles/*/.env "$DOTFILES_ROOT"/profiles/local/*/.env; do
        [ -f "$f" ] && source "$f"
    done
    set +a

    _dotfiles_env_path="$PATH"
    eval "$_dotfiles_caller_env"
    export PATH="$_dotfiles_env_path"
    unset _dotfiles_caller_env _dotfiles_env_path

    # Load helper library
    source "$DOTFILES_ROOT/scripts/dotfiles-lib.sh"

    # Git Bash (MSYS2) copies symlink targets by default; force native NTFS
    # symlinks so stow links and `ln -s` are real links visible to Windows apps.
    # nativestrict fails loudly instead of degrading to a copy.
    if [ "$(dotfiles_current_os)" = "windows" ]; then
        case "${MSYS:-}" in
            *winsymlinks*) ;;
            "") export MSYS="winsymlinks:nativestrict" ;;
            *)  export MSYS="$MSYS winsymlinks:nativestrict" ;;
        esac
    fi

    DOTFILES_RC_LOADED=1
fi
