_dotfiles() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
        dotfiles)
            COMPREPLY=($(compgen -W "list create remove import status install package uninstall upgrade self completion" -- "$cur"))
            ;;
        create)
            ;;
        remove|import|status|install|package|uninstall|upgrade)
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
