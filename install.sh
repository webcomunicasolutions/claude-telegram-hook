#!/bin/bash
# =============================================================================
# install.sh - Installer for claude-telegram-hook
# =============================================================================
#
# Installs the Telegram permission hook for Claude Code.
# Smart filtering auto-approves safe operations. Dangerous ones go to
# terminal prompt (default) or Telegram (when enabled).
#
# Usage:
#   bash install.sh
#   bash install.sh --uninstall
#
# Requirements: curl, jq
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Paths ---
CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
ENV_FILE="$HOOKS_DIR/.env"
HOOK_SCRIPT="$HOOKS_DIR/hook_permission_telegram.sh"
WRAPPER_SCRIPT="$HOOKS_DIR/hook_permission_telegram_wrapper.sh"

# --- Script directory (where install.sh lives) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_HOOK=""

# --- Helper Functions ---

print_banner() {
    echo ""
    echo -e "${CYAN}${BOLD}=====================================================${NC}"
    echo -e "${CYAN}${BOLD}   claude-telegram-hook installer${NC}"
    echo -e "${CYAN}${BOLD}=====================================================${NC}"
    echo -e "${DIM}   Smart permissions for Claude Code${NC}"
    echo ""
}

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

step() {
    echo ""
    echo -e "${BOLD}>> $*${NC}"
}

# --- Preflight Checks ---

check_dependencies() {
    step "Checking dependencies..."

    local missing=0

    if command -v curl &>/dev/null; then
        success "curl found: $(command -v curl)"
    else
        error "curl is not installed."
        echo "  Install with: sudo apt-get install -y curl"
        missing=1
    fi

    if command -v jq &>/dev/null; then
        success "jq found: $(command -v jq)"
    else
        error "jq is not installed."
        echo "  Install with: sudo apt-get install -y jq"
        missing=1
    fi

    if [ "$missing" -ne 0 ]; then
        echo ""
        error "Missing required dependencies. Please install them and try again."
        exit 1
    fi
}

find_hook_script() {
    # Look for the hook script relative to this installer
    local candidates=(
        "$SCRIPT_DIR/hook_permission_telegram.sh"
        "$SCRIPT_DIR/scripts/hook_permission_telegram.sh"
        "$SCRIPT_DIR/../scripts/hook_permission_telegram.sh"
    )

    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
            SOURCE_HOOK="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
            return 0
        fi
    done

    error "Cannot find hook_permission_telegram.sh"
    echo "  Expected locations:"
    for candidate in "${candidates[@]}"; do
        echo "    - $candidate"
    done
    echo ""
    echo "  Make sure hook_permission_telegram.sh is in the same directory"
    echo "  as install.sh, or in a scripts/ subdirectory."
    exit 1
}

# --- User Input ---

