#!/bin/bash
# =============================================================================
# hook_permission_telegram.sh - Smart filtering + optional Telegram for Claude Code
# =============================================================================
# PreToolUse hook with intelligent risk classification.
#
# Flow:
#   1. Safe operations   -> auto-approve instantly (no prompt)
#   2. Dangerous operations -> depends on mode:
#      - Terminal only (default): passthrough to Claude's normal y/n prompt
#      - Terminal + Telegram: terminal prompt + background Telegram escalation
#      - Telegram only: blocking Telegram with buttons (classic v0.3 behavior)
#
# Telegram mode is controlled by a flag file:
#   Enable:  touch /tmp/claude_telegram_active
#   Disable: rm -f /tmp/claude_telegram_active
#
# When NOT in tmux + Telegram enabled: blocking Telegram with reminders
#   at 60s, 120s, and 60s before timeout. Relaunch button on expiry.
# When in tmux + Telegram enabled: terminal prompt first, Telegram after 120s,
#   tmux send-keys bridges the response back to terminal.
#
# Sensitivity modes (TELEGRAM_SENSITIVITY):
#   all      - Everything is "dangerous" (no auto-approve)
#   smart    - Auto-approve safe ops, prompt for dangerous (default)
#   critical - Only the most dangerous ops trigger prompt
#
# Requirements: curl, jq
# Optional: tmux (for terminal+Telegram hybrid mode)
# =============================================================================

# --- Configuration ---
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
PERMISSION_TIMEOUT="${TELEGRAM_PERMISSION_TIMEOUT:-300}"
POLL_TIMEOUT=10
FALLBACK_ON_ERROR="${TELEGRAM_FALLBACK_ON_ERROR:-allow}"
LOG_FILE="${TELEGRAM_HOOK_LOG:-/tmp/claude/telegram_claude_hook.log}"
SENSITIVITY="${TELEGRAM_SENSITIVITY:-smart}"
MAX_RETRIES="${TELEGRAM_MAX_RETRIES:-2}"

# Telegram mode flag file (exists = ON, absent = OFF)
TELEGRAM_FLAG="/tmp/claude_telegram_active"

# Determine Telegram mode
TELEGRAM_ENABLED=false
if [ -f "$TELEGRAM_FLAG" ]; then
    TELEGRAM_ENABLED=true
fi

# Only set API URL if bot token is available
if [ -n "$BOT_TOKEN" ]; then
    TELEGRAM_API="https://api.telegram.org/bot${BOT_TOKEN}"
fi

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

log() {
    if [ -n "$LOG_FILE" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
    fi
}

escape_html() {
    local text="$1"
    text="${text//&/&amp;}"
    text="${text//</&lt;}"
    text="${text//>/&gt;}"
    echo "$text"
}

respond() {
    local decision="$1"
    local message="$2"

    if [ "$decision" = "allow" ]; then
        jq -n '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "allow"
            }
        }'
    else
        jq -n --arg msg "$message" '{
            hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "deny",
                permissionDecisionReason: $msg
            }
        }'
    fi
}

# =============================================================================
# SMART FILTERING - Risk classification
# =============================================================================

