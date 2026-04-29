#!/usr/bin/env bash
# dotfiles CLI

set -euo pipefail

export DOTFILES_ROOT="$(cd "$(dirname -- "$(realpath "${BASH_SOURCE:-$0}")")/.." && pwd)"
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

cmd_list() {
    printf '%-15s %-15s %-20s %s\n' "PROFILE" "STATUS" "OS" "DESCRIPTION"

    local profile
    for profile in $(dotfiles_discover_profiles); do
        local metadata
        metadata=$(dotfiles_load_profile "$profile") || continue
        local status
        status=$(dotfiles_profile_status "$profile")

        IFS=$'\t' read -r p_name p_desc p_os p_deps <<< "$metadata"
        printf '%-15s %-15s %-20s %s\n' "$p_name" "$status" "$p_os" "$p_desc"
    done
}

cmd_create() {
    [ -z "${1:-}" ] && { echo "Usage: dotfiles create <profile> [description]" >&2; exit 2; }
    dotfiles_create_profile "$1" "${2:-}"
    echo "Created profile '$1' at profiles/$1/"
}

cmd_import() {
    [ -z "${1:-}" ] || [ -z "${2:-}" ] && { echo "Usage: dotfiles import <profile> <path>..." >&2; exit 2; }
    local profile="$1"; shift
    dotfiles_import "$profile" "$@"
}

cmd_remove() {
    [ -z "${1:-}" ] && { echo "Usage: dotfiles remove <profile>" >&2; exit 2; }
    dotfiles_delete_profile "$1"
    echo "Removed profile '$1'"
}

cmd_install() {
    [ -z "${1:-}" ] && { echo "Usage: dotfiles install <profile>..." >&2; exit 2; }
    for profile in "$@"; do
        dotfiles_install "$profile"
    done
}

cmd_uninstall() {
    [ -z "${1:-}" ] && { echo "Usage: dotfiles uninstall <profile>..." >&2; exit 2; }
    for profile in "$@"; do
        dotfiles_uninstall "$profile"
    done
}

cmd_upgrade() {
    [ -z "${1:-}" ] && { echo "Usage: dotfiles upgrade <profile>..." >&2; exit 2; }
    for profile in "$@"; do
        dotfiles_upgrade "$profile"
    done
}

cmd_status() {
    [ -z "${1:-}" ] && { echo "Usage: dotfiles status <profile>..." >&2; exit 2; }
    for profile in "$@"; do
        dotfiles_status_detail "$profile"
    done
}

cmd_self() {
    case "${1:-}" in
        update)
            echo "Updating $DOTFILES_ROOT..."
            git -C "$DOTFILES_ROOT" pull
            git -C "$DOTFILES_ROOT" submodule update --recursive
            ;;
        version)
            git -C "$DOTFILES_ROOT" log -1 --format='%h %s (%ar)'
            ;;
        ""|-h|--help)
            echo "Usage: dotfiles self <subcommand>"
            echo ""
            echo "Subcommands:"
            echo "  update    Pull latest dotfiles repository (and initialized submodules)"
            echo "  version   Show framework commit SHA, message, and age"
            ;;
        *)
            echo "dotfiles self: unknown subcommand '$1'" >&2
            exit 2
            ;;
    esac
}

case "${1:-}" in
    list)       shift; cmd_list "$@" ;;
    create)     shift; cmd_create "$@" ;;
    remove)     shift; cmd_remove "$@" ;;
    import)     shift; cmd_import "$@" ;;
    status)     shift; cmd_status "$@" ;;
    install)    shift; cmd_install "$@" ;;
    uninstall)  shift; cmd_uninstall "$@" ;;
    upgrade)    shift; cmd_upgrade "$@" ;;
    self)       shift; cmd_self "$@" ;;
    completion)
        case "${2:-}" in
            bash) cat "$DOTFILES_ROOT/scripts/completions/dotfiles.bash" ;;
            zsh)  cat "$DOTFILES_ROOT/scripts/completions/dotfiles.zsh" ;;
            *)    echo "Usage: dotfiles completion <bash|zsh>" >&2; exit 2 ;;
        esac
        ;;
    -h|--help|"")
        echo "Usage: dotfiles <command> [args]"
        echo ""
        echo "Profile management:"
        echo "  list        List profiles and their status"
        echo "  create      Create a new profile from template"
        echo "  remove      Remove a profile from the repository"
        echo "  import      Import dotfiles into a profile (stow --adopt)"
        echo ""
        echo "Installation:"
        echo "  status      Show detailed install status for a profile"
        echo "  install     Install a profile (prepare + package + stow)"
        echo "  uninstall   Uninstall a profile (unstow from \$HOME)"
        echo "  upgrade     Upgrade an installed profile"
        echo ""
        echo "Self management:"
        echo "  self update Pull latest dotfiles repository"
        echo "  self version Show framework commit SHA, message, and age"
        echo ""
        echo "Shell integration:"
        echo "  completion  Output shell completion script"
        echo ""
        echo "Run 'dotfiles <command> --help' for more information."
        ;;
    *)
        echo "dotfiles: unknown command '$1'" >&2
        echo "Run 'dotfiles --help' for usage." >&2
        exit 2
        ;;
esac