ask_telegram_config() {
    step "Telegram Bot configuration"
    echo ""
    echo -e "${DIM}  You need a Telegram bot token and your chat ID.${NC}"
    echo -e "${DIM}  Create a bot with @BotFather on Telegram if you don't have one.${NC}"
    echo -e "${DIM}  Get your chat ID by messaging @userinfobot on Telegram.${NC}"
    echo ""

    # Bot Token
    while true; do
        read -rp "$(echo -e "${BOLD}  TELEGRAM_BOT_TOKEN: ${NC}")" BOT_TOKEN
        if [ -z "$BOT_TOKEN" ]; then
            warn "Bot token is required. Please enter your Telegram bot token."
        elif [[ ! "$BOT_TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
            warn "Token format looks invalid. Expected format: 123456789:ABCdefGhIjKlMnOpQrStUvWxYz"
            read -rp "$(echo -e "${YELLOW}  Use it anyway? [y/N]: ${NC}")" use_anyway
            if [[ "$use_anyway" =~ ^[Yy]$ ]]; then
                break
            fi
        else
            break
        fi
    done

    # Chat ID
    while true; do
        read -rp "$(echo -e "${BOLD}  TELEGRAM_CHAT_ID:  ${NC}")" CHAT_ID
        if [ -z "$CHAT_ID" ]; then
            warn "Chat ID is required. Please enter your Telegram chat ID."
        elif [[ ! "$CHAT_ID" =~ ^-?[0-9]+$ ]]; then
            warn "Chat ID should be a number (e.g., 123456789 or -1001234567890)."
            read -rp "$(echo -e "${YELLOW}  Use it anyway? [y/N]: ${NC}")" use_anyway
            if [[ "$use_anyway" =~ ^[Yy]$ ]]; then
                break
            fi
        else
            break
        fi
    done

    echo ""
    info "Bot Token: ${BOT_TOKEN:0:10}...${BOT_TOKEN: -4}"
    info "Chat ID:   $CHAT_ID"
}

ask_sensitivity_config() {
    step "Smart filtering configuration"
    echo ""
    echo -e "${DIM}  Smart filtering auto-approves safe operations (ls, cat, git status...)${NC}"
    echo -e "${DIM}  and only asks for dangerous ones (rm, sudo, git push...).${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} ${GREEN}smart${NC} (recommended) -- Auto-approve safe, ask for dangerous"
    echo -e "  ${BOLD}2)${NC} ${YELLOW}critical${NC} -- Only the most destructive ops need approval"
    echo -e "  ${BOLD}3)${NC} ${RED}all${NC} -- Everything needs approval (no auto-approve)"
    echo ""

    while true; do
        read -rp "$(echo -e "${BOLD}  Choose [1/2/3] (default: 1): ${NC}")" sensitivity_choice
        case "${sensitivity_choice:-1}" in
            1) SENSITIVITY_MODE="smart"; break ;;
            2) SENSITIVITY_MODE="critical"; break ;;
            3) SENSITIVITY_MODE="all"; break ;;
            *) warn "Please enter 1, 2, or 3." ;;
        esac
    done

    success "Sensitivity mode: $SENSITIVITY_MODE"
}

# --- Installation Steps ---

create_directories() {
    step "Creating directories..."

    if [ ! -d "$CLAUDE_DIR" ]; then
        mkdir -p "$CLAUDE_DIR"
        success "Created $CLAUDE_DIR"
    else
        success "$CLAUDE_DIR already exists"
    fi

    if [ ! -d "$HOOKS_DIR" ]; then
        mkdir -p "$HOOKS_DIR"
        success "Created $HOOKS_DIR"
    else
        success "$HOOKS_DIR already exists"
    fi
}

copy_hook_script() {
    step "Installing hook script..."

    if [ -f "$HOOK_SCRIPT" ]; then
        warn "Hook script already exists at $HOOK_SCRIPT"
        read -rp "$(echo -e "${YELLOW}  Overwrite? [y/N]: ${NC}")" overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            info "Keeping existing hook script."
            return 0
        fi
        # Backup existing
        cp "$HOOK_SCRIPT" "${HOOK_SCRIPT}.backup.$(date +%Y%m%d%H%M%S)"
        info "Backup created of existing hook script."
    fi

    cp "$SOURCE_HOOK" "$HOOK_SCRIPT"
    chmod +x "$HOOK_SCRIPT"
    success "Installed hook script to $HOOK_SCRIPT"
}