is_safe_bash_command() {
    local cmd="$1"
    local first_word
    first_word=$(echo "$cmd" | awk '{print $1}')
    first_word=$(basename "$first_word" 2>/dev/null || echo "$first_word")

    case "$first_word" in
        ls|cat|head|tail|wc|file|stat|du|df|free|uptime|uname|hostname|whoami|id|date|cal)
            return 0 ;;
        grep|rg|find|locate|which|whereis|type|awk|sed|sort|uniq|cut|tr|tee|diff|comm|paste)
            return 0 ;;
        echo|printf|true|false|test|expr)
            return 0 ;;
        jq|yq|xmllint|csvtool)
            return 0 ;;
        ps|top|htop|pgrep|lsof|ss|netstat|ip|ifconfig|ping|dig|nslookup|host|traceroute)
            return 0 ;;
        touch|mkdir|cp|mv|ln|tree|realpath|dirname|basename|readlink)
            return 0 ;;
        env|printenv|set|declare|alias|history|pwd)
            return 0 ;;
        npm)
            local sub=$(echo "$cmd" | awk '{print $2}')
            case "$sub" in
                list|ls|info|view|outdated|help|config|version|prefix|root|bin|pack) return 0 ;;
                *) return 1 ;;
            esac ;;
        pip|pip3)
            local sub=$(echo "$cmd" | awk '{print $2}')
            case "$sub" in
                list|show|freeze|check|config|help) return 0 ;;
                *) return 1 ;;
            esac ;;
        git)
            # Scan all words (handles -C /path and other flags before subcmd)
            local w; for w in $cmd; do
                case "$w" in status|log|diff|show|branch|tag|remote|stash|describe|shortlog|blame|reflog|rev-parse|ls-files|ls-tree|cat-file|config|version|add|commit) return 0 ;; esac
            done
            return 1 ;;
        python|python3|node)
            local second=$(echo "$cmd" | awk '{print $2}')
            case "$second" in
                --version|-V) return 0 ;;
                *) return 1 ;;
            esac ;;
        curl|wget) return 0 ;;
        *)
            return 1 ;;
    esac
}

is_dangerous_command() {
    local cmd="$1"
    local first_word
    first_word=$(echo "$cmd" | awk '{print $1}')
    first_word=$(basename "$first_word" 2>/dev/null || echo "$first_word")

    case "$first_word" in
        rm|rmdir|shred) return 0 ;;
        sudo|su|doas) return 0 ;;
        chmod|chown|chgrp) return 0 ;;
        kill|killall|pkill) return 0 ;;
        systemctl|service|init) return 0 ;;
        reboot|shutdown|halt|poweroff|mkfs|fdisk|dd|mount|umount) return 0 ;;
        apt|apt-get|dpkg|yum|dnf|pacman|snap|flatpak|brew) return 0 ;;
        docker)
            # Scan all words for dangerous subcommands (handles flags before subcmd)
            local w; for w in $cmd; do
                case "$w" in rm|rmi|stop|kill|prune|system) return 0 ;; esac
            done
            return 1 ;;
        git)
            # Scan all words (handles -C /path and other flags before subcmd)
            local w; for w in $cmd; do
                case "$w" in push|reset|rebase|merge|checkout|clean) return 0 ;; esac
            done
            return 1 ;;
        iptables|ufw|firewalld) return 0 ;;
        crontab) return 0 ;;
        *) return 1 ;;
    esac
}

has_dangerous_heredoc() {
    local cmd="$1"
    if ! echo "$cmd" | grep -qE '<<|python3?\s+-c\s|node\s+-e\s'; then
        return 1
    fi
    local patterns=('os\.remove' 'os\.unlink' 'shutil\.rmtree' 'subprocess' 'os\.system' 'os\.popen' "open\(.*['\"]w['\"]" 'exec\(' 'eval\(' '__import__' 'fs\.unlinkSync' 'fs\.rmdirSync' 'child_process' 'execSync' 'spawn\(')
    for p in "${patterns[@]}"; do
        if echo "$cmd" | grep -qE "$p"; then
            return 0
        fi
    done
    return 1
}

has_dangerous_subcommand() {
    local cmd="$1"
    local parts
    parts=$(echo "$cmd" | sed -E 's/\s*(\|{1,2}|&&|;)\s*/\n/g')
    while IFS= read -r part; do
        part=$(echo "$part" | sed 's/^[[:space:]]*//')
        [ -z "$part" ] && continue
        if is_dangerous_command "$part"; then
            return 0
        fi
    done <<< "$parts"
    return 1
}

touches_sensitive_path() {
    local file_path="$1"
    local patterns=('\.env$' '\.env\.' '\.ssh/' 'credentials' 'secrets' '\.secret' '\.key$' '\.pem$' 'id_rsa' 'id_ed25519' 'authorized_keys' 'shadow$' 'passwd$' 'sudoers' 'htpasswd')
    if echo "$file_path" | grep -qE '^(/etc/|/usr/|/boot/|/sys/|/proc/)'; then
        return 0
    fi
    for p in "${patterns[@]}"; do
        if echo "$file_path" | grep -qiE "$p"; then
            return 0
        fi
    done
    return 1
}

