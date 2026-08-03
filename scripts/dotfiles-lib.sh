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
        name="" description="" supported_os=() depends=() after=() before=()
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

    if [ "$_found" -eq 0 ] && [ "$_missing" -eq 0 ]; then
        echo "empty"
    elif [ "$_missing" -eq 0 ] && [ "$_found" -gt 0 ]; then
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
        profiles=()
        while IFS= read -r _p; do
            profiles+=("$_p")
        done < <(dotfiles_discover_profiles)
    fi

    local current_os
    current_os=$(dotfiles_current_os)

    local _in_set=""
    local install_set=()

    _resolve_profiles() {
        local p="$1"
        case " $_in_set " in *" $p "*) return 0 ;; esac

        local m
        m=$(dotfiles_load_profile "$p") || { echo "Unknown profile: $p" >&2; return 1; }

        local _n _d p_os deps _a _b
        IFS=$'\x1f' read -r _n _d p_os deps _a _b <<< "$m"
        if [ -n "$p_os" ]; then
            case " $p_os " in
                *" $current_os "*) ;;
                *) return 0 ;;
            esac
        fi

        _in_set="$_in_set $p"
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

    # Collect predecessor edges within install_set.
    # Each line in _edges is "target predecessor" meaning predecessor precedes target.
    local _edges=""
    for profile in "${install_set[@]}"; do
        local m _n _d _o deps after before
        m=$(dotfiles_load_profile "$profile")
        IFS=$'\x1f' read -r _n _d _o deps after before <<< "$m"

        local x
        for x in $deps $after; do
            case " $_in_set " in *" $x "*) ;; *) continue ;; esac
            _edges="${_edges}${profile} ${x}
"
        done
        for x in $before; do
            case " $_in_set " in *" $x "*) ;; *) continue ;; esac
            _edges="${_edges}${x} ${profile}
"
        done
    done

    # Topological sort via DFS over collected edges.
    local _visited="" _in_stack=""
    local order=()

    _topo_visit() {
        local p="$1"
        case " $_visited " in *" $p "*) return 0 ;; esac
        case " $_in_stack " in *" $p "*) echo "Circular dependency: $p" >&2; return 1 ;; esac
        _in_stack="$_in_stack $p"

        local _preds="" _t _x
        while IFS=' ' read -r _t _x; do
            [ -z "$_t" ] && continue
            case "$_t" in "$p") _preds="$_preds $_x" ;; esac
        done <<< "$_edges"

        local prev
        for prev in $_preds; do
            _topo_visit "$prev" || return 1
        done

        _in_stack="${_in_stack/ $p/}"
        _visited="$_visited $p"
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

    _dotfiles_ensure_stow || return 1

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

    if [ "$status" = "not installed" ] || [ "$status" = "no dotfiles" ] || [ "$status" = "empty" ]; then
        echo "Profile '$profile_name' is not installed" >&2
        return 1
    fi

    _dotfiles_ensure_stow || return 1

    dotfiles_run_phase "$profile_name" uninstall
}

_dotfiles_ensure_stow() {
    command -v stow &>/dev/null && return 0
    echo "Installing GNU Stow..."
    if command -v brew &>/dev/null; then
        brew install stow
    elif command -v apt &>/dev/null; then
        sudo apt install -y stow
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm stow
    else
        echo "ERROR: cannot install stow — no supported package manager found" >&2
        return 1
    fi
}

