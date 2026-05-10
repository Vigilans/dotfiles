#!/usr/bin/env bash
# Forward Claude Code hook events to a desktop toast.
#
# Events handled (each has a different payload shape):
#   Notification       — TUI-only idle/auth prompts; .message holds the text.
#   PermissionRequest  — IDE+TUI; .tool_name + .tool_input (varies by tool).
#   Stop               — every turn end; .last_assistant_message is the body.
#
# Title format:  [<tool_name>|Response · ]<cwd>[ · <host>]   (host only over SSH)
# Body format:   event-specific preview (see build_body).
#
# Dual-track dispatch (see "Pick mode" block):
#   vscode — $VSCODE_OSC_NOTIFIER_SOCK is published by the OSC notifier workspace
#            companion extension. Write raw OSC bytes to that sock; the workspace
#            ext forwards them to the UI ext, which parses and fires the toast
#            with windowId-stamped click-back. Notification is dropped because
#            Claude Code doesn't emit it in IDE mode anyway.
#   cli    — No bridge sock. Write OSC bytes directly to /dev/tty (with tmux DCS
#            passthrough wrapping if $TMUX). Only Notification is acted on, since
#            Claude Code already gates it on "user attention needed".
#            PermissionRequest and Stop would be too noisy without a focus filter,
#            so they're dropped.

set -eu

LOG="$HOME/.claude/notify.log"
log() {
    [ -n "${CLAUDE_NOTIFY_DEBUG:-}" ] || return 0
    printf '%s | %s\n' "$(date -Iseconds)" "$*" >> "$LOG"
}

# ---------- Parse hook payload ----------
input=$(cat)
event=$(jq -r '.hook_event_name // "Notification"' <<<"$input")
session=$(jq -r '.session_id // ""' <<<"$input")
cwd=$(jq -r '.cwd // ""' <<<"$input")
cwd_base=$(basename "$cwd" 2>/dev/null || echo "")
host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "")

log "fired event=$event session=$session cwd=$cwd host=$host"
log "input=$input"

# ---------- Pick mode and filter events ----------
if [ -n "${VSCODE_OSC_NOTIFIER_SOCK:-}" ] && { [ "${OS:-}" = "Windows_NT" ] || [ -S "$VSCODE_OSC_NOTIFIER_SOCK" ]; }; then
    mode=vscode
else
    mode=cli
fi
log "mode=$mode"

case "$mode:$event" in
    vscode:Notification)            log "drop (vscode mode)"; exit 0 ;;
    cli:PermissionRequest|cli:Stop) log "drop (cli mode)";    exit 0 ;;
esac

# ---------- Build title ----------
# Joins non-empty parts with " · ". Hostname is only added when reached over SSH
# (local sessions don't need to disambiguate hosts). Icon already brands the
# toast as Claude Code, so the name itself is omitted from the title.
build_title() {
    local parts=() tool joined
    case "$event" in
        PermissionRequest)
            tool=$(jq -r '.tool_name // ""' <<<"$input")
            [ -n "$tool" ] && parts+=("$tool")
            ;;
        Stop)
            parts+=("Response")
            ;;
    esac
    [ -n "$cwd_base" ] && parts+=("$cwd_base")
    [ -n "${SSH_CONNECTION:-}" ] && [ -n "$host" ] && parts+=("$host")

    if [ "${#parts[@]}" -eq 0 ]; then
        printf '%s' "Claude Code"
    else
        joined=$(printf '%s · ' "${parts[@]}")
        printf '%s' "${joined% · }"
    fi
}

# ---------- Build body ----------
# PermissionRequest's interesting field varies by tool, so we probe the most
# informative one. Stop's body is the model's last message — gives the user
# enough preview to judge whether to switch back without leaving their task.
build_body() {
    case "$event" in
        Notification)
            jq -r '.message // "Awaiting input"' <<<"$input"
            ;;
        PermissionRequest)
            jq -r '
                .tool_input as $i |
                if   $i.command       then $i.command
                elif $i.url           then $i.url + (if $i.prompt then ": " + $i.prompt else "" end)
                elif $i.query         then $i.query
                elif $i.questions and ($i.questions|length>0) then $i.questions[0].question
                elif $i.file_path     then $i.file_path
                elif $i.notebook_path then $i.notebook_path
                else "Permission requested" end
            ' <<<"$input"
            ;;
        Stop)
            jq -r '.last_assistant_message // "Response complete"' <<<"$input"
            ;;
        *)
            printf 'Event: %s' "$event"
            ;;
    esac
}