classify_risk() {
    local tool_name="$1"
    local tool_input="$2"

    if [ "$SENSITIVITY" = "all" ]; then
        echo "dangerous"
        return
    fi

    case "$tool_name" in
        Read|Glob|Grep|WebFetch|WebSearch|ListMcpResourcesTool|ReadMcpResourceTool)
            echo "safe"
            return ;;
        Bash)
            local command
            command=$(echo "$tool_input" | jq -r '.command // ""' 2>/dev/null)
            [ -z "$command" ] && { echo "dangerous"; return; }
            if has_dangerous_heredoc "$command"; then
                log "Heredoc with dangerous content"
                echo "dangerous"; return
            fi
            if has_dangerous_subcommand "$command"; then
                log "Compound command with dangerous sub-command"
                echo "dangerous"; return
            fi
            if is_dangerous_command "$command"; then
                echo "dangerous"; return
            fi
            echo "safe"; return ;;
        Write|Edit|NotebookEdit)
            local file_path
            file_path=$(echo "$tool_input" | jq -r '.file_path // .notebook_path // ""' 2>/dev/null)
            if touches_sensitive_path "$file_path"; then
                echo "dangerous"; return
            fi
            echo "safe"; return ;;
        Task)
            echo "safe"; return ;;
        *)
            echo "safe"; return ;;
    esac
}

# =============================================================================
# TELEGRAM FUNCTIONS
# =============================================================================

send_telegram_with_buttons() {
    local text="$1"
    local response
    response=$(curl -s -X POST "${TELEGRAM_API}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$CHAT_ID" \
            --arg text "$text" \
            '{
                chat_id: ($chat_id | tonumber),
                text: $text,
                parse_mode: "HTML",
                reply_markup: {
                    inline_keyboard: [[
                        { text: "\u2705 Allow", callback_data: "allow" },
                        { text: "\u274c Deny", callback_data: "deny" }
                    ]]
                }
            }'
        )" 2>/dev/null)
    local ok
    ok=$(echo "$response" | jq -r '.ok' 2>/dev/null)
    [ "$ok" = "true" ]
}

send_telegram() {
    local text="$1"
    curl -s -X POST "${TELEGRAM_API}/sendMessage" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "text=${text}" >/dev/null 2>&1
}

answer_callback() {
    local callback_id="$1"
    local text="$2"
    curl -s -X POST "${TELEGRAM_API}/answerCallbackQuery" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg id "$callback_id" --arg text "$text" \
            '{ callback_query_id: $id, text: $text }'
        )" >/dev/null 2>&1
}

get_latest_offset() {
    local response
    response=$(curl -s "${TELEGRAM_API}/getUpdates?offset=-1&limit=1" 2>/dev/null)
    local update_id
    update_id=$(echo "$response" | jq -r '.result[-1].update_id // empty' 2>/dev/null)
    if [ -n "$update_id" ]; then
        echo $((update_id + 1))
    else
        echo "0"
    fi
}

