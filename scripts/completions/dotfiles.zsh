_dotfiles() {
    local commands="list create remove import status install package uninstall upgrade self completion"
    local profiles
    local profile_seen=0 i
    profiles=$(dotfiles list 2>/dev/null | tail -n +2 | awk '{print $1}')
    if [[ "$words[CURRENT-1]" = --package || "$words[CURRENT-1]" = --home ]]; then
        _directories
        return
    fi

    for ((i=3; i<CURRENT; i++)); do
        case "$words[i]" in
            --package|--home) ((i++)) ;;
            --) profile_seen=1 ;;
            -*) ;;
            *) profile_seen=1 ;;
        esac
    done

    case "$words[2]" in
        install|package|upgrade)
            if (( profile_seen )); then
                _values 'profile' ${(f)profiles}
            else
                _values 'option or profile' --package --home ${(f)profiles}
            fi
            ;;
        remove|import|status|uninstall)
            [[ -n "$profiles" ]] && _values 'profile' ${(f)profiles} ;;
        self)
            _values 'subcommand' update version ;;
        completion)
            _values 'shell' bash zsh ;;
        *)
            _values 'command' ${(s: :)commands} ;;
    esac
}
compdef _dotfiles dotfiles