# ---------- Build payload ----------
# Wrap body, icon, and optional click_uri into the JSON payload shape that
# vscode-terminal-osc-notifier's parser recognizes. Branding (Claude Code icon)
# and click-back URI live here, not on the wire spec.
build_payload() {
    local body="$1" click_uri=""
    [ -n "$session" ] && click_uri="vscode://Anthropic.claude-code/open?session=$session"
    jq -nc \
        --arg body "$body" \
        --arg icon "ext:Anthropic.claude-code" \
        --arg click_uri "$click_uri" \
        '{body: $body, icon: $icon} + (if $click_uri != "" then {click_uri: $click_uri} else {} end)'
}

# ---------- Dispatch ----------
dispatch_via_vscode() {
    local title="$1" body="$2"
    local payload=$(build_payload "$body")
    log "branch=vscode sock=$VSCODE_OSC_NOTIFIER_SOCK payload=$payload"
    if printf '\e]777;notify;%s;%s\a' "$title" "$payload" | connect_to_sock "$VSCODE_OSC_NOTIFIER_SOCK" 2>>"$LOG"; then
        log "sock done"
    else
        log "sock write failed"
    fi
}

dispatch_via_osc() {
    local title="$1" body="$2"
    local payload=$(build_payload "$body")
    local osc=$(printf '\e]777;notify;%s;%s\a' "$title" "$payload")
    if [ -n "${TMUX:-}" ]; then
        # DCS tmux passthrough: double every inner ESC so tmux doesn't
        # terminate the frame early on the inner OSC's ST.
        osc=$(printf '\ePtmux;%s\e\\' "$(printf '%s' "$osc" | sed $'s/\x1b/\x1b\x1b/g')")
    fi
    log "branch=osc"
    printf '%s' "$osc" > /dev/tty 2>/dev/null \
        || log "osc tty write failed"
    log "osc done"
}

# Connect stdin to a Unix socket (macOS/Linux) or Win32 named pipe (Windows).
# Tries node first since net.connect() handles both endpoint types uniformly;
# falls back to perl on Unix or powershell.exe (5.1) on Windows — both are
# pre-installed on their respective platforms.
connect_to_sock() {
    local sock="$1"

    if command -v node >/dev/null 2>&1; then
        log "connect via node"
        MSYS_NO_PATHCONV=1 node -e \
            'process.stdin.pipe(require("net").createConnection(process.argv[1]))' \
            "$sock"
        return $?
    fi

    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            log "connect via powershell"
            local pipe_name="${sock##*\\}"
            MSYS_NO_PATHCONV=1 powershell.exe -NoProfile -Command "
                \$p = New-Object System.IO.Pipes.NamedPipeClientStream('.', '$pipe_name', [System.IO.Pipes.PipeDirection]::Out)
                \$p.Connect(2000)
                [Console]::OpenStandardInput().CopyTo(\$p)
                \$p.Close()
            "
            ;;
        *)
            if command -v perl >/dev/null 2>&1; then
                log "connect via perl"
                perl -e 'use IO::Socket::UNIX;
                         my $s = IO::Socket::UNIX->new($ARGV[0]) || die;
                         binmode STDIN; binmode $s;
                         print $s $_ while sysread(STDIN, $_, 4096)' "$sock"
            else
                log "connect: no usable tool"
                return 1
            fi
            ;;
    esac
}

# ---------- Main ----------
title=$(build_title)
message=$(build_body)

# Truncate to ~120 chars so the toast doesn't get clipped mid-character.
if [ "${#message}" -gt 120 ]; then
    message="${message:0:117}…"
fi
log "title=$title message=$message"

if [ "$mode" = vscode ]; then
    dispatch_via_vscode "$title" "$message"
else
    dispatch_via_osc "$title" "$message"
fi
