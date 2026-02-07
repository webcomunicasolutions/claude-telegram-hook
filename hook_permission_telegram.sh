#!/bin/bash
# =============================================================================
# hook_permission_telegram.sh - Approve/reject Claude Code permissions from Telegram
# =============================================================================
# Replaces the terminal permission dialog with Telegram inline buttons.
# When Claude Code needs permission, it sends a message to Telegram and
# waits for your response (button tap or text reply).
#
# Event: PermissionRequest
# Requirements: curl, jq
# =============================================================================

# --- Configuration ---
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:?ERROR: Set TELEGRAM_BOT_TOKEN environment variable}"
CHAT_ID="${TELEGRAM_CHAT_ID:?ERROR: Set TELEGRAM_CHAT_ID environment variable}"
PERMISSION_TIMEOUT="${TELEGRAM_PERMISSION_TIMEOUT:-120}"
POLL_TIMEOUT=10
FALLBACK_ON_ERROR="${TELEGRAM_FALLBACK_ON_ERROR:-allow}"
LOG_FILE="${TELEGRAM_HOOK_LOG:-/tmp/telegram_claude_hook.log}"
TELEGRAM_API="https://api.telegram.org/bot${BOT_TOKEN}"

# --- Functions ---

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
                hookEventName: "PermissionRequest",
                decision: { behavior: "allow" }
            }
        }'
    else
        jq -n --arg msg "$message" '{
            hookSpecificOutput: {
                hookEventName: "PermissionRequest",
                decision: { behavior: "deny", message: $msg }
            }
        }'
    fi
}

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
                        { text: "✅ Allow", callback_data: "allow" },
                        { text: "❌ Deny", callback_data: "deny" }
                    ]]
                }
            }'
        )" 2>/dev/null)

    local ok
    ok=$(echo "$response" | jq -r '.ok' 2>/dev/null)

    if [ "$ok" = "true" ]; then
        log "Message with buttons sent to Telegram"
        return 0
    else
        local error
        error=$(echo "$response" | jq -r '.description // "Unknown error"' 2>/dev/null)
        log "Error sending to Telegram: $error"
        return 1
    fi
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

    while [ $elapsed -lt $timeout ]; do
        local remaining=$((timeout - elapsed))
        local this_poll=$POLL_TIMEOUT
        if [ $remaining -lt $this_poll ]; then
            this_poll=$remaining
        fi

        local response
        response=$(curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}&timeout=${this_poll}&limit=1" 2>/dev/null)

        elapsed=$((elapsed + this_poll))

        local result_count
        result_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

        if [ "$result_count" -gt 0 ] 2>/dev/null; then
            local update_id
            update_id=$(echo "$response" | jq -r '.result[0].update_id // empty' 2>/dev/null)

            if [ -n "$update_id" ]; then
                offset=$((update_id + 1))
            fi

            # Case 1: Inline button pressed (callback_query)
            local callback_data callback_id callback_from
            callback_data=$(echo "$response" | jq -r '.result[0].callback_query.data // empty' 2>/dev/null)
            callback_id=$(echo "$response" | jq -r '.result[0].callback_query.id // empty' 2>/dev/null)
            callback_from=$(echo "$response" | jq -r '.result[0].callback_query.from.id // empty' 2>/dev/null)

            if [ -n "$callback_data" ]; then
                if [ "$callback_from" != "$CHAT_ID" ]; then
                    log "Callback ignored from unauthorized user: $callback_from"
                    continue
                fi

                answer_callback "$callback_id" "Received"
                curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}" >/dev/null 2>&1

                echo "$callback_data"
                return 0
            fi

            # Case 2: Text message (fallback compatibility)
            local text from_id
            text=$(echo "$response" | jq -r '.result[0].message.text // empty' 2>/dev/null)
            from_id=$(echo "$response" | jq -r '.result[0].message.from.id // empty' 2>/dev/null)

            if [ -n "$text" ]; then
                if [ "$from_id" != "$CHAT_ID" ]; then
                    log "Message ignored from unauthorized user: $from_id"
                    continue
                fi

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

    # Direct from inline button
    if [ "$response" = "allow" ] || [ "$response" = "deny" ]; then
        echo "$response"
        return 0
    fi

    # Text message normalization
    local normalized
    normalized=$(echo "$response" | tr '[:upper:]' '[:lower:]' | xargs)

    case "$normalized" in
        si|sí|s|yes|y|ok|dale|vale|adelante|apruebo|aprobar|approve|go|1)
            echo "allow"
            return 0
            ;;
        no|n|cancelar|cancel|rechazar|rechazado|deny|nope|0)
            echo "deny"
            return 0
            ;;
        *)
            echo "unknown"
            return 1
            ;;
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
            message+="<b>Command:</b>"$'\n'"<code>${command}</code>"$'\n'
            ;;
        Write)
            local file_path
            file_path=$(echo "$tool_input" | jq -r '.file_path // "unknown"' 2>/dev/null)
            file_path=$(escape_html "$file_path")
            message+="<b>Tool:</b> Write (create file)"$'\n'
            message+="<b>File:</b> <code>${file_path}</code>"$'\n'
            ;;
        Edit)
            local file_path
            file_path=$(echo "$tool_input" | jq -r '.file_path // "unknown"' 2>/dev/null)
            file_path=$(escape_html "$file_path")
            message+="<b>Tool:</b> Edit"$'\n'
            message+="<b>File:</b> <code>${file_path}</code>"$'\n'
            ;;
        WebFetch)
            local url
            url=$(echo "$tool_input" | jq -r '.url // "unknown"' 2>/dev/null)
            url=$(escape_html "$url")
            message+="<b>Tool:</b> WebFetch"$'\n'
            message+="<b>URL:</b> <code>${url}</code>"$'\n'
            ;;
        WebSearch)
            local query
            query=$(echo "$tool_input" | jq -r '.query // "unknown"' 2>/dev/null)
            query=$(escape_html "$query")
            message+="<b>Tool:</b> WebSearch"$'\n'
            message+="<b>Query:</b> <code>${query}</code>"$'\n'
            ;;
        *)
            local safe_name
            safe_name=$(escape_html "$tool_name")
            message+="<b>Tool:</b> ${safe_name}"$'\n'
            local input_preview
            input_preview=$(echo "$tool_input" | jq -c '.' 2>/dev/null | head -c 200)
            input_preview=$(escape_html "$input_preview")
            if [ -n "$input_preview" ]; then
                message+="<b>Detail:</b> <code>${input_preview}</code>"$'\n'
            fi
            ;;
    esac

    message+=$'\n'"<i>Timeout: ${PERMISSION_TIMEOUT}s</i>"

    echo "$message"
}

