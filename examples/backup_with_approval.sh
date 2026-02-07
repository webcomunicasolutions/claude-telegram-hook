#!/bin/bash
# =============================================================================
# Example: Backup script with Telegram approval
# =============================================================================
# Creates a backup and asks via Telegram before uploading to remote storage.
#
# Usage:
#   export TELEGRAM_BOT_TOKEN="your-token"
#   export TELEGRAM_CHAT_ID="your-chat-id"
#   bash backup_with_approval.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../telegram_approve.sh"

# --- Your backup logic ---
BACKUP_DIR="/tmp"
BACKUP_FILE="${BACKUP_DIR}/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
SOURCE_DIR="${1:-/var/www/html}"

echo "Creating backup of ${SOURCE_DIR}..."
tar czf "$BACKUP_FILE" "$SOURCE_DIR" 2>/dev/null

SIZE=$(du -h "$BACKUP_FILE" | cut -f1)

# --- Ask via Telegram ---
if telegram_ask "<b>Backup ready</b>

Server: <code>$(hostname)</code>
Source: <code>${SOURCE_DIR}</code>
File: <code>${BACKUP_FILE}</code>
Size: ${SIZE}

Upload to remote storage?" "Upload" "Skip"; then

    echo "User approved -- uploading..."
    # Replace with your actual upload command:
    # aws s3 cp "$BACKUP_FILE" s3://my-bucket/backups/
    # scp "$BACKUP_FILE" user@server:/backups/
    # rclone copy "$BACKUP_FILE" remote:backups/

    telegram_send "Backup uploaded successfully"
    echo "Done."
else
    echo "User skipped upload."
    telegram_send "Backup kept locally at <code>${BACKUP_FILE}</code>"
fi