wait_for_response() {
    local offset="$1"
    local timeout="$2"
    local elapsed=0

    # Reminder schedule: at 60s, 120s, and 60s before timeout
    local r1=60
    local r2=120
    local r3=$((timeout - 60))
    local sent_r1=0 sent_r2=0 sent_r3=0

    while [ $elapsed -lt $timeout ]; do
        local remaining=$((timeout - elapsed))
        local this_poll=$POLL_TIMEOUT
        [ $remaining -lt $this_poll ] && this_poll=$remaining

        if [ $sent_r1 -eq 0 ] && [ $elapsed -ge $r1 ] && [ $r1 -lt $timeout ]; then
            send_telegram "⏳ Pending permission. ${remaining}s remaining"
            sent_r1=1
        fi
        if [ $sent_r2 -eq 0 ] && [ $elapsed -ge $r2 ] && [ $r2 -lt $r3 ]; then
            send_telegram "⏰ Still waiting. ${remaining}s remaining"
            sent_r2=1
        fi
        if [ $sent_r3 -eq 0 ] && [ $elapsed -ge $r3 ] && [ $r3 -gt $r2 ]; then
            send_telegram "🚨 Last ${remaining}s to respond!"
            sent_r3=1
        fi

        local response
        response=$(curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}&timeout=${this_poll}&limit=1" 2>/dev/null)
        elapsed=$((elapsed + this_poll))

        local result_count
        result_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

        if [ "$result_count" -gt 0 ] 2>/dev/null; then
            local update_id
            update_id=$(echo "$response" | jq -r '.result[0].update_id // empty' 2>/dev/null)
            [ -n "$update_id" ] && offset=$((update_id + 1))

            local callback_data callback_id callback_from
            callback_data=$(echo "$response" | jq -r '.result[0].callback_query.data // empty' 2>/dev/null)
            callback_id=$(echo "$response" | jq -r '.result[0].callback_query.id // empty' 2>/dev/null)
            callback_from=$(echo "$response" | jq -r '.result[0].callback_query.from.id // empty' 2>/dev/null)

            if [ -n "$callback_data" ]; then
                [ "$callback_from" != "$CHAT_ID" ] && continue
                answer_callback "$callback_id" "Received"
                curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}" >/dev/null 2>&1
                echo "$callback_data"
                return 0
            fi

            local text from_id
            text=$(echo "$response" | jq -r '.result[0].message.text // empty' 2>/dev/null)
            from_id=$(echo "$response" | jq -r '.result[0].message.from.id // empty' 2>/dev/null)

            if [ -n "$text" ]; then
                [ "$from_id" != "$CHAT_ID" ] && continue
                curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}" >/dev/null 2>&1
                echo "$text"
                return 0
            fi
        fi
    done
    return 1
}

parse_user_response() {
    local response="$1"
    if [ "$response" = "allow" ] || [ "$response" = "deny" ]; then
        echo "$response"; return 0
    fi
    local normalized
    normalized=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)
    case "$normalized" in
        si|sí|s|yes|y|ok|dale|vale|adelante|apruebo|aprobar|approve|go|1) echo "allow"; return 0 ;;
        no|n|cancelar|cancel|rechazar|rechazado|deny|nope|0) echo "deny"; return 0 ;;
        *) echo "unknown"; return 1 ;;
    esac
}

build_permission_message() {
    local tool_name="$1"
    local tool_input="$2"
    local message="<b>Claude Code needs permission</b>"$'\n\n'
    case "$tool_name" in
        Bash)
            local command
            command=$(echo "$tool_input" | jq -r '.command // "unknown"' 2>/dev/null)
            command=$(escape_html "$command")
            message+="<b>Tool:</b> Bash"$'\n'
            message+="<b>Command:</b>"$'\n'"<code>${command}</code>"$'\n' ;;
        Write)
            local fp=$(echo "$tool_input" | jq -r '.file_path // "unknown"' 2>/dev/null)
            message+="<b>Tool:</b> Write"$'\n'"<b>File:</b> <code>$(escape_html "$fp")</code>"$'\n' ;;
        Edit)
            local fp=$(echo "$tool_input" | jq -r '.file_path // "unknown"' 2>/dev/null)
            message+="<b>Tool:</b> Edit"$'\n'"<b>File:</b> <code>$(escape_html "$fp")</code>"$'\n' ;;
        *)
            message+="<b>Tool:</b> $(escape_html "$tool_name")"$'\n'
            local preview=$(echo "$tool_input" | jq -c '.' 2>/dev/null | head -c 200)
            [ -n "$preview" ] && message+="<b>Detail:</b> <code>$(escape_html "$preview")</code>"$'\n' ;;
    esac
    message+=$'\n'"<i>Timeout: ${PERMISSION_TIMEOUT}s</i>"
    echo "$message"
}

