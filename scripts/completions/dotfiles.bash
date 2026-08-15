_dotfiles() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    local command="${COMP_WORDS[1]}"
    local commands="list create remove import status install package uninstall upgrade self completion"
    local profile_seen=0 i

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return
    fi

    case "$prev" in
        --package|--home)
            COMPREPLY=($(compgen -d -- "$cur"))
            return
            ;;
    esac

    for ((i=2; i<COMP_CWORD; i++)); do
        case "${COMP_WORDS[i]}" in
            --package|--home) ((i++)) ;;
            --) profile_seen=1 ;;
            -*) ;;
            *) profile_seen=1 ;;
        esac
    done

    case "$command" in
        create)
            ;;
        install|package|upgrade)
            local options=""
            [ "$profile_seen" -eq 1 ] || options="--package --home"
            COMPREPLY=($(compgen -W "$options $(dotfiles list 2>/dev/null | tail -n +2 | awk '{print $1}')" -- "$cur"))
            ;;
        remove|import|status|uninstall)
            COMPREPLY=($(compgen -W "$(dotfiles list 2>/dev/null | tail -n +2 | awk '{print $1}')" -- "$cur"))
            ;;
        self)
            COMPREPLY=($(compgen -W "update version" -- "$cur"))
            ;;
        completion)
            COMPREPLY=($(compgen -W "bash zsh" -- "$cur"))
            ;;
    esac
}
complete -F _dotfiles dotfiles
