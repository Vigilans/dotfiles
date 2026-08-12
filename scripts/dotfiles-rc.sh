if [ -z "${DOTFILES_ROOT:-}" ]; then
    export DOTFILES_ROOT=$(cd "$(dirname -- "${BASH_SOURCE:-$0}")/.." >/dev/null 2>&1 && pwd)
fi

# Guard prevents re-sourcing within the same shell. The guard is intentionally
# NOT exported, so each profile invocation gets a fresh read of all .env files
# from disk. A full install keeps its phases in that same shell.
if [ -z "${DOTFILES_RC_LOADED:-}" ]; then
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

    # Load helper library
    source "$DOTFILES_ROOT/scripts/dotfiles-lib.sh"

    DOTFILES_RC_LOADED=1
fi