# --- Main ---

log "=== Hook PermissionRequest started ==="

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

INPUT=$(cat)
log "Input: $INPUT"

if ! echo "$INPUT" | jq . >/dev/null 2>&1; then
    log "ERROR: Invalid JSON input"
    respond "$FALLBACK_ON_ERROR" "Invalid JSON input"
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$INPUT" | jq -c '.tool_input // {}')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "no-session"')

log "Tool: $TOOL_NAME | Session: $SESSION_ID"

PERMISSION_MSG=$(build_permission_message "$TOOL_NAME" "$TOOL_INPUT")

OFFSET=$(get_latest_offset)
log "Offset: $OFFSET"

if ! send_telegram_with_buttons "$PERMISSION_MSG"; then
    log "ERROR: Could not send to Telegram, using fallback policy"
    respond "$FALLBACK_ON_ERROR" "Could not reach Telegram"
    exit 0
fi

log "Waiting for response (timeout: ${PERMISSION_TIMEOUT}s)..."
USER_RESPONSE=$(wait_for_response "$OFFSET" "$PERMISSION_TIMEOUT")

if [ $? -ne 0 ]; then
    log "Timeout: no response"
    send_telegram "Timeout: no response in ${PERMISSION_TIMEOUT}s. Action denied."
    respond "deny" "Timeout: no response in ${PERMISSION_TIMEOUT}s"
    exit 0
fi

log "User response: $USER_RESPONSE"
DECISION=$(parse_user_response "$USER_RESPONSE")

case "$DECISION" in
    allow)
        log "Decision: ALLOWED"
        send_telegram "Action allowed"
        respond "allow"
        ;;
    deny)
        log "Decision: DENIED"
        send_telegram "Action denied"
        respond "deny" "User denied from Telegram"
        ;;
    unknown)
        log "Decision: UNKNOWN ($USER_RESPONSE), denying for safety"
        send_telegram "Unrecognized response: '${USER_RESPONSE}'. Denied for safety."
        respond "deny" "Unrecognized response: ${USER_RESPONSE}"
        ;;
esac

log "=== Hook PermissionRequest finished ==="
exit 0
