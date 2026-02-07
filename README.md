[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Telegram Bot API](https://img.shields.io/badge/Telegram-Bot%20API-26A5E4?logo=telegram&logoColor=white)](https://core.telegram.org/bots/api)

# claude-telegram-hook

**Approve or deny Claude Code permissions from your phone via Telegram.**

A Bash hook for [Claude Code](https://claude.ai/code) (Anthropic's official CLI) that replaces the terminal permission dialog with Telegram inline buttons. When Claude Code needs your approval to run a command, edit a file, or perform any action that requires permission, it sends a message to your Telegram with Allow/Deny buttons and waits for your response.

---

## The Problem

When Claude Code needs permission to execute an action -- running a shell command, writing a file, making a web request -- it pauses and displays a confirmation dialog in the terminal. You have to be physically watching the terminal to respond.

This creates friction when:

- You step away from your desk while Claude Code works on a long task
- You are working in another application and miss the prompt
- You have multiple Claude Code sessions running and cannot monitor all of them
- You want to let Claude Code work autonomously while you review permissions from anywhere

## The Solution

**claude-telegram-hook** intercepts every permission request and routes it to your Telegram chat. You receive a notification on your phone with full context about what Claude Code wants to do, tap a button to allow or deny, and Claude Code continues immediately. No terminal watching required.

---

## How It Works (Flow)

```
+-------------------+       +-------------------------+       +-------------------+
|                   |       |                         |       |                   |
|   Claude Code     |       |   hook_permission_      |       |   Telegram        |
|                   |       |   telegram.sh           |       |   Bot API         |
|   Wants to run:   |       |                         |       |                   |
|   "git push"      +------>+  1. Reads JSON stdin    +------>+  sendMessage      |
|                   | stdin |  2. Builds message      | HTTPS |  with inline      |
|                   |       |  3. Sends to Telegram   |       |  keyboard         |
|                   |       |                         |       |                   |
|                   |       |                         |       +--------+----------+
|                   |       |                         |                |
|                   |       |                         |                v
|                   |       |                         |
|                   |       |                         |       +-------------------+
|                   |       |                         |       |                   |
|                   |       |                         |       |   Your Phone      |
|                   |       |                         |       |                   |
|                   |       |                         |       |   "Claude Code    |
|                   |       |                         |       |    needs perm."   |
|                   |       |                         |       |                   |
|                   |       |                         |       |  [Allow] [Deny]   |
|                   |       |                         |       |                   |
|                   |       |                         |       +--------+----------+
|                   |       |                         |                |
|                   |       |                         |                v
|                   |       |                         |       +-------------------+
|                   |       |                         |       |                   |
|   Receives        |       |  4. Polls getUpdates   |       |   Telegram        |
|   decision:       +<------+  5. Parses response    +<------+   Bot API         |
|   allow / deny    | stdout|  6. Returns JSON       | HTTPS |   (callback)      |
|                   |       |                         |       |                   |
|   (continues or   |       |                         |       |                   |
|    stops action)  |       |                         |       |                   |
+-------------------+       +-------------------------+       +-------------------+
```

---

## Features

- **Inline keyboard buttons** -- tap Allow or Deny directly in Telegram, no typing required
- **Text fallback** -- also accepts typed responses ("yes", "no", "si", "ok", "cancel", etc.)
- **Bilingual support** -- recognizes approval/denial in both English and Spanish
- **HTML escaping** -- safely renders commands and file paths in Telegram messages without breaking HTML parse mode
- **Security validation** -- only accepts responses from your authorized Chat ID; ignores messages from other users
- **Configurable timeout** -- auto-denies after a configurable period (default: 120 seconds) so Claude Code is never stuck waiting indefinitely
- **Fallback policy** -- configurable behavior (allow or deny) when the hook encounters an error (network failure, missing dependencies, etc.)
- **Structured logging** -- all hook activity is logged to a file for debugging and auditing
- **Tool-aware messages** -- formats the permission request differently for Bash commands, file writes, file edits, web fetches, and web searches, showing the most relevant details for each
- **Callback acknowledgment** -- responds to Telegram callback queries so buttons show immediate feedback

---

## Prerequisites

| Requirement | Purpose |
|-------------|---------|
| [curl](https://curl.se/) | HTTP requests to the Telegram Bot API |
| [jq](https://jqlang.github.io/jq/) | JSON parsing for hook input/output and API responses |
| A Telegram bot | Created via [@BotFather](https://t.me/BotFather) (see [instructions below](#how-to-create-a-telegram-bot)) |
| [Claude Code](https://claude.ai/code) | Anthropic's CLI with hook support |

Most Linux distributions and macOS include `curl` by default. To install `jq`:

```bash
# Debian / Ubuntu / WSL
sudo apt-get install -y jq

# macOS
brew install jq

# Verify
jq --version
```

---

## Quick Install

### 1. Clone the repository

```bash
git clone https://github.com/webcomunicasolutions/claude-telegram-hook.git
cd claude-telegram-hook
```

### 2. Copy the hook script to your Claude Code hooks directory

```bash
mkdir -p ~/.claude/hooks
cp hook_permission_telegram.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/hook_permission_telegram.sh
```

### 3. Set your environment variables

Add these to your shell profile (`~/.bashrc`, `~/.zshrc`, or equivalent):

```bash
export TELEGRAM_BOT_TOKEN="your-bot-token-here"
export TELEGRAM_CHAT_ID="your-chat-id-here"
```

Then reload your shell:

```bash
source ~/.bashrc   # or source ~/.zshrc
```

### 4. Configure the hook in Claude Code

Add the following to your `~/.claude/settings.json` file. If the file already exists, merge the `hooks` section into your existing configuration:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/hook_permission_telegram.sh",
            "timeout": 130
          }
        ]
      }
    ]
  }
}
```

**About the matcher:** Setting `"matcher": ""` (empty string) means the hook triggers for all tool permission requests. You can restrict it to specific tools (e.g., `"Bash"`, `"Write"`) if you only want Telegram approval for certain actions.

**About the timeout:** The `timeout` value (130 seconds) should be slightly higher than the `TELEGRAM_PERMISSION_TIMEOUT` (default 120 seconds) to give the script time to handle the timeout gracefully before Claude Code kills it.

### 5. Allow Telegram API access in the sandbox

If you use Claude Code's network sandbox, add `api.telegram.org` to the allowed domains in your `~/.claude/settings.json`:

```json
{
  "permissions": {
    "allow": [
      "Bash(command:bash ~/.claude/hooks/hook_permission_telegram.sh)"
    ]
  },
  "network": {
    "allowedDomains": [
      "api.telegram.org"
    ]
  }
}
```

### 6. Restart Claude Code

Close and reopen Claude Code for the new hook configuration to take effect.

### 7. Test it

Start a Claude Code session and ask it to do something that requires permission. You should receive a Telegram message with inline buttons.

---

## Configuration

All configuration is done through environment variables. The script uses sensible defaults if a variable is not set.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TELEGRAM_BOT_TOKEN` | Yes | -- | Your Telegram bot token from @BotFather |
| `TELEGRAM_CHAT_ID` | Yes | -- | Your personal Telegram Chat ID (numeric) |
| `TELEGRAM_PERMISSION_TIMEOUT` | No | `120` | Seconds to wait for a response before auto-denying |
| `TELEGRAM_FALLBACK_ON_ERROR` | No | `allow` | What to do if the hook encounters an error: `allow` or `deny` |
| `TELEGRAM_HOOK_LOG` | No | `/tmp/telegram_claude_hook.log` | Path to the log file. Set to empty string to disable logging |

