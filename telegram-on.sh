#!/bin/bash
# Enable Telegram approval mode
# Usage: source telegram-on.sh [delay_seconds]
#   or:  ./telegram-on.sh [delay_seconds]

DELAY="${1:-120}"
echo "$DELAY" > /tmp/claude_telegram_active
echo "Telegram ON (delay: ${DELAY}s)"
