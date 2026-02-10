---
name: telegram
description: Toggle Telegram approval mode on/off for the permission hook
user_invocable: true
---

# /telegram - Toggle Telegram Approval Mode

When the user invokes `/telegram`, do the following:

## Behavior

### Without arguments (`/telegram`)
1. Check current status
2. Toggle: if ON -> turn OFF, if OFF -> turn ON
3. Confirm with one short line

### With arguments (`/telegram on`, `/telegram off`)
Execute directly without menu.

## Implementation

The Telegram mode is controlled by a flag file at `/tmp/claude_telegram_active`.

### Check status
```bash
[ -f /tmp/claude_telegram_active ] && echo "ON" || echo "OFF"
```

### Enable
```bash
touch /tmp/claude_telegram_active
```

### Disable
```bash
rm -f /tmp/claude_telegram_active
```

## Rules
- Always run bash commands with `dangerouslyDisableSandbox: true`
- Respond in Spanish
- Keep confirmations short: one line
- It's a simple toggle: ON/OFF, nothing else
