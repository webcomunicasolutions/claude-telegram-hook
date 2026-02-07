#!/bin/bash
# =============================================================================
# Example: Server maintenance with multiple Telegram options
# =============================================================================
# Checks disk usage and lets you choose an action from your phone.
#
# Usage:
#   export TELEGRAM_BOT_TOKEN="your-token"
#   export TELEGRAM_CHAT_ID="your-chat-id"
#   bash server_maintenance.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../telegram_approve.sh"

# --- Check disk usage ---
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')

# Only alert if above 80%
USAGE_NUM=$(echo "$DISK_USAGE" | tr -d '%')
if [ "$USAGE_NUM" -lt 80 ]; then
    echo "Disk usage at ${DISK_USAGE} -- no action needed."
    exit 0
fi

# --- Ask what to do ---
choice=$(telegram_choose "<b>Disk usage alert</b>

Server: <code>$(hostname)</code>
Usage: <b>${DISK_USAGE}</b>
Available: ${DISK_AVAIL}

What should we do?" \
    "Clean old logs" "clean_logs" \
    "Clean temp files" "clean_tmp" \
    "Ignore" "skip")

case "$choice" in
    clean_logs)
        COUNT=$(find /var/log -name "*.log.gz" -mtime +30 | wc -l)
        find /var/log -name "*.log.gz" -mtime +30 -delete 2>/dev/null
        telegram_send "Cleaned ${COUNT} old log files"
        echo "Logs cleaned."
        ;;
    clean_tmp)
        COUNT=$(find /tmp -type f -mtime +7 | wc -l)
        find /tmp -type f -mtime +7 -delete 2>/dev/null
        telegram_send "Cleaned ${COUNT} temp files older than 7 days"
        echo "Temp files cleaned."
        ;;
    skip)
        telegram_send "OK, disk alert ignored"
        echo "Skipped."
        ;;
    timeout)
        echo "No response -- no action taken."
        ;;
esac
