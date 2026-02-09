# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-02-08

### Added
- **Smart filtering**: Three sensitivity modes (`smart`, `critical`, `all`) via `TELEGRAM_SENSITIVITY`
  - `smart` (default): Auto-approves safe operations (ls, cat, git status, Read, Grep, etc.), dangerous ones go to terminal or Telegram
  - `critical`: Only the most destructive operations (rm, sudo, git push, etc.) require approval
  - `all`: Everything needs approval (no auto-approve)
- **Risk classification engine**: Functions `classify_risk`, `is_safe_bash_command`, `is_dangerous_command`, `has_dangerous_heredoc`, `touches_sensitive_path`, `has_dangerous_subcommand`
- **Compound command analysis**: Splits piped/chained commands and flags the chain as dangerous if any sub-command is dangerous
- **Heredoc/inline script scanning**: Detects dangerous patterns in Python and Node.js inline scripts (os.remove, subprocess, shutil.rmtree, fs.unlinkSync, etc.)
- **Sensitive path detection**: Blocks auto-approval for writes to `.env`, `.ssh/*`, `credentials`, `/etc/*`, and similar paths
- **Telegram toggle**: Simple on/off control via flag file (`/tmp/claude_telegram_active`)
  - Enable: `echo 120 > /tmp/claude_telegram_active` (or use `/telegram` slash command)
  - Disable: `rm -f /tmp/claude_telegram_active` (or use `/telegram` slash command)
- **`/telegram` slash command** for Claude Code: interactive menu to toggle Telegram on/off from within a session
- Helper scripts: `telegram-on.sh` and `telegram-off.sh` for quick toggle
- **tmux hybrid mode**: When tmux is available and Telegram is enabled, terminal prompt + background Telegram escalation
- **Blocking Telegram mode**: When tmux is not available and Telegram is enabled, classic blocking Telegram with buttons (v0.3 behavior)

### Changed
- **Hook event changed from `PermissionRequest` to `PreToolUse`**: fires on every tool use, enabling smart filtering to auto-approve safe operations silently
- Default `TELEGRAM_PERMISSION_TIMEOUT` increased from `120` to `300` (5 minutes)
- Hook main flow simplified to: Smart Filter -> Terminal prompt (default) or Telegram (when enabled)
- Removed local popup/dialog system (no more `TELEGRAM_LOCAL_DELAY`)
- `defaultMode: "default"` required in settings.json for terminal prompts to work correctly

### Removed
- Local dialog / PC popup feature (`TELEGRAM_LOCAL_DELAY` env var)
- Platform-specific popup code (WSL2 powershell, zenity, osascript)

## [0.3.0] - 2026-02-07

### Added
- `telegram_approve.sh`: standalone reusable library for any Bash script (not just Claude Code)
- Functions: `telegram_ask`, `telegram_choose`, `telegram_send`, `telegram_send_buttons`
- `examples/` directory with 4 ready-to-use scripts:
  - `backup_with_approval.sh` - Backup with upload confirmation
  - `deploy_with_approval.sh` - Deploy with approval gate
  - `server_maintenance.sh` - Disk alert with multiple choices
  - `cron_notification.sh` - Simple post-task notification
- "Bonus: Use It Beyond Claude Code" section in both READMEs

## [0.2.0] - 2026-02-07

### Added
- Smart reminders: phone buzzes again at 60s and 90s if no response
- Retry mechanism: after timeout, offers a Retry/Deny button instead of immediately denying
- Configurable max retries via `TELEGRAM_MAX_RETRIES` environment variable (default: 2)
- Retry counter shown in timeout messages ("Retry 1 of 2")
- Documentation: known limitation with multi-agent teams (subagent permissions bypass hooks)
- Documentation: workaround for pre-approving subagent commands

### Changed
- Recommended `settings.json` timeout increased from 130 to 600 to accommodate retry rounds
- Timeout flow: instead of instant denial, now offers up to 2 retry rounds before final denial

## [0.1.0] - 2026-02-07

### Added
- Telegram inline keyboard buttons (Allow / Deny) for permission requests
- Text fallback with bilingual support (English and Spanish)
- HTML escaping for safe rendering of commands and file paths
- Security validation: only accepts responses from the authorized Chat ID
- Configurable timeout with auto-deny (default: 120 seconds)
- Configurable fallback policy (allow or deny) on error
- Structured logging to file
- Tool-aware messages for Bash, Write, Edit, WebFetch, WebSearch
- Callback acknowledgment for immediate button feedback
- Interactive installer (`install.sh`) with dependency checks and Telegram test
- Uninstaller (`install.sh --uninstall`) with settings.json cleanup
- Environment file (`.env`) with restricted permissions (600)
- Wrapper script for loading environment variables automatically
- Automatic backup of `settings.json` before modifications

[0.4.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.4.0
[0.3.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.3.0
[0.2.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.2.0
[0.1.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.1.0