Example configuration in your shell profile:

```bash
export TELEGRAM_BOT_TOKEN="1234567890:ABCdefGHIjklMNOpqrsTUVwxyz"
export TELEGRAM_CHAT_ID="123456789"
export TELEGRAM_PERMISSION_TIMEOUT="180"
export TELEGRAM_FALLBACK_ON_ERROR="deny"
export TELEGRAM_HOOK_LOG="$HOME/.claude/logs/telegram_hook.log"
```

---

## How to Create a Telegram Bot

1. Open Telegram and search for [@BotFather](https://t.me/BotFather), or tap the link directly.

2. Start a conversation and send the command:
   ```
   /newbot
   ```

3. BotFather will ask you for a **display name** for your bot. Choose any name you like (e.g., "Claude Code Permissions").

4. BotFather will ask you for a **username** for your bot. This must end in `bot` (e.g., `claude_code_perms_bot`).

5. BotFather will respond with your **bot token**. It looks like this:
   ```
   1234567890:ABCdefGHIjklMNOpqrsTUVwxyz
   ```
   Save this token securely. This is your `TELEGRAM_BOT_TOKEN`.

6. **Important:** Open a conversation with your new bot in Telegram and send it any message (e.g., `/start`). The bot cannot send you messages until you initiate contact first.

---

## How to Find Your Chat ID

After you have sent at least one message to your bot, run this command in your terminal (replace the token with your own):

```bash
curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates" | jq '.result[0].message.from.id'
```

This returns your numeric Chat ID (e.g., `123456789`). This is your `TELEGRAM_CHAT_ID`.

Alternative method: search for [@userinfobot](https://t.me/userinfobot) on Telegram and send it any message. It will reply with your user ID.

---

## How It Works (Technical)

This hook uses the **PermissionRequest** event in Claude Code's hook system.

### The PermissionRequest Hook Lifecycle

1. **Trigger:** Claude Code is about to perform an action that requires user permission (running a shell command, writing a file, etc.). Instead of showing a terminal dialog, it invokes all registered `PermissionRequest` hooks.

2. **Input:** The hook receives a JSON payload on stdin containing the `tool_name`, `tool_input` (the specific action details), and `session_id`.

3. **Processing:** The hook script:
   - Parses the JSON input to extract the tool name and relevant details
   - Builds an HTML-formatted Telegram message describing the action
   - Fetches the latest Telegram update offset to ignore old messages
   - Sends the message to your Telegram chat with inline Allow/Deny buttons
   - Polls the Telegram Bot API (`getUpdates`) using long polling, waiting for your response

4. **Response:** When you tap a button or type a response:
   - The script validates that the response came from your authorized Chat ID
   - It parses the response (button callback data or free-text input)
   - It outputs a JSON decision to stdout in the format Claude Code expects

5. **Decision format:**
   - Allow: `{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}`
   - Deny: `{"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "deny", "message": "reason"}}}`

6. **Claude Code acts:** Based on the JSON output, Claude Code either proceeds with the action or aborts it.

### PermissionRequest vs PreToolUse

This hook is designed for the **PermissionRequest** event, which is the recommended approach for permission management. It fires specifically when Claude Code would show a permission dialog.

It can also be adapted for **PreToolUse**, which fires before every tool invocation regardless of whether permission is needed. If you use PreToolUse, the JSON output format is slightly different (`{"decision": "approve"}` / `{"decision": "deny", "reason": "..."}`). See the Claude Code hooks documentation for details.

### Bilingual Text Response Support

When using text input instead of buttons, the hook recognizes approval and denial keywords in both English and Spanish:

| Decision | Recognized words |
|----------|-----------------|
| Allow | yes, y, ok, go, approve, si, dale, vale, adelante, aprobar |
| Deny | no, n, cancel, deny, nope, cancelar, rechazar |

---

## Troubleshooting

### The hook does not trigger

- Verify that `~/.claude/settings.json` contains the hook configuration under the correct event name (`PermissionRequest`).
- Ensure the script path in the configuration matches the actual file location.
- Restart Claude Code after modifying `settings.json`.
- Check that the script is executable: `chmod +x ~/.claude/hooks/hook_permission_telegram.sh`.

### No message appears in Telegram

- Confirm that `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are set in your environment. Run `echo $TELEGRAM_BOT_TOKEN` to verify.
- Make sure you have started a conversation with your bot (sent it at least one message).
- Test the Telegram API directly:
  ```bash
  curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=Test message"
  ```
- Check the log file (default: `/tmp/telegram_claude_hook.log`) for error details.

### Message appears but buttons do not work

- Make sure you are tapping the buttons in the most recent message. Buttons on older messages may correspond to expired polling sessions.
- Check that your Chat ID matches the one configured in `TELEGRAM_CHAT_ID`. The hook ignores callbacks from unauthorized users.

### Timeout occurs before you can respond

- Increase the `TELEGRAM_PERMISSION_TIMEOUT` environment variable (e.g., `export TELEGRAM_PERMISSION_TIMEOUT=300` for 5 minutes).
- Also increase the `timeout` value in your `settings.json` hook configuration to be higher than the permission timeout.

### "jq not installed" or "curl not installed" errors

- Install the missing dependency:
  ```bash
  sudo apt-get install -y jq curl
  ```
- When the hook cannot find its dependencies, it falls back to the configured `TELEGRAM_FALLBACK_ON_ERROR` policy (default: allow).

### Claude Code's sandbox blocks the request

- Add `api.telegram.org` to the `allowedDomains` in your `settings.json` network configuration.
- Make sure the hook command itself is allowed in the sandbox permissions.

### Log file inspection

The hook writes detailed logs to `/tmp/telegram_claude_hook.log` by default. To follow the log in real time:

```bash
tail -f /tmp/telegram_claude_hook.log
```

---

## Contributing

Contributions are welcome. To get started:

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-improvement`.
3. Make your changes and test them manually by piping JSON to the hook script:
   ```bash
   echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"test-123"}' \
     | bash hook_permission_telegram.sh
   ```
4. Commit your changes with a clear message.
5. Open a Pull Request describing what you changed and why.

### Ideas for contributions

- Support for additional languages in text response parsing
- Customizable message templates
- Group chat support with user mention
- Notification hooks for PostToolUse and Stop events
- Docker container for running the bot as a persistent service
- Rate limiting and "approve all for N minutes" mode

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Built With

| Technology | Role |
|------------|------|
| [Claude Code](https://claude.ai/code) | Anthropic's CLI for Claude -- provides the hook system |
| [Telegram Bot API](https://core.telegram.org/bots/api) | Messaging platform for delivering permission requests |
| [Bash](https://www.gnu.org/software/bash/) | Shell scripting language for the hook implementation |
| [curl](https://curl.se/) | HTTP client for Telegram API requests |
| [jq](https://jqlang.github.io/jq/) | JSON processor for parsing hook input and API responses |