_dotfiles_stow_conflicts() {
    local profile_dir="$1"
    stow -n -v -d "$profile_dir" -t "$HOME" dotfiles 2>&1 \
        | grep 'existing target' \
        | sed -E 's/.*existing target ([^:]*: )?//' \
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

    _dotfiles_ensure_stow || return 1

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

dotfiles_ensure_gh() {
    command -v gh &>/dev/null && return 0
    echo "Installing GitHub CLI..."
    if command -v brew &>/dev/null; then
        brew install gh
    elif command -v apt &>/dev/null; then
        sudo apt install -y gh
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y gh
    elif command -v yum &>/dev/null; then
        sudo yum install -y gh
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm github-cli
    else
        echo "ERROR: cannot install gh — no supported package manager found" >&2
        return 1
    fi
}

# Check out a profile's submodule at the commit the superproject locks. The
# tracked lock decides the version, so an upstream change reaches other machines
# by being bumped here.
#
# Skipped when the submodule carries commits the lock doesn't contain:
# `submodule update` checks out unconditionally and would detach away from them
# without warning.
dotfiles_submodule_checkout() {
    local sub="$1"
    local state current locked
    state=$(git -C "$DOTFILES_ROOT" submodule status -- "$sub")

    # "-": submodule not checked out — nothing to compare against the lock yet.
    if [ "${state:0:1}" != "-" ]; then
        # No lock to check out while the gitlink is staged but not committed.
        locked=$(git -C "$DOTFILES_ROOT" ls-tree HEAD "$sub" | awk '{print $3}')
        [ -n "$locked" ] || return 0

        current=$(git -C "$sub" rev-parse HEAD)
        if [ "$current" != "$locked" ] && \
           ! git -C "$sub" merge-base --is-ancestor "$current" "$locked"; then
            echo "[$name] submodule has commits the dotfiles lock doesn't carry — skipping checkout." >&2
            echo "[$name] If this is intentional, bump the superproject:" >&2
            echo "[$name]     cd \"\$DOTFILES_ROOT\" && git add \"$sub\" && git commit -m 'Bump $name'" >&2
            return 0
        fi
    fi

    git -C "$DOTFILES_ROOT" submodule update --init --recursive -- "$sub"
}

# Render Nunjucks templates from <src> tree to <dst> tree, mirroring structure
# and stripping the .j2 suffix. Non-.j2 files are ignored. Context is
# process.env — vars published via the .env channel are accessible as
# {{ VAR_NAME }} in templates.
#
# nunjucks is loaded ephemerally via npx (cached in ~/.npm/_npx after first
# call). npx adds the install dir to PATH but not to node's require resolution,
# so we extract _npx/<hash>/node_modules from PATH and pass it explicitly to
# require.resolve. This avoids committing package.json/node_modules to the
# repo and avoids npm install -g.
render_templates_nunjucks() {
    local src="$1" dst="$2"
    [ -d "$src" ] || return 0
    src="$src" dst="$dst" npx --yes -p nunjucks@^3 -p smol-toml@^1 node -e "$(cat <<'JS'
        const path = require('path');
        const fs = require('fs');
        const npxBin = process.env.PATH.split(path.delimiter).find(p => /[\/\\]_npx[\/\\].+[\/\\]node_modules[\/\\]\.bin$/.test(p));
        const resolveFromNpx = name => require(require.resolve(name, { paths: [npxBin.replace(/[\/\\]\.bin$/, '')] }));
        const nunjucks = resolveFromNpx('nunjucks');
        const toml = resolveFromNpx('smol-toml');
        const { src, dst } = process.env;
        const env = nunjucks.configure(src, { autoescape: false, throwOnUndefined: true });
        env.addGlobal('fs', {
            readFile(filename) {
                return fs.existsSync(filename) ? fs.readFileSync(filename, 'utf8') : null;
            }
        });
        env.addGlobal('fail', message => { throw new Error(message); });
        env.addGlobal('toml', {
            parse: toml.parse,
            stringify: toml.stringify,
            merge(target, key, value) {
                return { ...target, [key]: value };
            }
        });
        env.addGlobal('json', {
            parse: JSON.parse,
            merge(target, key, value) {
                return { ...target, [key]: value };
            }
        });
        (function walk(rel) {
            for (const e of fs.readdirSync(path.join(src, rel), { withFileTypes: true })) {
                const r = path.join(rel, e.name);
                if (e.isDirectory()) walk(r);
                else if (e.name.endsWith('.j2')) {
                    const out = path.join(dst, r.replace(/\.j2$/, ''));
                    const profile = path.dirname(src);
                    console.log('RENDER: ' + path.join(path.relative(profile, src), r) + ' => ' + path.relative(profile, out));
                    fs.mkdirSync(path.dirname(out), { recursive: true });
                    fs.writeFileSync(out, env.render(r, { ...process.env, os: { environ: process.env } }));
                }
            }
        })('');
JS
)"
}