send_relaunch_button() {
    local text="$1"
    curl -s -X POST "${TELEGRAM_API}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$CHAT_ID" \
            --arg text "$text" \
            '{
                chat_id: ($chat_id | tonumber),
                text: $text,
                parse_mode: "HTML",
                reply_markup: {
                    inline_keyboard: [[
                        { text: "🔄 Relaunch", callback_data: "relaunch" },
                        { text: "❌ Deny", callback_data: "deny" }
                    ]]
                }
            }'
        )" >/dev/null 2>&1
}

# =============================================================================
# TELEGRAM BLOCKING FLOW (used when not in tmux)
# =============================================================================

run_telegram_blocking() {
    local tool_name="$1"
    local tool_input="$2"

    local permission_msg
    permission_msg=$(build_permission_message "$tool_name" "$tool_input")

    local relaunch_count=0

    while true; do
        local offset
        offset=$(get_latest_offset)
        log "Offset: $offset (attempt $((relaunch_count + 1)))"

        if ! send_telegram_with_buttons "$permission_msg"; then
            log "ERROR: Could not send to Telegram"
            respond "$FALLBACK_ON_ERROR" "Could not reach Telegram"
            return
        fi

        log "Waiting for Telegram response (timeout: ${PERMISSION_TIMEOUT}s)..."
        local user_response
        user_response=$(wait_for_response "$offset" "$PERMISSION_TIMEOUT")

        if [ $? -ne 0 ]; then
            # Timeout: offer relaunch if retries remain
            if [ $relaunch_count -lt $MAX_RETRIES ]; then
                relaunch_count=$((relaunch_count + 1))
                offset=$(get_latest_offset)
                send_relaunch_button "⏰ <b>Expired</b>. Tap <b>Relaunch</b> to resend or <b>Deny</b>. <i>(${relaunch_count}/${MAX_RETRIES})</i>"
                log "Relaunch offered ($relaunch_count/$MAX_RETRIES)"

                local relaunch_resp
                relaunch_resp=$(wait_for_response "$offset" 60)
                if [ $? -eq 0 ] && [ "$relaunch_resp" = "relaunch" ]; then
                    send_telegram "🔄 Relaunching..."
                    log "User chose relaunch"
                    continue
                elif [ "$relaunch_resp" = "deny" ]; then
                    send_telegram "❌ Action denied"
                    respond "deny" "Denied from relaunch prompt"
                    return
                fi
            fi
            send_telegram "⛔ No response. Action denied."
            respond "deny" "Timeout after $relaunch_count relaunches"
            return
        fi

        log "User response: $user_response"
        local decision
        decision=$(parse_user_response "$user_response")

        case "$decision" in
            allow) send_telegram "✅ Action allowed"; respond "allow" ;;
            deny)  send_telegram "❌ Action denied";  respond "deny" "Denied from Telegram" ;;
            *)     send_telegram "❓ Unknown response. Denied."; respond "deny" "Unknown: $user_response" ;;
        esac
        return
    done
}

# =============================================================================
# TMUX TELEGRAM ESCALATOR (background - used when in tmux)
# =============================================================================

