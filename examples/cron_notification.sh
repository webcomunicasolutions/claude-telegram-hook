#!/bin/bash
# =============================================================================
# Example: Cron job notification (no approval needed)
# =============================================================================
# Sends a summary to Telegram after a cron job finishes.
# No buttons, just a notification.
#
# Usage:
#   export TELEGRAM_BOT_TOKEN="your-token"
#   export TELEGRAM_CHAT_ID="your-chat-id"
#   bash cron_notification.sh
#
# Crontab example (daily at 3am):
#   0 3 * * * /path/to/cron_notification.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../telegram_approve.sh"

# --- Your cron task ---
START=$(date +%s)

# Replace with your actual task:
# pg_dump mydb > /backups/mydb.sql
# python3 /scripts/cleanup.py
# ./sync_data.sh
sleep 2  # Simulated task

END=$(date +%s)
DURATION=$((END - START))

# --- Send notification ---
telegram_send "<b>Cron job completed</b>

Task: Database cleanup
Server: <code>$(hostname)</code>
Duration: ${DURATION}s
Time: $(date '+%Y-%m-%d %H:%M:%S')
Status: OK"
