# ---------------------------------------------------------------------------
# Profile management
# ---------------------------------------------------------------------------

dotfiles_profile_dir() {
    local name="$1"
    local dir
    for dir in "$DOTFILES_ROOT/profiles/$name" "$DOTFILES_ROOT/profiles/local/$name"; do
        [ -d "$dir" ] && { echo "$dir"; return 0; }
    done
    return 1
}

dotfiles_is_profile_dir() {
    local f="$1/profile.sh"
    [ -f "$f" ] \
        && grep -q '^name=' "$f" \
        && grep -q '^supported_os=' "$f"
}

dotfiles_discover_profiles() {
    local dir
    for dir in "$DOTFILES_ROOT"/profiles/*/ "$DOTFILES_ROOT"/profiles/local/*/; do
        [ -f "$dir/profile.sh" ] && basename "$dir"
    done
}

dotfiles_load_profile() {
    local profile_dir
    profile_dir=$(dotfiles_profile_dir "$1") || return 1
    [ -f "$profile_dir/profile.sh" ] || return 1
    (
        set +u
        source "$profile_dir/profile.sh" 2>/dev/null
        [ -z "$name" ] && return 1
        # Use ASCII Unit Separator (\x1f) — non-whitespace, won't collapse on
        # empty interior fields the way \t would (bash IFS-whitespace rule).
        printf '%s\x1f%s\x1f%s\x1f%s\x1f%s\x1f%s' \
            "$name" \
            "${description%%$'\n'*}" \
            "$(printf '%s\n' "${supported_os[@]}" | sort | paste -sd ' ' -)" \
            "${depends[*]}" \
            "${after[*]}" \
            "${before[*]}"
    )
}

dotfiles_profile_status() {
    local profile_name="$1"
    local profile_dir dotfiles_dir
    profile_dir=$(dotfiles_profile_dir "$profile_name") || { echo "no dotfiles"; return; }
    dotfiles_dir=$(realpath "$profile_dir/dotfiles" 2>/dev/null)
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
    local profile_dir
    profile_dir=$(dotfiles_profile_dir "$profile_name") || { echo "Profile '$profile_name' not found" >&2; return 1; }

    [ -f "$profile_dir/profile.sh" ] || { echo "Profile '$profile_name' not found" >&2; return 1; }

    local dotfiles_dir
    dotfiles_dir=$(realpath "$profile_dir/dotfiles" 2>/dev/null) || true

    local metadata
    metadata=$(dotfiles_load_profile "$profile_name") || true
    local status
    status=$(dotfiles_profile_status "$profile_name")

    local p_name p_desc p_os p_deps
    if [ -n "$metadata" ]; then
        IFS=$'\x1f' read -r p_name p_desc p_os p_deps _ _ <<< "$metadata"
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
    local -A in_set=()
    local install_set=()

    # Load metadata, filter by OS, and auto-pull depends transitively into install_set.
    _resolve_profiles() {
        local p="$1"
        [ "${in_set[$p]:-}" = "1" ] && return 0

        local m="${meta_cache[$p]:-}"
        if [ -z "$m" ]; then
            m=$(dotfiles_load_profile "$p") || { echo "Unknown profile: $p" >&2; return 1; }
            meta_cache[$p]="$m"
        fi

        local _n _d p_os deps _a _b
        IFS=$'\x1f' read -r _n _d p_os deps _a _b <<< "$m"
        if [ -n "$p_os" ]; then
            case " $p_os " in
                *" $current_os "*) ;;
                *) return 0 ;;
            esac
        fi

        in_set[$p]=1
        install_set+=("$p")

        local dep
        for dep in $deps; do
            _resolve_profiles "$dep" || return 1
        done
    }

    local profile
    for profile in "${profiles[@]}"; do
        _resolve_profiles "$profile" || return 1
    done

    # Collect predecessor edges within install_set:
    #   depends + after on P:  X precedes P  (if X in_set)
    #   before on P:           P precedes X  (if X in_set)
    local -A predecessors=()
    for profile in "${install_set[@]}"; do
        local _n _d _o deps after before
        IFS=$'\x1f' read -r _n _d _o deps after before <<< "${meta_cache[$profile]}"

        local x
        for x in $deps $after; do
            [ "${in_set[$x]:-}" = "1" ] || continue
            predecessors[$profile]="${predecessors[$profile]:-} $x"
        done
        for x in $before; do
            [ "${in_set[$x]:-}" = "1" ] || continue
            predecessors[$x]="${predecessors[$x]:-} $profile"
        done
    done

    # Topological sort over install_set using collected predecessor edges.
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

        local prev
        for prev in ${predecessors[$p]:-}; do
            _topo_visit "$prev" || return 1
        done

        in_stack[$p]=0
        visited[$p]=1
        order+=("$p")
    }

    for profile in "${install_set[@]}"; do
        _topo_visit "$profile" || return 1
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
    local profile_dir
    profile_dir=$(dotfiles_profile_dir "$profile_name") || { echo "Profile '$profile_name' does not exist" >&2; return 1; }

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
    local profile_dir
    profile_dir=$(dotfiles_profile_dir "$profile_name") || { echo "Profile '$profile_name' does not exist. Run 'dotfiles create $profile_name' first." >&2; return 1; }

    local path
    for path in "$@"; do
        local expanded="${path/#\~/$HOME}"
        local abs=$(realpath "$expanded" 2>/dev/null) || { echo "Not found: $path" >&2; continue; }
        local rel="${abs#$HOME/}"

        mkdir -p "$profile_dir/dotfiles/$(dirname "$rel")"

        if [ -d "$expanded" ] && [ ! -L "$expanded" ]; then
            [ -e "$profile_dir/dotfiles/$rel" ] && { echo "Already exists in profile: $rel" >&2; continue; }
            mv "$expanded" "$profile_dir/dotfiles/$rel"
        else
            touch "$profile_dir/dotfiles/$rel"
        fi
    done

    stow --adopt -v -d "$profile_dir" -t "$HOME" dotfiles
}