create_env_file() {
    step "Creating environment file..."

    if [ -f "$ENV_FILE" ]; then
        warn "Environment file already exists at $ENV_FILE"
        read -rp "$(echo -e "${YELLOW}  Overwrite? [y/N]: ${NC}")" overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            info "Keeping existing environment file."
            return 0
        fi
        cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        info "Backup created of existing environment file."
    fi

    cat > "$ENV_FILE" <<ENVEOF
# claude-telegram-hook environment variables
# Generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')
#
# Edit these values if your bot token or chat ID changes.
# Do NOT commit this file to version control.

export TELEGRAM_BOT_TOKEN="$BOT_TOKEN"
export TELEGRAM_CHAT_ID="$CHAT_ID"

# Smart filtering: all | smart | critical (default: smart)
# - all: every tool needs approval (no auto-approve)
# - smart: auto-approves safe commands, asks for dangerous ones
# - critical: only the most destructive operations need approval
export TELEGRAM_SENSITIVITY="${SENSITIVITY_MODE:-smart}"

# Timeout in seconds for Telegram permission requests (default: 300)
# export TELEGRAM_PERMISSION_TIMEOUT="300"
ENVEOF

    chmod 600 "$ENV_FILE"
    success "Created environment file at $ENV_FILE (permissions: 600)"
}

create_wrapper_script() {
    step "Creating wrapper script..."

    cat > "$WRAPPER_SCRIPT" <<'WRAPPEREOF'
#!/bin/bash
# =============================================================================
# hook_permission_telegram_wrapper.sh
# =============================================================================
# Wrapper that loads environment variables and runs the main hook script.
# Generated by install.sh - do not edit manually.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Load environment variables
if [ -f "$ENV_FILE" ]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Telegram hook .env file not found. Run install.sh again."}}'
    exit 0
fi

# Execute the main hook script, passing stdin through
exec bash "$SCRIPT_DIR/hook_permission_telegram.sh"
WRAPPEREOF

    chmod +x "$WRAPPER_SCRIPT"
    success "Created wrapper script at $WRAPPER_SCRIPT"
}

