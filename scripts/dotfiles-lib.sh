# ---------------------------------------------------------------------------
# Profile management
# ---------------------------------------------------------------------------

dotfiles_discover_profiles() {
    local dir
    for dir in "$DOTFILES_ROOT"/profiles/*/; do
        [ -f "$dir/profile.sh" ] && basename "$dir"
    done
}

dotfiles_load_profile() {
    local profile_dir="$DOTFILES_ROOT/profiles/$1"
    [ -f "$profile_dir/profile.sh" ] || return 1
    (
        set +u
        source "$profile_dir/profile.sh" 2>/dev/null
        [ -z "$name" ] && return 1
        printf '%s\t%s\t%s\t%s' \
            "$name" "${description%%$'\n'*}" "${supported_os[*]}" "${depends[*]}"
    )
}

dotfiles_profile_status() {
    local profile_name="$1"
    local dotfiles_dir
    dotfiles_dir=$(realpath "$DOTFILES_ROOT/profiles/$profile_name/dotfiles" 2>/dev/null)
    [ -d "$dotfiles_dir" ] || { echo "no dotfiles"; return; }

    local _found=0 _missing=0
    _dotfiles_check_tree "$dotfiles_dir" "$HOME" "$dotfiles_dir"

    if [ "$_missing" -eq 0 ] && [ "$_found" -gt 0 ]; then
        echo "installed"
    elif [ "$_found" -eq 0 ]; then
        echo "not installed"
    else
        echo "partial"
    fi
}

_dotfiles_check_tree() {
    local src_dir="$1" target_dir="$2" root="$3"
    local entry
    local _old_nullglob=$(shopt -p nullglob 2>/dev/null)
    shopt -s nullglob
    for entry in "$src_dir"/.* "$src_dir"/*; do
        local base=$(basename "$entry")
        [[ "$base" == "." || "$base" == ".." ]] && continue
        local target="$target_dir/$base"

        if [ -L "$target" ]; then
            local resolved=$(realpath "$target" 2>/dev/null)
            if [[ "$resolved" == "$root"* ]]; then
                _found=$((_found + 1))
            else
                _missing=$((_missing + 1))
            fi
        elif [ -d "$entry" ] && [ -d "$target" ]; then
            _dotfiles_check_tree "$entry" "$target" "$root"
        else
            _missing=$((_missing + 1))
        fi
    done
    $_old_nullglob
}

dotfiles_status_detail() {
    local profile_name="$1"
    local profile_dir="$DOTFILES_ROOT/profiles/$profile_name"

    [ -f "$profile_dir/profile.sh" ] || { echo "Profile '$profile_name' not found" >&2; return 1; }

    local dotfiles_dir
    dotfiles_dir=$(realpath "$profile_dir/dotfiles" 2>/dev/null) || true

    local metadata
    metadata=$(dotfiles_load_profile "$profile_name") || true
    local status
    status=$(dotfiles_profile_status "$profile_name")

    local p_name p_desc p_os p_deps
    if [ -n "$metadata" ]; then
        IFS=$'\t' read -r p_name p_desc p_os p_deps <<< "$metadata"
    else
        p_name="$profile_name"; p_desc="(no metadata)"; p_os=""; p_deps=""
    fi

    echo "Profile: $p_name ($status)"
    [ -n "$p_desc" ] && echo "  Description: $p_desc"
    [ -n "$p_os" ] && echo "  OS: $p_os"
    [ -n "$p_deps" ] && echo "  Depends: $p_deps"
    echo ""

    if [ ! -d "$dotfiles_dir" ]; then
        echo "  No dotfiles/ directory"
        return
    fi

    _dotfiles_status_tree "$dotfiles_dir" "$HOME" "$dotfiles_dir" ""
}

_dotfiles_status_tree() {
    local src_dir="$1" target_dir="$2" root="$3" prefix="$4"
    local entry
    local _old_nullglob=$(shopt -p nullglob 2>/dev/null)
    shopt -s nullglob
    for entry in "$src_dir"/.* "$src_dir"/*; do
        local base=$(basename "$entry")
        [[ "$base" == "." || "$base" == ".." ]] && continue
        local target="$target_dir/$base"
        local rel_path="${prefix}${base}"

        if [ -L "$target" ]; then
            local resolved=$(realpath "$target" 2>/dev/null)
            if [[ "$resolved" == "$root"* ]]; then
                echo "  ✓ $rel_path"
            else
                echo "  ✗ $rel_path  (symlink → $resolved)"
            fi
        elif [ -d "$entry" ] && [ -d "$target" ]; then
            _dotfiles_status_tree "$entry" "$target" "$root" "${rel_path}/"
        elif [ -d "$entry" ]; then
            echo "  ✗ $rel_path/  (missing)"
        elif [ -e "$target" ]; then
            echo "  ✗ $rel_path  (real file, not a symlink)"
        else
            echo "  ✗ $rel_path  (missing)"
        fi
    done
    $_old_nullglob
}

dotfiles_current_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)  echo "linux" ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *)      echo "$(uname -s | tr '[:upper:]' '[:lower:]')" ;;
    esac
}

dotfiles_resolve_profiles() {
    local profiles=("$@")

    if [ ${#profiles[@]} -eq 0 ]; then
        mapfile -t profiles < <(dotfiles_discover_profiles)
    fi

    local current_os
    current_os=$(dotfiles_current_os)

    local -A meta_cache=()
    local filtered=()
    local profile
    for profile in "${profiles[@]}"; do
        local metadata
        metadata=$(dotfiles_load_profile "$profile") || continue
        meta_cache[$profile]="$metadata"

        IFS=$'\t' read -r _name _desc p_os _deps <<< "$metadata"
        if [ -n "$p_os" ]; then
            case " $p_os " in
                *" $current_os "*) ;;
                *) continue ;;
            esac
        fi
        filtered+=("$profile")
    done

    # Topological sort with dependency auto-inclusion
    local -A visited=()
    local -A in_stack=()
    local order=()

    _topo_visit() {
        local p="$1"
        [ "${visited[$p]:-}" = "1" ] && return 0
        if [ "${in_stack[$p]:-}" = "1" ]; then
            echo "Circular dependency: $p" >&2
            return 1
        fi
        in_stack[$p]=1

        local m="${meta_cache[$p]:-}"
        if [ -z "$m" ]; then
            m=$(dotfiles_load_profile "$p") || { echo "Unknown profile: $p" >&2; return 1; }
            meta_cache[$p]="$m"
        fi

        local _n _d _o deps
        IFS=$'\t' read -r _n _d _o deps <<< "$m"
        local dep
        for dep in $deps; do
            _topo_visit "$dep"
        done

        in_stack[$p]=0
        visited[$p]=1
        order+=("$p")
    }

    for profile in "${filtered[@]}"; do
        _topo_visit "$profile"
    done

    echo "${order[@]}"
}

dotfiles_create_profile() {
    local profile_name="$1"
    local description="${2:-}"
    local profile_dir="$DOTFILES_ROOT/profiles/$profile_name"
    local current_os
    current_os=$(dotfiles_current_os)

    [ -f "$profile_dir/profile.sh" ] && { echo "Profile '$profile_name' already exists" >&2; return 1; }

    mkdir -p "$profile_dir/dotfiles"
    sed -e "s/__NAME__/$profile_name/" \
        -e "s/__DESCRIPTION__/$description/" \
        -e "s/__OS__/$current_os/" \
        "$DOTFILES_ROOT/scripts/templates/profile.sh" > "$profile_dir/profile.sh"
    chmod +x "$profile_dir/profile.sh"
}

dotfiles_delete_profile() {
    local profile_name="$1"
    local profile_dir="$DOTFILES_ROOT/profiles/$profile_name"

    [ -d "$profile_dir" ] || { echo "Profile '$profile_name' does not exist" >&2; return 1; }

    local status
    status=$(dotfiles_profile_status "$profile_name")
    if [ "$status" = "installed" ] || [ "$status" = "partial" ]; then
        echo "Profile '$profile_name' is currently installed. Run 'dotfiles uninstall $profile_name' first." >&2
        return 1
    fi

    rm -rf "$profile_dir"
}

dotfiles_import() {
    local profile_name="$1"
    shift
    local profile_dir="$DOTFILES_ROOT/profiles/$profile_name"

    [ -d "$profile_dir" ] || { echo "Profile '$profile_name' does not exist. Run 'dotfiles create $profile_name' first." >&2; return 1; }

    local path
    for path in "$@"; do
        local expanded="${path/#\~/$HOME}"
        local abs=$(realpath "$expanded" 2>/dev/null) || { echo "Not found: $path" >&2; continue; }
        local rel="${abs#$HOME/}"

        mkdir -p "$profile_dir/dotfiles/$(dirname "$rel")"
        touch "$profile_dir/dotfiles/$rel"
    done

    stow --adopt -v -d "$profile_dir" -t "$HOME" dotfiles
}

dotfiles_run_phase() {
    local profile_name="$1"
    local phase="$2"
    local profile_dir="$DOTFILES_ROOT/profiles/$profile_name"

    [ -f "$profile_dir/profile.sh" ] || { echo "Profile '$profile_name' not found" >&2; return 1; }

    (
        source "$profile_dir/profile.sh"
        if declare -f "$phase" >/dev/null; then
            "$phase"
        else
            echo "Profile '$profile_name' has no '$phase' function" >&2
            return 1
        fi
    )
}

dotfiles_uninstall() {
    local profile_name="$1"
    local status
    status=$(dotfiles_profile_status "$profile_name")

    if [ "$status" = "not installed" ] || [ "$status" = "no dotfiles" ]; then
        echo "Profile '$profile_name' is not installed" >&2
        return 1
    fi

    dotfiles_run_phase "$profile_name" uninstall
}

dotfiles_install() {
    local profile_name="$1"
    local profile_dir="$DOTFILES_ROOT/profiles/$profile_name"

    [ -f "$profile_dir/profile.sh" ] || { echo "Profile '$profile_name' not found" >&2; return 1; }

    local status
    status=$(dotfiles_profile_status "$profile_name")
    if [ "$status" = "installed" ]; then
        echo "Profile '$profile_name' is already installed" >&2
        return 1
    fi

    echo "[$profile_name] prepare"
    dotfiles_run_phase "$profile_name" prepare

    echo "[$profile_name] package"
    dotfiles_run_phase "$profile_name" package

    echo "[$profile_name] install"
    dotfiles_run_phase "$profile_name" install
}

dotfiles_upgrade() {
    local profile_name="$1"
    local status
    status=$(dotfiles_profile_status "$profile_name")

    if [ "$status" = "not installed" ] || [ "$status" = "no dotfiles" ]; then
        echo "Profile '$profile_name' is not installed" >&2
        return 1
    fi

    echo "[$profile_name] upgrade"
    dotfiles_run_phase "$profile_name" upgrade
}
