_dotfiles() {
    local commands="list create remove import status install uninstall upgrade self completion"
    local profiles
    profiles=$(dotfiles list 2>/dev/null | tail -n +2 | awk '{print $1}')

    case "$words[2]" in
        remove|import|status|install|uninstall|upgrade)
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
