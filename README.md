[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)](#)
[![Telegram Bot API](https://img.shields.io/badge/Telegram-Bot%20API-26A5E4?logo=telegram&logoColor=white)](https://core.telegram.org/bots/api)
[![Claude Code](https://img.shields.io/badge/Claude-Code-cc785c?logo=anthropic&logoColor=white)](https://docs.anthropic.com/en/docs/claude-code)
[![Setup Time](https://img.shields.io/badge/Setup-3%20minutes-brightgreen)](#setup-in-3-minutes)

# claude-telegram-hook

**Control Claude Code from your phone. Walk away from the terminal.**

> [English] | [Espanol](README_ES.md)

---

## Why?

Claude Code is incredible -- until it asks for permission. Every shell command, every file write, every tool call pauses and waits for you to type `y` in the terminal. You're stuck staring at a blinking cursor while your coffee gets cold.

**claude-telegram-hook fixes that.** Permission requests go to your phone. You tap a button. Claude keeps working. You keep living.

### Before

```
You: Refactor the auth module and run the tests.

Claude: I need to run `npm test`. Allow? [y/n]
You: *watching terminal* ... y

Claude: I need to write src/auth.ts. Allow? [y/n]
You: *still watching* ... y

Claude: I need to run `git diff`. Allow? [y/n]
You: *20 minutes later, still here* ... y
```

### After

```
You: Refactor the auth module and run the tests.

*You walk away. Make coffee. Pet the dog.*

Phone buzzes:
  "Claude wants to run: npm test"
  [ Allow ]  [ Deny ]
*Tap Allow from the couch.*

Phone buzzes:
  "Claude wants to write: src/auth.ts"
  [ Allow ]  [ Deny ]
*Tap Allow while sipping coffee.*
```

Claude Code keeps working. You keep living.

---

## What You Need

That's the beauty of this project: almost nothing.

| # | Requirement | Details |
|---|---|---|
| 1 | **A Telegram account** | The app you already have on your phone |
| 2 | **A Telegram bot token** | Created in 30 seconds via @BotFather -- free, instant, no approval |
| 3 | **Your Telegram user ID** | A number you grab once (we'll show you how) |
| 4 | **curl** | Already installed on macOS and virtually every Linux |
| 5 | **jq** | One command to install: `apt install jq` or `brew install jq` |

**That's the whole list.** No servers to run. No databases. No Docker. No cloud accounts. No paid API keys. Telegram's Bot API is free with zero meaningful rate limits for this use case.

The entire hook is **a single Bash script** that talks to Telegram using `curl`. That's it.

---

## Setup in 3 Minutes

### Phase 1: Create Your Telegram Bot (30 seconds)

Open Telegram on your phone or desktop and search for **[@BotFather](https://t.me/BotFather)** -- Telegram's official tool for creating bots.

**Step 1** -- Start a chat with BotFather and send:

```
/newbot
```

**Step 2** -- BotFather replies: *"Alright, a new bot. How are we going to call it? Please choose a name for your bot."*

Type a friendly name:

```
Claude Code Approver
```

**Step 3** -- BotFather replies: *"Good. Now let's choose a username for your bot. It must end in `bot`."*

Pick a unique username:

```
my_claude_approver_bot
```

**Step 4** -- BotFather responds with your token:

```
Done! Congratulations on your new bot. You can now add a description,
about section and profile picture for your bot.

Use this token to access the HTTP API:
7012345678:AAH1bmFnZ2luZy1hLWJvdC10b2tlbi1oZXJl

Keep your token secure and store it safely, it can be used by anyone
to control your bot.
```

> Copy that long string. That is your **`TELEGRAM_BOT_TOKEN`**.

**Step 5** -- Now get your user ID. Search for **[@userinfobot](https://t.me/userinfobot)** on Telegram and send it any message. It replies instantly:

```
Your user ID: 123456789
```

> That number is your **`TELEGRAM_CHAT_ID`**.

**Step 6** -- One last thing: open a chat with **your new bot** and send `/start`. This is required -- bots cannot message you until you initiate contact.

Done. You now have the only two credentials you need.

---

### Phase 2: Install the Hook (60 seconds)

```bash
# Clone the repository
git clone https://github.com/webcomunicasolutions/claude-telegram-hook.git
cd claude-telegram-hook

# Copy the hook to Claude Code's hooks directory
mkdir -p ~/.claude/hooks
cp hook_permission_telegram.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/hook_permission_telegram.sh
```

Now set your credentials. Add these two lines to your `~/.bashrc`, `~/.zshrc`, or `~/.profile`:

```bash
export TELEGRAM_BOT_TOKEN="7012345678:AAH1bmFnZ2luZy1hLWJvdC10b2tlbi1oZXJl"
export TELEGRAM_CHAT_ID="123456789"
```

Reload your shell:

```bash
source ~/.bashrc  # or ~/.zshrc
```

---

### Phase 3: Configure Claude Code (30 seconds)

Open (or create) `~/.claude/settings.json` and add the hook:

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
            "timeout": 600
          }
        ]
      }
    ]
  }
}
```

> **Tip:** The `"matcher": ""` means the hook triggers for all permission requests. You can set it to `"Bash"` to only get Telegram prompts for shell commands, for example.
>
> **About the timeout:** The `600` seconds gives enough room for the retry mechanism (each round is ~120s wait + 60s retry window, up to 2 retries by default). The actual per-round timeout is controlled by `TELEGRAM_PERMISSION_TIMEOUT` (120s default).
>
> **About PermissionRequest:** This hook uses the `PermissionRequest` event, which fires only when Claude Code would show you a permission dialog. This means it won't bother you for tools that are already auto-approved in your permissions.

**That's it. You're done.** Start Claude Code and ask it to do something that needs permission. Your phone will buzz.

---

## How It Works

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant Hook as hook_permission_telegram.sh
    participant API as Telegram Bot API
    participant Phone as Your Phone

    CC->>Hook: PermissionRequest event (JSON via stdin)
    Note over Hook: Parses tool name, command,<br/>file path, or other details

    Hook->>API: sendMessage with inline keyboard<br/>(Allow / Deny buttons)
    API->>Phone: Push notification

    Note over Phone: You see what Claude wants to do<br/>and tap a button

    Phone->>API: Callback: user tapped "Allow"
    API->>Hook: getUpdates returns callback data

    alt Allow
        Hook->>CC: JSON stdout: behavior "allow"
    else Deny
        Hook->>CC: JSON stdout: behavior "deny"
    else No response (timeout)
        Hook->>Phone: ⏰ "Timed out" + [Retry] [Deny]
        Phone->>API: Callback: user tapped "Retry"
        API->>Hook: getUpdates returns "retry"
        Hook->>API: Resend original permission message
        API->>Phone: Push notification (second chance)
    end
```

The entire flow uses Telegram's free Bot API over HTTPS. No webhook server, no open ports, no background processes. The hook script:

1. **Receives** tool call details from Claude Code via stdin as JSON.
2. **Formats** a clear message showing the tool name, command, file path, or other relevant context.
3. **Sends** the message to your Telegram with inline Allow/Deny buttons.
4. **Reminds** you at 60s and 90s with extra notifications if you haven't responded.
5. **Offers retry** if the timeout expires -- tap Retry to get the permission request again.
6. **Returns** the appropriate JSON so Claude Code knows whether to proceed or stop.

---

## Features

- **Phone-based approvals** -- Tap Allow or Deny from anywhere. No terminal needed.
- **Inline keyboard buttons** -- One tap. No typing.
- **Rich context** -- See the exact command, file path, or URL before you decide.
- **Tool-aware formatting** -- Bash commands, file writes, edits, web fetches, and searches are each formatted to highlight the most important details.
- **Smart reminders** -- Phone buzzes again at 60s and 90s if you haven't responded. No more missed notifications.
- **Retry after timeout** -- Missed the window? A Retry button appears so you can get the permission request again without losing your Claude session.
- **Timeout protection** -- No response within the timeout? Action is auto-denied. Claude Code never hangs.
- **Bilingual text fallback** -- Besides buttons, you can type "yes", "no", "si", "dale", "cancel" and more, in English or Spanish.
- **Security validation** -- Only responses from your authorized Chat ID are accepted.
- **Configurable fallback** -- Choose whether errors (network issues, missing tools) result in allow or deny.
- **Structured logging** -- Every decision is logged for debugging and auditing.
- **Zero infrastructure** -- No servers, no databases, no Docker, no cloud.
- **Single file** -- One Bash script. That's the entire hook.
- **Free forever** -- Telegram's Bot API costs nothing.

---

## Known Limitation: Multi-Agent Teams

> **Important:** If you use Claude Code's **Agent Teams** (multi-agent system with `Task` tool and `TeamCreate`), be aware that **permission requests from subagents do NOT trigger the `PermissionRequest` hook**. Instead, they appear as standard terminal prompts in the parent session.
>
> This means subagent actions will show the traditional `"Do you want to proceed? [y/n]"` dialog in your terminal instead of sending a Telegram notification.
>
> **Why?** When a subagent needs permission, the request is delegated to the parent session's UI, bypassing the hook pipeline entirely. This is a current limitation of Claude Code's hook system, not of this project.
>
> **Workaround:** Pre-approve the commands your agents commonly use in your `settings.json` permissions so they don't need to ask:
>
> ```json
> {
>   "permissions": {
>     "allow": [
>       "Bash(export:*)",
>       "Bash(source:*)",
>       "Bash(curl:*)",
>       "Bash(npm:*)",
>       "Bash(node:*)"
>     ]
>   }
> }
> ```
>
> This way, subagents can work autonomously without blocking on terminal prompts.

---

## Configuration

All settings are environment variables with sensible defaults:

| Variable | Required | Default | Description |
|---|---|---|---|
| `TELEGRAM_BOT_TOKEN` | Yes | -- | Bot token from @BotFather |
| `TELEGRAM_CHAT_ID` | Yes | -- | Your Telegram user ID (numeric) |
| `TELEGRAM_PERMISSION_TIMEOUT` | No | `120` | Seconds to wait for a response before offering retry |
| `TELEGRAM_MAX_RETRIES` | No | `2` | How many times to offer a Retry button after timeout |
| `TELEGRAM_FALLBACK_ON_ERROR` | No | `allow` | What happens if the hook errors out: `allow` or `deny` |
| `TELEGRAM_HOOK_LOG` | No | `/tmp/telegram_claude_hook.log` | Log file path. Set to empty string to disable |

### Example: Longer timeout and strict fallback

```bash
export TELEGRAM_BOT_TOKEN="7012345678:AAH1bmFnZ2luZy1hLWJvdC10b2tlbi1oZXJl"
export TELEGRAM_CHAT_ID="123456789"
export TELEGRAM_PERMISSION_TIMEOUT="300"
export TELEGRAM_FALLBACK_ON_ERROR="deny"
export TELEGRAM_HOOK_LOG="$HOME/.claude/logs/telegram_hook.log"
```

---

## Automated Installer

Don't want to do the steps manually? Use the included installer:

```bash
# Option 1: Run directly from the repo
git clone https://github.com/webcomunicasolutions/claude-telegram-hook.git
cd claude-telegram-hook
./install.sh

# Option 2: One-liner
curl -fsSL https://raw.githubusercontent.com/webcomunicasolutions/claude-telegram-hook/main/install.sh | bash
```

The installer will:

- Check that `curl` and `jq` are installed
- Prompt you for your bot token and chat ID
- Copy the hook script to `~/.claude/hooks/`
- Add environment variables to your shell profile
- Update your Claude Code `settings.json`
- Send a test message to your Telegram to confirm everything works

---

## Troubleshooting

### I don't get any message on Telegram

1. **Did you send `/start` to your bot?** Bots can't message you until you initiate. Open a chat with your bot and send `/start`.
2. **Is your token correct?** Test it:
   ```bash
   curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | jq .
   ```
   You should see your bot's info. If you get `"ok": false`, the token is wrong.
3. **Is your Chat ID correct?** Send a message to your bot, then run:
   ```bash
   curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates" | jq '.result[-1].message.chat.id'
   ```
   The returned number must match your `TELEGRAM_CHAT_ID`.

### Claude Code ignores the hook

- Verify your `settings.json` is valid JSON (no trailing commas, proper nesting).
- Make sure the hook is under `PermissionRequest` in your `settings.json`.
- Check the script is executable: `ls -la ~/.claude/hooks/hook_permission_telegram.sh`.
- Restart Claude Code after editing `settings.json`.

### The hook times out before I can respond

The hook sends you reminders at 60s and 90s, and offers a Retry button when the timeout expires. If you still need more time, you can:

1. Increase the per-round timeout:
   ```bash
   export TELEGRAM_PERMISSION_TIMEOUT=300  # 5 minutes per round
   ```
2. Increase the number of retries:
   ```bash
   export TELEGRAM_MAX_RETRIES=3  # 3 retry rounds
   ```
3. Make sure the `timeout` in `settings.json` is high enough to cover all rounds (e.g., `600`).

### Buttons appear but nothing happens when I tap

- Make sure you're tapping buttons on the **most recent** message. Old messages have expired polling sessions.
- Verify your Chat ID matches -- the hook ignores callbacks from unauthorized users.

### "jq: command not found"

```bash
# Debian / Ubuntu / WSL
sudo apt-get install -y jq

# macOS
brew install jq
```

### Claude Code's sandbox blocks the request

Add `api.telegram.org` to the allowed network domains in `settings.json`:

```json
{
  "network": {
    "allowedDomains": ["api.telegram.org"]
  }
}
```

### Checking the logs

The hook writes detailed logs by default:

```bash
tail -f /tmp/telegram_claude_hook.log
```

---

## FAQ

**Q: Is my bot token safe?**
A: Your bot token lets someone send messages *as* your bot, but the hook only ever messages your own Chat ID and only accepts responses from that same ID. Still, treat it like any credential: keep it in environment variables, never commit it to git. If compromised, revoke it instantly in @BotFather with `/revokenewtoken`.

**Q: What if I lose internet on my phone?**
A: The hook times out after `TELEGRAM_PERMISSION_TIMEOUT` seconds. But don't worry -- it will offer you a Retry button (up to `TELEGRAM_MAX_RETRIES` times) so you get another chance. If all retries expire, the action is auto-denied. Claude Code won't hang. You can also respond from Telegram Desktop, Telegram Web, or any device where you're logged in.

**Q: Will this slow Claude Code down?**
A: The hook adds exactly the time it takes you to tap a button. Claude Code already pauses on permission requests -- this just moves the pause from your terminal to your phone.

**Q: Can I approve from multiple devices?**
A: Yes. Telegram delivers to all your logged-in devices. Tap Allow from whichever you see first -- phone, tablet, desktop app, or web client.

**Q: Can I use a Telegram group instead of a direct message?**
A: Yes. Use the group's chat ID as `TELEGRAM_CHAT_ID` and make sure the bot is a member with permission to send messages.

**Q: Does this work on Windows (WSL)?**
A: Yes. Claude Code runs in WSL, which has `curl` and supports `jq`. The hook works identically.

**Q: What about Telegram rate limits?**
A: Telegram allows roughly 30 messages per second per bot. For a single developer approving Claude Code actions, you'll never come close.

**Q: Can I auto-approve certain tools?**
A: Yes. Change the `"matcher"` in your `settings.json` to only match tools you want Telegram approval for (e.g., `"Bash"` for shell commands only). Read-only tools like `Read`, `Glob`, and `Grep` can be left to the default terminal flow or auto-approved in Claude Code's permissions.

**Q: Can I customize the message format?**
A: Absolutely. The message template lives inside the hook script. Edit it to change the layout, add timestamps, include session IDs, or anything else you want.

**Q: Does this work with Claude Code teams or shared sessions?**
A: Each person sets up their own bot and chat ID. The hook runs locally on whoever launched Claude Code.

**Q: Does this work with Claude Code's multi-agent teams (Agent Teams)?**
A: Partially. The main session's permission requests go to Telegram as expected. However, **subagent permission requests bypass the hook** and fall back to terminal prompts. This is a Claude Code limitation, not ours. See the [Known Limitation](#known-limitation-multi-agent-teams) section above for details and workarounds.

---

## Bonus: Use It Beyond Claude Code

The Telegram approval pattern is not limited to Claude Code. We ship a **standalone Bash library** (`telegram_approve.sh`) you can `source` from any script -- backup jobs, deploys, cron tasks, server maintenance, anything.

### Quick Start

```bash
source telegram_approve.sh

# Yes/No question (returns exit code 0 or 1)
if telegram_ask "<b>Upload backup?</b>" "Upload" "Skip"; then
    echo "Approved"
fi

# Multiple choice (returns chosen callback_data on stdout)
choice=$(telegram_choose "Disk at 92%. What to do?" \
    "Clean logs" "clean" \
    "Restart" "restart" \
    "Ignore" "skip")

# Simple notification (no buttons)
telegram_send "<b>Cron job finished</b> -- 0 errors"
```

### Available Functions

| Function | What it does | Returns |
|---|---|---|
| `telegram_ask "text" ["Yes"] ["No"]` | Yes/No with buttons | Exit code: 0=yes, 1=no |
| `telegram_choose "text" "Btn" "data" ...` | Multiple choice buttons | stdout: chosen `callback_data` |
| `telegram_send "text"` | Plain notification | -- |
| `telegram_send_buttons "text" "B1" "d1" "B2" "d2"` | Custom 2-button message | -- |

### Examples

See the [`examples/`](examples/) directory:

| Script | What it does |
|---|---|
| [`backup_with_approval.sh`](examples/backup_with_approval.sh) | Creates a backup, asks before uploading |
| [`deploy_with_approval.sh`](examples/deploy_with_approval.sh) | Shows git info, asks before deploying |
| [`server_maintenance.sh`](examples/server_maintenance.sh) | Disk alert with multiple action choices |
| [`cron_notification.sh`](examples/cron_notification.sh) | Simple notification after a cron job |

```bash
# Try an example
export TELEGRAM_BOT_TOKEN="your-token"
export TELEGRAM_CHAT_ID="your-chat-id"
bash examples/backup_with_approval.sh /var/www
```

---

## Contributing

Contributions are welcome. This project prizes simplicity above everything -- a PR that adds a server, a database, or a `package.json` will be politely declined.

Great contributions:

- Bug fixes
- Better message formatting
- New language support for text responses
- Documentation improvements
- Translations (see [README_ES.md](README_ES.md))

```bash
# Fork, clone, branch
git checkout -b my-improvement

# Test manually by piping JSON to the hook
echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"},"session_id":"test"}' \
  | bash hook_permission_telegram.sh

# Commit and open a PR
git commit -m "Describe what you improved"
git push origin my-improvement
```

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details.

---

## License

[MIT](LICENSE) -- Use it however you want.

---

## Built With

| | |
|---|---|
| [Bash](https://www.gnu.org/software/bash/) | The hook script itself |
| [Telegram Bot API](https://core.telegram.org/bots/api) | Free messaging infrastructure |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Anthropic's CLI -- the permission system we extend |
| [curl](https://curl.se/) | HTTP requests to Telegram |
| [jq](https://jqlang.github.io/jq/) | JSON parsing |

---

<p align="center">
<b>Stop watching the terminal. Start living.</b>
<br><br>
<a href="https://github.com/webcomunicasolutions/claude-telegram-hook">github.com/webcomunicasolutions/claude-telegram-hook</a>
</p>
