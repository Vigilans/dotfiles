#!/usr/bin/env bash

export PROFILE_ROOT="$( cd "$( dirname -- "${BASH_SOURCE:-$0}" )" >/dev/null 2>&1 && pwd )"; cd "$PROFILE_ROOT"
if [ -z "$DOTFILES_ROOT" ]; then
    export DOTFILES_ROOT=$(realpath "$PROFILE_ROOT/../..")
fi
export DOTFILES_PACKAGE="${DOTFILES_PACKAGE:-$PROFILE_ROOT/dotfiles}"
export DOTFILES_HOME="${DOTFILES_HOME:-$HOME}"
source "$DOTFILES_ROOT/scripts/dotfiles-rc.sh"

# Profile metadata
name=agents
description="Coding agent configs (rules, skills) for Claude Code, Codex, opencode, and other AGENTS.md-aware tools"
supported_os=(linux macos windows)
depends=(shell)             # required profiles, auto-pulled into profiles to install if missing
after=()                    # order current profile after these during install
before=()                   # order current profile before these during install

# Install upstream packages/binaries (brew, apt, github-release, etc.)
prepare() {
    dotfiles_submodule_checkout "$PROFILE_ROOT/dotfiles/.local/share/agents"
    dotfiles_ensure_node || return 1

    if ! command -v jq &>/dev/null \
        || ! command -v rg &>/dev/null; then
        if command -v brew &>/dev/null; then
            brew install jq ripgrep
        elif command -v apt &>/dev/null; then
            sudo apt install -y jq ripgrep
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y jq ripgrep
        elif command -v yum &>/dev/null; then
            sudo yum install -y jq ripgrep
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm jq ripgrep
        elif command -v apk &>/dev/null; then
            sudo apk add -q jq ripgrep
        elif command -v winget &>/dev/null; then
            _dotfiles_winget_install jqlang.jq
            _dotfiles_winget_install BurntSushi.ripgrep.MSVC
        else
            echo "[agents] No supported package manager found" >&2
            return 1
        fi
    fi

    _install_codex
}

# Assemble files in dotfiles/ before stowing (clone plugins, build artifacts, etc.)
package() {
    # Codex requires every catalog entry to carry a full ModelInfo, including a
    # ~20KB base_instructions prompt. Take it from the installed binary so the
    # prompt matches the runtime, and fall back to upstream when Codex is absent.
    mkdir -p "$PROFILE_ROOT/build"
    if ! codex debug models --bundled > "$PROFILE_ROOT/build/codex-models.json" 2>/dev/null; then
        curl -fsSL https://raw.githubusercontent.com/openai/codex/main/codex-rs/models-manager/models.json \
            -o "$PROFILE_ROOT/build/codex-models.json" || {
            echo "[agents] failed to obtain a Codex model catalog prototype" >&2
            return 1
        }
    fi

    render_templates_nunjucks "$PROFILE_ROOT/templates" "$DOTFILES_PACKAGE"
}

# Stow dotfiles into $DOTFILES_HOME and run post-install setup
install() {
    # Skills link runs first so $HOME/.agents/skills and each target's parent
    # exist as real dirs before stow — otherwise stow would fold those paths
    # into symlinks pointing at the repo, redirecting npx skills' real-dir
    # writes and Claude Code's runtime state into the dotfiles tree.
    _install_skills_link "$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.config/opencode/skills"
    mkdir -p "$DOTFILES_HOME/.codex"
    stow -v -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
    _install_vendor_skills
    _install_claude_code install &&
        _sync_claude_plugins install
    command -v codex &>/dev/null &&
        _sync_codex_plugins
}

# Re-prepare and update runtime components
upgrade() {
    prepare
    package
    stow -v -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" . || return 1
    _install_vendor_skills
    npx -y skills update -g -y
    _install_claude_code upgrade &&
        _sync_claude_plugins upgrade
    command -v codex &>/dev/null &&
        _sync_codex_plugins
}

# Unstow dotfiles from $DOTFILES_HOME and clean up
uninstall() {
    stow -v -D -d "$DOTFILES_PACKAGE" -t "$DOTFILES_HOME" .
}