dotfiles_run_phase() {
    local profile_name="$1"
    local phase="$2"
    local profile_dir
    profile_dir=$(dotfiles_profile_dir "$profile_name") || { echo "Profile '$profile_name' not found" >&2; return 1; }

    [ -f "$profile_dir/profile.sh" ] || { echo "Profile '$profile_name' not found" >&2; return 1; }

    # Subprocess: profile.sh sets up its own env from rc.sh, dispatches via its
    # trailing `if [ "$0" = "$BASH_SOURCE" ]; then "$@"; fi` block.
    bash "$profile_dir/profile.sh" "$phase"
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

_dotfiles_stow_conflicts() {
    local profile_dir="$1"
    stow -n -v -d "$profile_dir" -t "$HOME" dotfiles 2>&1 \
        | grep 'existing target' \
        | sed 's/.*existing target //' \
        | sed 's/ since .*//'
}

_dotfiles_resolve_merge() {
    local home_file="$1"
    local dotfiles_file="$2"

    local tmp=$(mktemp)
    local base=$(mktemp)
    # Synthesize base from common lines for three-way merge without a real ancestor
    diff -u "$home_file" "$dotfiles_file" 2>/dev/null | grep '^ ' | sed 's/^ //' > "$base" || true
    cp "$home_file" "$tmp"
    git merge-file "$tmp" "$base" "$dotfiles_file" 2>/dev/null || true
    ${EDITOR:-vim} "$tmp"
    cp "$tmp" "$dotfiles_file"
    rm -f "$tmp" "$base"
}

_dotfiles_resolve_conflicts() {
    local profile_name="$1"
    local profile_dir
    profile_dir=$(dotfiles_profile_dir "$profile_name") || return 0
    local dotfiles_dir="$profile_dir/dotfiles"

    local conflicts
    conflicts=$(_dotfiles_stow_conflicts "$profile_dir" || true)
    [ -z "$conflicts" ] && return 0

    local backup_dir="$DOTFILES_ROOT/.backups/${profile_name}-$(date +%Y%m%d-%H%M%S)"
    local backed_up=0

    local rel_path
    while IFS= read -r rel_path; do
        [ -z "$rel_path" ] && continue
        local home_file="$HOME/$rel_path"
        local dotfiles_file="$dotfiles_dir/$rel_path"

        echo ""
        echo "CONFLICT: ~/$rel_path"

        local choice
        while true; do
            printf '  [d]iff  [b]ackup  [k]eep  [M]erge: '
            read -r choice </dev/tty
            choice="${choice:-m}"
            case "$choice" in
                d|D)
                    git diff --no-index -- "$dotfiles_file" "$home_file" || true
                    ;;
                b|B)
                    mkdir -p "$backup_dir/$(dirname "$rel_path")"
                    mv "$home_file" "$backup_dir/$rel_path"
                    backed_up=1
                    break
                    ;;
                k|K)
                    cp "$home_file" "$dotfiles_file"
                    rm "$home_file"
                    break
                    ;;
                m|M)
                    _dotfiles_resolve_merge "$home_file" "$dotfiles_file"
                    rm "$home_file"
                    break
                    ;;
                *)
                    echo "  Invalid choice. Use d/b/k/m (default: m)"
                    ;;
            esac
        done
    done <<< "$conflicts"

    if [ "$backed_up" -eq 1 ]; then
        echo ""
        echo "Backups saved to $backup_dir/"
    fi
}

dotfiles_install() {
    local profile_name="$1"
    local profile_dir
    profile_dir=$(dotfiles_profile_dir "$profile_name") || { echo "Profile '$profile_name' not found" >&2; return 1; }

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

    _dotfiles_resolve_conflicts "$profile_name"

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
