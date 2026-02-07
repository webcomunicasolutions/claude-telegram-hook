#!/bin/bash
# =============================================================================
# telegram_approve.sh - Reusable Telegram approval library
# =============================================================================
# Source this file from any Bash script to add Telegram approval buttons.
# Not tied to Claude Code -- works with any script, cron job, or server task.
#
# Usage:
#   source telegram_approve.sh
#   if telegram_ask "Deploy to production?"; then
#       ./deploy.sh
#   fi
#
# Requirements: curl, jq
# Environment: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID
# =============================================================================

# --- Configuration ---
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:?ERROR: Set TELEGRAM_BOT_TOKEN environment variable}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:?ERROR: Set TELEGRAM_CHAT_ID environment variable}"
TELEGRAM_TIMEOUT="${TELEGRAM_TIMEOUT:-120}"
TELEGRAM_API="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}"

# --- Internal functions ---

_telegram_escape_html() {
    local text="$1"
    text="${text//&/&amp;}"
    text="${text//</&lt;}"
    text="${text//>/&gt;}"
    echo "$text"
}

_telegram_get_offset() {
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

_telegram_wait_response() {
    local offset="$1"
    local timeout="$2"
    local elapsed=0
    local poll_timeout=10

    while [ $elapsed -lt $timeout ]; do
        local remaining=$((timeout - elapsed))
        local this_poll=$poll_timeout
        [ $remaining -lt $this_poll ] && this_poll=$remaining

        local response
        response=$(curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}&timeout=${this_poll}&limit=1" 2>/dev/null)
        elapsed=$((elapsed + this_poll))

        local result_count
        result_count=$(echo "$response" | jq '.result | length' 2>/dev/null)

        if [ "$result_count" -gt 0 ] 2>/dev/null; then
            local update_id
            update_id=$(echo "$response" | jq -r '.result[0].update_id // empty' 2>/dev/null)
            [ -n "$update_id" ] && offset=$((update_id + 1))

            # Inline button pressed
            local callback_data callback_id callback_from
            callback_data=$(echo "$response" | jq -r '.result[0].callback_query.data // empty' 2>/dev/null)
            callback_id=$(echo "$response" | jq -r '.result[0].callback_query.id // empty' 2>/dev/null)
            callback_from=$(echo "$response" | jq -r '.result[0].callback_query.from.id // empty' 2>/dev/null)

            if [ -n "$callback_data" ]; then
                if [ "$callback_from" != "$TELEGRAM_CHAT_ID" ]; then
                    continue
                fi
                # Acknowledge the button tap
                curl -s -X POST "${TELEGRAM_API}/answerCallbackQuery" \
                    -H "Content-Type: application/json" \
                    -d "$(jq -n --arg id "$callback_id" '{ callback_query_id: $id, text: "OK" }')" >/dev/null 2>&1
                # Clear offset
                curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}" >/dev/null 2>&1
                echo "$callback_data"
                return 0
            fi

            # Text message fallback
            local text from_id
            text=$(echo "$response" | jq -r '.result[0].message.text // empty' 2>/dev/null)
            from_id=$(echo "$response" | jq -r '.result[0].message.from.id // empty' 2>/dev/null)

            if [ -n "$text" ] && [ "$from_id" = "$TELEGRAM_CHAT_ID" ]; then
                curl -s "${TELEGRAM_API}/getUpdates?offset=${offset}" >/dev/null 2>&1
                echo "$text"
                return 0
            fi
        fi
    done

    return 1
}

# --- Public functions ---

# Send a plain text message (no buttons)
# Usage: telegram_send "Hello world"
# Supports HTML: telegram_send "<b>Bold</b> and <i>italic</i>"
telegram_send() {
    local text="$1"
    curl -s -X POST "${TELEGRAM_API}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$TELEGRAM_CHAT_ID" \
            --arg text "$text" \
            '{
                chat_id: ($chat_id | tonumber),
                text: $text,
                parse_mode: "HTML"
            }'
        )" >/dev/null 2>&1
}

# Send a message with two custom buttons
# Usage: telegram_send_buttons "Message" "Yes text" "yes_data" "No text" "no_data"
telegram_send_buttons() {
    local text="$1"
    local btn1_text="${2:-Yes}"
    local btn1_data="${3:-yes}"
    local btn2_text="${4:-No}"
    local btn2_data="${5:-no}"

    curl -s -X POST "${TELEGRAM_API}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$TELEGRAM_CHAT_ID" \
            --arg text "$text" \
            --arg b1t "$btn1_text" \
            --arg b1d "$btn1_data" \
            --arg b2t "$btn2_text" \
            --arg b2d "$btn2_data" \
            '{
                chat_id: ($chat_id | tonumber),
                text: $text,
                parse_mode: "HTML",
                reply_markup: {
                    inline_keyboard: [[
                        { text: $b1t, callback_data: $b1d },
                        { text: $b2t, callback_data: $b2d }
                    ]]
                }
            }'
        )" >/dev/null 2>&1
}

# Ask a yes/no question. Returns exit code 0 (yes) or 1 (no/timeout).
# Usage:
#   if telegram_ask "Deploy to production?"; then
#       echo "Approved!"
#   fi
# Custom button labels:
#   telegram_ask "Upload backup?" "Upload" "Skip"
telegram_ask() {
    local question="$1"
    local yes_text="${2:-Yes}"
    local no_text="${3:-No}"

    local offset
    offset=$(_telegram_get_offset)

    telegram_send_buttons "$question" "$yes_text" "yes" "$no_text" "no"

    local response
    response=$(_telegram_wait_response "$offset" "$TELEGRAM_TIMEOUT")

    if [ $? -ne 0 ]; then
        telegram_send "Timeout -- no response received"
        return 1
    fi

    if [ "$response" = "yes" ]; then
        return 0
    else
        return 1
    fi
}

# Ask a question with multiple custom options.
# Returns the chosen callback_data on stdout, or "timeout" on timeout.
# Usage:
#   choice=$(telegram_choose "What should we do?" \
#       "Clean logs" "clean" \
#       "Restart" "restart" \
#       "Skip" "skip")
telegram_choose() {
    local question="$1"
    shift

    local offset
    offset=$(_telegram_get_offset)

    # Build button JSON dynamically
    local buttons="["
    local first=1
    while [ $# -ge 2 ]; do
        [ $first -eq 0 ] && buttons+=","
        local btn_text btn_data
        btn_text=$(echo "$1" | jq -Rs '.' | sed 's/^"//;s/"$//')
        btn_data=$(echo "$2" | jq -Rs '.' | sed 's/^"//;s/"$//')
        buttons+="{\"text\":\"${btn_text}\",\"callback_data\":\"${btn_data}\"}"
        first=0
        shift 2
    done
    buttons+="]"

    curl -s -X POST "${TELEGRAM_API}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$TELEGRAM_CHAT_ID" \
            --arg text "$question" \
            --argjson buttons "[$buttons]" \
            '{
                chat_id: ($chat_id | tonumber),
                text: $text,
                parse_mode: "HTML",
                reply_markup: { inline_keyboard: $buttons }
            }'
        )" >/dev/null 2>&1

    local response
    response=$(_telegram_wait_response "$offset" "$TELEGRAM_TIMEOUT")

    if [ $? -ne 0 ]; then
        telegram_send "Timeout -- no response received"
        echo "timeout"
        return 1
    fi

    echo "$response"
    return 0
}
