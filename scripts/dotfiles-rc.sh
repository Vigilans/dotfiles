if [ -z "${DOTFILES_ROOT:-}" ]; then
    export DOTFILES_ROOT=$(cd "$(dirname -- "${BASH_SOURCE:-$0}")/.." >/dev/null 2>&1 && pwd)
fi

# Ensure rc loaded and only loaded once
if [ -z "${DOTFILES_RC_LOADED:-}" ]; then
    # Load environment variables
    set -a
    [ -f "$DOTFILES_ROOT/.env" ] && source "$DOTFILES_ROOT/.env"
    set +a

    # Load helper library functions
    source "$DOTFILES_ROOT/scripts/dotfiles-lib.sh"

    export DOTFILES_RC_LOADED=1
fi