start_tmux_escalator() {
    local tool_name="$1"
    local tool_input="$2"
    local delay="$3"

    (
        exec 2>>"$LOG_FILE"
        log "[BG] Tmux escalator started (delay: ${delay}s, PID: $$)"

        sleep "$delay"

        log "[BG] Delay elapsed, sending to Telegram"
        local permission_msg
        permission_msg=$(build_permission_message "$tool_name" "$tool_input")

        if ! send_telegram_with_buttons "$permission_msg"; then
            log "[BG] ERROR: Could not send to Telegram"
            exit 1
        fi

        local offset
        offset=$(get_latest_offset)

        local remaining=$((PERMISSION_TIMEOUT - delay))
        [ $remaining -lt 30 ] && remaining=30

        local user_response
        user_response=$(wait_for_response "$offset" "$remaining")

        if [ $? -ne 0 ]; then
            log "[BG] Timeout waiting for Telegram response"
            send_telegram "No response. Check the terminal."
            exit 1
        fi

        local decision
        decision=$(parse_user_response "$user_response")
        log "[BG] Telegram response: $decision"

        # Find tmux pane and send keystroke
        local target_pane
        target_pane=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_command}' 2>/dev/null \
            | grep -iE "node|claude" \
            | head -1 \
            | cut -d' ' -f1)

        if [ -z "$target_pane" ]; then
            target_pane=$(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null | head -1)
        fi

        if [ -n "$target_pane" ]; then
            case "$decision" in
                allow)
                    send_telegram "Approved. Sending to terminal..."
                    log "[BG] Sending 'y' to tmux pane: $target_pane"
                    tmux send-keys -t "$target_pane" "y" Enter
                    ;;
                deny)
                    send_telegram "Denied. Sending to terminal..."
                    log "[BG] Sending 'n' to tmux pane: $target_pane"
                    tmux send-keys -t "$target_pane" "n" Enter
                    ;;
                *)
                    send_telegram "Unknown response. Check terminal."
                    ;;
            esac
        else
            log "[BG] ERROR: No tmux pane found"
            send_telegram "Could not find terminal. Respond manually."
        fi

        log "[BG] Escalator done"
    ) &>/dev/null &
    disown $!
    log "Background tmux escalator started (PID: $!, delay: ${delay}s)"
}

# =============================================================================
# MAIN
# =============================================================================
# Flow:
#   1. Parse input, classify risk
#   2. Safe -> auto-approve
#   3. Dangerous + no Telegram -> passthrough (terminal prompt only)
#   4. Dangerous + Telegram + tmux -> passthrough + background escalator
#   5. Dangerous + Telegram + no tmux -> blocking Telegram (v0.3 style)
# =============================================================================

log "=== Hook started (sensitivity=$SENSITIVITY, telegram=$TELEGRAM_ENABLED) ==="

# Check dependencies
if ! command -v jq &>/dev/null; then
    log "ERROR: jq not installed"
    respond "$FALLBACK_ON_ERROR" "jq not installed"
    exit 0
fi
if ! command -v curl &>/dev/null; then
    log "ERROR: curl not installed"
    respond "$FALLBACK_ON_ERROR" "curl not installed"
    exit 0
fi

# Read input
INPUT=$(cat)
log "Input: $INPUT"

if ! echo "$INPUT" | jq . >/dev/null 2>&1; then
    log "ERROR: Invalid JSON"
    respond "$FALLBACK_ON_ERROR" "Invalid JSON"
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}')

log "Tool: $TOOL_NAME"

# --- Step 1: Smart filtering ---
RISK=$(classify_risk "$TOOL_NAME" "$TOOL_INPUT")
log "Risk: $RISK"

if [ "$RISK" = "safe" ]; then
    log "Auto-approved (safe)"
    respond "allow"
    exit 0
fi

# --- Step 2: Dangerous operation ---
log "Dangerous operation detected"

# MODE 1: Terminal only (no Telegram)
if [ "$TELEGRAM_ENABLED" != "true" ]; then
    log "Terminal only mode - passthrough"
    log "=== Hook passthrough (terminal prompt) ==="
    exit 0
fi

# Check Telegram credentials
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    log "ERROR: Telegram credentials missing, falling back to terminal"
    exit 0
fi

# MODE 2: Terminal + Telegram (tmux available)
if command -v tmux &>/dev/null && tmux list-sessions &>/dev/null 2>&1; then
    log "Hybrid mode: terminal + Telegram via tmux"
    start_tmux_escalator "$TOOL_NAME" "$TOOL_INPUT" "120"
    # Exit with no output -> Claude shows terminal prompt
    log "=== Hook passthrough (terminal prompt + tmux escalator) ==="
    exit 0
fi

# MODE 3: Telegram only (no tmux, blocking)
log "Blocking Telegram mode (no tmux available)"
run_telegram_blocking "$TOOL_NAME" "$TOOL_INPUT"

log "=== Hook finished ==="
exit 0