configure_settings() {
    step "Configuring Claude Code settings..."

    local hook_command="bash $WRAPPER_SCRIPT"

    # Create settings.json if it does not exist
    if [ ! -f "$SETTINGS_FILE" ]; then
        info "Creating new settings.json..."
        echo '{}' > "$SETTINGS_FILE"
        success "Created $SETTINGS_FILE"
    fi

    # Validate existing settings.json is valid JSON
    if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
        error "Existing $SETTINGS_FILE is not valid JSON."
        error "Please fix it manually and run the installer again."
        exit 1
    fi

    # Backup settings.json before modifying
    cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    info "Backup created of settings.json"

    # --- Add PreToolUse hook ---
    info "Adding PreToolUse hook..."

    # Build the new hook entry
    local new_hook_entry
    new_hook_entry=$(jq -n --arg cmd "$hook_command" '{
        "hooks": [
            {
                "type": "command",
                "command": $cmd,
                "timeout": 600
            }
        ]
    }')

    # Check if hooks.PreToolUse already exists
    local has_pretool_hook
    has_pretool_hook=$(jq 'has("hooks") and (.hooks | has("PreToolUse"))' "$SETTINGS_FILE" 2>/dev/null || echo "false")

    if [ "$has_pretool_hook" = "true" ]; then
        # Check if our hook command is already present
        local count
        count=$(jq --arg cmd "$hook_command" '
            [.hooks.PreToolUse[].hooks[] | select(.command | test("hook_permission_telegram"))] | length
        ' "$SETTINGS_FILE" 2>/dev/null || echo "0")

        if [ "$count" -gt 0 ]; then
            warn "PreToolUse hook is already configured in settings.json"
            info "Updating the existing hook command..."
            jq --arg cmd "$hook_command" '
                .hooks.PreToolUse |= [
                    .[] | .hooks |= [
                        .[] | if .command | test("hook_permission_telegram") then .command = $cmd else . end
                    ]
                ]
            ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
            success "Updated existing PreToolUse hook."
        else
            info "Appending hook to existing PreToolUse configuration..."
            jq --argjson entry "$new_hook_entry" '
                .hooks.PreToolUse += [$entry]
            ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
            success "Added PreToolUse hook to existing configuration."
        fi
    else
        # Add hooks.PreToolUse from scratch (preserve existing hooks)
        jq --argjson entry "$new_hook_entry" '
            .hooks = (.hooks // {}) | .hooks.PreToolUse = [$entry]
        ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        success "Added PreToolUse hook configuration."
    fi

    # --- Remove old PermissionRequest hook if present ---
    local has_old_hook
    has_old_hook=$(jq 'has("hooks") and (.hooks | has("PermissionRequest"))' "$SETTINGS_FILE" 2>/dev/null || echo "false")
    if [ "$has_old_hook" = "true" ]; then
        local old_count
        old_count=$(jq '
            [.hooks.PermissionRequest[]?.hooks[]? | select(.command | test("hook_permission_telegram"))] | length
        ' "$SETTINGS_FILE" 2>/dev/null || echo "0")

        if [ "$old_count" -gt 0 ]; then
            info "Removing old PermissionRequest hook (migrated to PreToolUse)..."
            jq '
                .hooks.PermissionRequest |= [
                    .[] | select(
                        (.hooks // []) | all(.command | test("hook_permission_telegram") | not)
                    )
                ]
                | if (.hooks.PermissionRequest | length) == 0 then del(.hooks.PermissionRequest) else . end
            ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
            success "Removed old PermissionRequest hook."
        fi
    fi

    # --- Ensure defaultMode is "default" ---
    info "Checking permissions configuration..."
    local current_mode
    current_mode=$(jq -r '.permissions.defaultMode // "not_set"' "$SETTINGS_FILE" 2>/dev/null)

    if [ "$current_mode" != "default" ]; then
        jq '.permissions = (.permissions // {}) | .permissions.defaultMode = "default"' \
            "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        success "Set defaultMode to \"default\" (required for terminal prompts)."
    else
        success "defaultMode is already \"default\"."
    fi

    # --- Add api.telegram.org to sandbox network allowedDomains ---
    info "Checking sandbox network configuration..."

    local telegram_domain="api.telegram.org"

    local has_domain
    has_domain=$(jq --arg domain "$telegram_domain" '
        (.sandbox.network.allowedDomains // []) | index($domain) != null
    ' "$SETTINGS_FILE" 2>/dev/null || echo "false")

    if [ "$has_domain" = "true" ]; then
        success "api.telegram.org is already in sandbox allowedDomains."
    else
        info "Adding api.telegram.org to sandbox network allowedDomains..."
        jq --arg domain "$telegram_domain" '
            .sandbox = (.sandbox // {})
            | .sandbox.network = (.sandbox.network // {})
            | .sandbox.network.allowedDomains = ((.sandbox.network.allowedDomains // []) + [$domain] | unique)
        ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        success "Added api.telegram.org to sandbox allowedDomains."
    fi

    # Final validation
    if jq empty "$SETTINGS_FILE" 2>/dev/null; then
        success "settings.json is valid JSON after modifications."
    else
        error "settings.json is invalid after modifications!"
        error "Restoring from backup..."
        local latest_backup
        latest_backup=$(ls -t "${SETTINGS_FILE}.backup."* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" "$SETTINGS_FILE"
            success "Restored from $latest_backup"
        fi
        exit 1
    fi
}

test_telegram_connection() {
    step "Testing Telegram bot connection..."

    local api_url="https://api.telegram.org/bot${BOT_TOKEN}"

    # Test 1: Verify bot token with getMe
    info "Verifying bot token..."
    local me_response
    me_response=$(curl -s -m 10 "${api_url}/getMe" 2>/dev/null)

    local me_ok
    me_ok=$(echo "$me_response" | jq -r '.ok' 2>/dev/null)

    if [ "$me_ok" != "true" ]; then
        local me_error
        me_error=$(echo "$me_response" | jq -r '.description // "Could not connect to Telegram API"' 2>/dev/null)
        error "Bot token verification failed: $me_error"
        warn "The hook is installed but may not work until the token is fixed."
        warn "Edit $ENV_FILE to update your bot token."
        return 1
    fi

    local bot_username
    bot_username=$(echo "$me_response" | jq -r '.result.username // "unknown"' 2>/dev/null)
    success "Bot verified: @${bot_username}"

    # Test 2: Send a test message
    info "Sending test message to chat $CHAT_ID..."
    local test_message="<b>claude-telegram-hook</b> installed successfully!

This chat will receive permission requests from Claude Code when Telegram mode is enabled.

<b>How to use:</b>
- Safe operations (ls, cat, git status) are auto-approved silently
- Dangerous operations ask in your terminal by default
- Use <code>/telegram</code> in Claude Code to enable Telegram approvals
- Or run: <code>echo 120 > /tmp/claude_telegram_active</code>"

    local send_response
    send_response=$(curl -s -m 10 -X POST "${api_url}/sendMessage" \
        -H "Content-Type: application/json" \
        -d "$(jq -n \
            --arg chat_id "$CHAT_ID" \
            --arg text "$test_message" \
            '{
                chat_id: ($chat_id | tonumber),
                text: $text,
                parse_mode: "HTML"
            }'
        )" 2>/dev/null)

    local send_ok
    send_ok=$(echo "$send_response" | jq -r '.ok' 2>/dev/null)

    if [ "$send_ok" = "true" ]; then
        success "Test message sent! Check your Telegram."
    else
        local send_error
        send_error=$(echo "$send_response" | jq -r '.description // "Unknown error"' 2>/dev/null)
        error "Failed to send test message: $send_error"
        warn "Make sure you have started a conversation with the bot first."
        warn "Send /start to @${bot_username} on Telegram, then run this installer again."
        return 1
    fi
}

print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}=====================================================${NC}"
    echo -e "${GREEN}${BOLD}   Installation complete!${NC}"
    echo -e "${GREEN}${BOLD}=====================================================${NC}"
    echo ""
    echo -e "  ${BOLD}Files installed:${NC}"
    echo -e "    Hook script:    ${CYAN}$HOOK_SCRIPT${NC}"
    echo -e "    Wrapper script: ${CYAN}$WRAPPER_SCRIPT${NC}"
    echo -e "    Environment:    ${CYAN}$ENV_FILE${NC}"
    echo -e "    Settings:       ${CYAN}$SETTINGS_FILE${NC}"
    echo ""
    echo -e "  ${BOLD}Configuration:${NC}"
    echo -e "    Sensitivity: ${CYAN}${SENSITIVITY_MODE:-smart}${NC}"
    echo -e "    Safe operations: ${GREEN}auto-approved silently${NC}"
    echo -e "    Dangerous operations: ${YELLOW}terminal prompt (default)${NC}"
    echo -e "    Telegram: ${DIM}OFF by default${NC}"
    echo ""
    echo -e "  ${BOLD}To enable Telegram approvals:${NC}"
    echo -e "    ${CYAN}/telegram${NC}  (inside Claude Code -- interactive menu)"
    echo -e "    ${CYAN}echo 120 > /tmp/claude_telegram_active${NC}  (from terminal)"
    echo ""
    echo -e "  ${BOLD}Next steps:${NC}"
    echo -e "    ${YELLOW}1.${NC} Restart Claude Code for the hook to take effect."
    echo -e "    ${YELLOW}2.${NC} Safe operations will be auto-approved (no prompt)."
    echo -e "    ${YELLOW}3.${NC} Dangerous operations will ask in the terminal."
    echo -e "    ${YELLOW}4.${NC} Use ${CYAN}/telegram${NC} when you want to approve from your phone."
    echo ""
    echo -e "  ${BOLD}Troubleshooting:${NC}"
    echo -e "    Logs: ${CYAN}/tmp/telegram_claude_hook.log${NC}"
    echo -e "    Test: ${CYAN}echo '{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls\"}}' | bash $WRAPPER_SCRIPT${NC}"
    echo ""
    echo -e "  ${BOLD}Uninstall:${NC}"
    echo -e "    ${CYAN}bash $(basename "$0") --uninstall${NC}"
    echo ""
}

# --- Uninstall ---

uninstall() {
    print_banner
    step "Uninstalling claude-telegram-hook..."
    echo ""

    local removed=0

    # Remove hook script
    if [ -f "$HOOK_SCRIPT" ]; then
        rm "$HOOK_SCRIPT"
        success "Removed $HOOK_SCRIPT"
        removed=1
    fi

    # Remove wrapper script
    if [ -f "$WRAPPER_SCRIPT" ]; then
        rm "$WRAPPER_SCRIPT"
        success "Removed $WRAPPER_SCRIPT"
        removed=1
    fi

    # Remove env file
    if [ -f "$ENV_FILE" ]; then
        rm "$ENV_FILE"
        success "Removed $ENV_FILE"
        removed=1
    fi

    # Remove hook from settings.json (both PreToolUse and PermissionRequest)
    if [ -f "$SETTINGS_FILE" ]; then
        cp "$SETTINGS_FILE" "${SETTINGS_FILE}.backup.$(date +%Y%m%d%H%M%S)"

        for hook_event in "PreToolUse" "PermissionRequest"; do
            local has_hook
            has_hook=$(jq --arg event "$hook_event" 'has("hooks") and (.hooks | has($event))' "$SETTINGS_FILE" 2>/dev/null || echo "false")

            if [ "$has_hook" = "true" ]; then
                jq --arg event "$hook_event" '
                    .hooks[$event] |= [
                        .[] | select(
                            (.hooks // []) | all(.command | test("hook_permission_telegram") | not)
                        )
                    ]
                    | if (.hooks[$event] | length) == 0 then del(.hooks[$event]) else . end
                    | if (.hooks | length) == 0 then del(.hooks) else . end
                ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
                success "Removed $hook_event hook from settings.json"
                removed=1
            fi
        done
    fi

    # Remove flag file
    if [ -f "/tmp/claude_telegram_active" ]; then
        rm -f /tmp/claude_telegram_active
        success "Removed Telegram flag file"
    fi

    # Remove backups
    local backups
    backups=$(ls "${HOOK_SCRIPT}.backup."* "${ENV_FILE}.backup."* 2>/dev/null || true)
    if [ -n "$backups" ]; then
        rm -f "${HOOK_SCRIPT}.backup."* "${ENV_FILE}.backup."* 2>/dev/null
        success "Removed backup files."
    fi

    if [ "$removed" -eq 0 ]; then
        info "Nothing to uninstall. claude-telegram-hook does not appear to be installed."
    else
        echo ""
        success "claude-telegram-hook has been uninstalled."
        warn "Restart Claude Code for changes to take effect."
    fi
}

# --- Main ---

main() {
    # Parse arguments
    case "${1:-}" in
        --uninstall|--remove|uninstall|remove)
            uninstall
            exit 0
            ;;
        --help|-h|help)
            echo "Usage: bash install.sh [--uninstall]"
            echo ""
            echo "Installs the Telegram permission hook for Claude Code."
            echo ""
            echo "Options:"
            echo "  --uninstall    Remove the hook and associated files"
            echo "  --help         Show this help message"
            exit 0
            ;;
    esac

    print_banner

    # Step 1: Check dependencies
    check_dependencies

    # Step 2: Find the hook script source
    find_hook_script
    success "Found hook script: $SOURCE_HOOK"

    # Step 3: Get Telegram configuration from user
    ask_telegram_config

    # Step 4: Smart filtering configuration
    ask_sensitivity_config

    # Step 5: Create directories
    create_directories

    # Step 6: Copy hook script
    copy_hook_script

    # Step 7: Create .env file
    create_env_file

    # Step 8: Create wrapper script
    create_wrapper_script

    # Step 9: Configure settings.json
    configure_settings

    # Step 10: Test Telegram connection
    test_telegram_connection || true

    # Step 11: Print summary
    print_summary
}

main "$@"