# Symlink each agent's skills dir to the shared ~/.agents/skills, so all agents
# see both vendor (real dirs from npx skills) and own (stowed) skills without
# each maintaining its own copy.
_install_skills_link() {
    local source="$1"
    shift
    mkdir -p "$source"
    local target relative
    for target in "$@"; do
        relative=$(realpath -sm --relative-to="$(dirname "$target")" "$source")

        [ -L "$target" ] && [ "$(readlink "$target")" = "$relative" ] && continue

        if [ -d "$target" ] && [ ! -L "$target" ] && [ -n "$(ls -A "$target")" ]; then
            echo "[agents] $target is a non-empty directory."
            read -rp "  Move contents into $source/ and replace with symlink? [Y/n] " ans
            case "$ans" in
                [nN]*) echo "[agents] aborted; resolve $target manually" >&2; return 1 ;;
                *)
                    mkdir -p "$source"
                    ( shopt -s dotglob; mv "$target"/* "$source/" )
                    ;;
            esac
        fi

        mkdir -p "$(dirname "$target")"
        rm -rf "$target"
        ln -s "$relative" "$target"
    done
}

# Restore vendor skills declared in ~/.agents/.skill-lock.json that aren't
# already on disk. Idempotent: existing skill folders are skipped.
_install_vendor_skills() {
    local lock="$HOME/.agents/.skill-lock.json"
    [ -f "$lock" ] || return 0

    local skill source
    while IFS=$'\t' read -r skill source; do
        [ -d "$HOME/.agents/skills/$skill" ] && continue
        echo "[agents] installing skill $skill from $source"
        npx -y skills add -g -y "$source" -s "$skill" </dev/null
    done < <(jq -r '.skills | to_entries[] | "\(.key)\t\(.value.source)"' "$lock")
}

_install_codex() {
    case "$(dotfiles_current_os)" in
        linux|macos)
            (
                set -o pipefail
                curl -fsSL https://chatgpt.com/codex/install.sh |
                    CODEX_NON_INTERACTIVE=1 \
                    PATH="${CODEX_INSTALL_DIR:-$HOME/.local/bin}:$PATH" sh
            )
            ;;
        windows)
            # The installer unpacks with `tar`; it must resolve to Windows'
            # bsdtar, since Git's GNU tar reads `C:\...` as a remote host.
            CODEX_NON_INTERACTIVE=1 PATH="$(cygpath -u "$SYSTEMROOT")/System32:$PATH" \
                powershell.exe -NoProfile -Command 'irm https://chatgpt.com/codex/install.ps1 | iex' || return 1
            export PATH="${CODEX_INSTALL_DIR:-$(cygpath -u "$LOCALAPPDATA")/Programs/OpenAI/Codex/bin}:$PATH"
            ;;
    esac
}

_install_claude_code() {
    local mode="${1:-install}"
    local use_clawgod="${AGENTS_CLAWGOD:-}"
    local clawgod_dir="${CLAWGOD_DIR:-$HOME/.local/share/clawgod}"
    local clawgod_cli="$clawgod_dir/cli.cjs"

    case "$use_clawgod" in
        0|1) ;;
        "")
            if [ -f "$clawgod_cli" ]; then
                use_clawgod=1
            elif [ "$mode" = "install" ]; then
                echo "[agents] ClawGod installs a patched Claude Code runtime with:"
                echo "  - custom model aliases"
                echo "  - Agent model overrides from PreToolUse hooks"
                echo "  - model preservation when SendMessage resumes an Agent"
                echo "  - other capabilities selected by its patch configuration"
                echo "[agents] It replaces the claude launcher and preserves an existing original when available."
                read -rp "  Install ClawGod? [y/N] " answer
                case "$answer" in
                    [yY]*) use_clawgod=1 ;;
                    *) use_clawgod=0 ;;
                esac
            else
                use_clawgod=0
            fi
            ;;
        *)
            echo "[agents] AGENTS_CLAWGOD must be 0 or 1" >&2
            return 1
            ;;
    esac

    if [ "$use_clawgod" = "1" ]; then
        case "$(dotfiles_current_os)" in
            linux|macos)
                (
                    set -o pipefail
                    curl -fsSL https://raw.githubusercontent.com/Vigilans/clawgod/dev/install.sh | CLAWGOD_DIR="$clawgod_dir" bash
                ) || return 1
                ;;
            windows)
                # Behind a proxy the installer unpacks with `tar`; same bsdtar
                # requirement as _install_codex.
                CLAWGOD_DIR="$clawgod_dir" PATH="$(cygpath -u "$SYSTEMROOT")/System32:$PATH" \
                    powershell.exe -NoProfile -Command 'irm https://raw.githubusercontent.com/Vigilans/clawgod/dev/install.ps1 | iex' || return 1
                ;;
        esac
        _configure_vscode_clawgod || return 1
    elif ! command -v claude &>/dev/null; then
        case "$(dotfiles_current_os)" in
            linux|macos)
                (
                    set -o pipefail
                    curl -fsSL https://claude.ai/install.sh | bash
                ) || return 1
                ;;
            windows)
                powershell.exe -NoProfile -Command 'irm https://claude.ai/install.ps1 | iex' || return 1
                ;;
        esac
        export PATH="$HOME/.local/bin:$PATH"
    elif [ "$mode" = "upgrade" ]; then
        claude update || return 1
    fi

    command -v claude &>/dev/null
}

# Sync plugins and their marketplaces against ~/.claude/settings.json.
# Settings.json is the declarative source of truth; installed_plugins.json and
# known_marketplaces.json are Claude Code's state logs we read but don't track.
#   mode=install: install missing plugins, skip already-installed.
#   mode=upgrade: install missing, `plugin update` already-installed.
# Marketplace sync runs first either way: unregistered → add (clones source);
# already-registered → update (pulls catalog). One network call per marketplace.
_sync_claude_plugins() {
    local mode="${1:-install}"
    local settings="$HOME/.claude/settings.json"
    [ -f "$settings" ] || return 0
    command -v claude &>/dev/null || {
        echo "[agents] claude CLI not on PATH, skipping plugin sync" >&2
        return 0
    }

    local known="$HOME/.claude/plugins/known_marketplaces.json"
    local name src_type src_ref
    while IFS=$'\t' read -r name src_type src_ref; do
        [ -z "$name" ] && continue
        if [ -f "$known" ] && jq -e --arg n "$name" 'has($n)' "$known" >/dev/null; then
            echo "[agents] updating marketplace $name"
            claude plugin marketplace update "$name" || { echo "[agents] failed to update marketplace $name" >&2; return 1; }
            continue
        fi
        case "$src_type" in
            github|directory)
                echo "[agents] adding marketplace $name ($src_ref)"
                claude plugin marketplace add "$src_ref" || { echo "[agents] failed to add marketplace $name" >&2; return 1; }
                ;;
            *)
                echo "[agents] marketplace $name has unsupported source type '$src_type', skipping" >&2
                ;;
        esac
    done < <(jq -r '.extraKnownMarketplaces // {} | to_entries[] | "\(.key)\t\(.value.source.source)\t\(.value.source.repo // .value.source.path // "")"' "$settings")

    local registry="$HOME/.claude/plugins/installed_plugins.json"
    local rc=0
    local plugin enabled
    while IFS=$'\t' read -r plugin enabled; do
        [ -z "$plugin" ] && continue
        if [ -f "$registry" ] && jq -e --arg p "$plugin" '.plugins[$p] // empty | length > 0' "$registry" >/dev/null; then
            [ "$mode" = "upgrade" ] || continue
            echo "[agents] updating plugin $plugin"
            claude plugin update "$plugin" || { echo "[agents] failed to update $plugin" >&2; rc=1; }
        elif [ "$enabled" = "true" ]; then
            echo "[agents] installing plugin $plugin"
            claude plugin install "$plugin" || { echo "[agents] failed to install $plugin" >&2; rc=1; }
        else
            echo "[agents] installing disabled plugin $plugin"
            claude plugin install "$plugin" || { echo "[agents] failed to install $plugin" >&2; rc=1; }
            claude plugin disable "$plugin" || { echo "[agents] failed to disable $plugin" >&2; rc=1; }
        fi
    done < <(jq -r '.enabledPlugins // {} | to_entries[] | "\(.key)\t\(.value)"' "$settings")

    return "$rc"
}

_sync_codex_plugins() {
    config="$HOME/.codex/config.toml" npx --yes -p smol-toml@^1 node <<'JS'
        const path = require('path');
        const fs = require('fs');
        const { execFileSync, spawn } = require('node:child_process');
        const { createInterface } = require('node:readline');

        const npxBin = process.env.PATH.split(path.delimiter).find(p => /[\/\\]_npx[\/\\].+[\/\\]node_modules[\/\\]\.bin$/.test(p));
        const toml = require(require.resolve('smol-toml', { paths: [npxBin.replace(/[\/\\]\.bin$/, '')] }));
        const run = (...args) => execFileSync('codex', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
        let server;

        (async () => {
            const config = toml.parse(fs.readFileSync(process.env.config, 'utf8'));
            const enabled = new Set(Object.entries(config.plugins || {})
                .filter(([, plugin]) => plugin.enabled).map(([id]) => id));

            run('plugin', 'marketplace', 'upgrade', '--json');
            const installed = new Set(JSON.parse(run('plugin', 'list', '--json'))
                .installed.map(plugin => plugin.pluginId));
            for (const plugin of enabled) {
                if (installed.has(plugin)) continue;
                console.log(`[agents] installing Codex plugin ${plugin}`);
                run('plugin', 'add', plugin, '--json');
            }

            server = spawn('codex', ['app-server', '--stdio'], { stdio: ['pipe', 'pipe', 'inherit'] });
            const messages = createInterface({ input: server.stdout })[Symbol.asyncIterator]();
            const write = message => server.stdin.write(JSON.stringify(message) + '\n');
            let requestId = 0;

            async function rpc(method, params) {
                const id = requestId++;
                write({ method, id, params });
                for (;;) {
                    const { value, done } = await messages.next();
                    if (done) throw new Error('Codex app-server exited');
                    const message = JSON.parse(value);
                    if (message.id !== id) continue;
                    if (message.error) throw new Error(message.error.message);
                    return message.result;
                }
            }

            await rpc('initialize', { clientInfo: { name: 'dotfiles', title: 'dotfiles', version: '1' } });
            write({ method: 'initialized', params: {} });

            const result = await rpc('hooks/list', { cwds: [process.env.PROFILE_ROOT] });
            const trust = Object.fromEntries(result.data.flatMap(entry => entry.hooks)
                .filter(hook => hook.source === 'plugin' && enabled.has(hook.pluginId) &&
                    hook.trustStatus !== 'trusted')
                .map(hook => [hook.key, { trusted_hash: hook.currentHash }]));

            if (Object.keys(trust).length) {
                await rpc('config/batchWrite', {
                    edits: [{ keyPath: 'hooks.state', value: trust, mergeStrategy: 'upsert' }],
                    reloadUserConfig: true
                });
            }

            server.stdin.end();
        })().catch(error => { console.error(`[agents] ${error.message}`); server?.kill(); process.exitCode = 1; });
JS
}

# Point existing local and Remote SSH VS Code settings at the PATH launcher.
_configure_vscode_clawgod() {
    local settings=("$HOME/.vscode-server/data/Machine/settings.json")
    case "$(dotfiles_current_os)" in
        linux) settings+=("${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json") ;;
        macos) settings+=("$HOME/Library/Application Support/Code/User/settings.json") ;;
        windows) settings+=("$(cygpath -u "$APPDATA")/Code/User/settings.json") ;;
    esac

    local existing=() file
    for file in "${settings[@]}"; do
        [ -f "$file" ] && existing+=("$file")
    done
    [ ${#existing[@]} -gt 0 ] || return 0

    npx --yes -p jsonc-parser@^3 node - "${existing[@]}" <<'JS'
        const path = require('path');
        const fs = require('fs');
        const npxBin = process.env.PATH.split(path.delimiter).find(p => /[\/\\]_npx[\/\\].+[\/\\]node_modules[\/\\]\.bin$/.test(p));
        const jsonc = require(require.resolve('jsonc-parser', { paths: [npxBin.replace(/[\/\\]\.bin$/, '')] }));

        for (const file of process.argv.slice(2)) {
            const text = fs.readFileSync(file, 'utf8');
            const source = text.trim() ? text : '{}';
            const errors = [];
            const root = jsonc.parseTree(source, errors, { allowTrailingComma: true });
            if (errors.length || root?.type !== 'object') {
                throw new Error(`${file} is not a valid JSONC object`);
            }

            const setting = ['claudeCode.claudeProcessWrapper'];
            const current = jsonc.findNodeAtLocation(root, setting);
            if (current && jsonc.getNodeValue(current) === 'claude') continue;

            const eol = text.includes('\r\n') ? '\r\n' : '\n';
            const indent = text.match(/^[ \t]+(?=")/m)?.[0];
            const edits = jsonc.modify(source, setting, 'claude', {
                formattingOptions: {
                    insertSpaces: !indent?.includes('\t'),
                    tabSize: indent?.length || 4,
                    eol
                }
            });
            if (edits.length) {
                fs.writeFileSync(file, jsonc.applyEdits(source, edits));
                console.log(`[agents] configured ClawGod for VS Code in ${file}`);
            }
        }
JS
}

if [ "$0" = "$BASH_SOURCE" ]; then
    set -e; "$@"
fi
