#!/bin/bash
# =============================================================================
# Example: Deploy to production with Telegram approval
# =============================================================================
# Checks the current git state and asks for approval before deploying.
#
# Usage:
#   export TELEGRAM_BOT_TOKEN="your-token"
#   export TELEGRAM_CHAT_ID="your-chat-id"
#   bash deploy_with_approval.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../telegram_approve.sh"

export TELEGRAM_TIMEOUT=300  # 5 minutes to decide on a deploy

# --- Gather info ---
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT=$(git log -1 --pretty=format:"%h - %s" 2>/dev/null || echo "unknown")
SERVER="${DEPLOY_SERVER:-production}"

# --- Ask via Telegram ---
if telegram_ask "<b>Deploy to production</b>

Branch: <code>${BRANCH}</code>
Commit: <code>${COMMIT}</code>
Server: <code>${SERVER}</code>

Proceed with deploy?" "Deploy" "Cancel"; then

    echo "Deploying..."
    telegram_send "Deploying <code>${COMMIT}</code> to ${SERVER}..."

    # Replace with your actual deploy command:
    # ./deploy.sh
    # docker-compose pull && docker-compose up -d
    # kubectl apply -f deployment.yaml
    sleep 2  # Simulated deploy

    telegram_send "Deploy complete"
    echo "Deploy finished."
else
    echo "Deploy cancelled."
    telegram_send "Deploy cancelled by user"
fi
