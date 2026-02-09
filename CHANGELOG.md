# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-02-08

### Added
- **Smart filtering**: Three sensitivity modes (`smart`, `critical`, `all`) via `TELEGRAM_SENSITIVITY`
  - `smart` (default): Auto-approves safe operations (ls, cat, git status, Read, Grep, etc.), sends dangerous ones to approval
  - `critical`: Only the most destructive operations (rm, sudo, git push, etc.) require approval
  - `all`: Everything goes to Telegram (v0.3 backward-compatible behavior)
- **Risk classification engine**: Functions `classify_risk`, `is_safe_bash_command`, `is_dangerous_command`, `has_dangerous_heredoc`, `touches_sensitive_path`, `has_dangerous_subcommand`
- **Compound command analysis**: Splits piped/chained commands and flags the chain as dangerous if any sub-command is dangerous
- **Heredoc/inline script scanning**: Detects dangerous patterns in Python and Node.js inline scripts (os.remove, subprocess, shutil.rmtree, fs.unlinkSync, etc.)
- **Sensitive path detection**: Blocks auto-approval for writes to `.env`, `.ssh/*`, `credentials`, `/etc/*`, and similar paths
- **Local dialog (PC-first)**: Native popup on your PC before escalating to Telegram, via `TELEGRAM_LOCAL_DELAY`
  - WSL2: Windows popup via `powershell.exe` + `WScript.Shell.Popup()`
  - Linux: `zenity --question` with timeout
  - macOS: `osascript` dialog with timeout
  - No GUI: Skips to Telegram directly
- New environment variables: `TELEGRAM_SENSITIVITY`, `TELEGRAM_LOCAL_DELAY`
- Installer: new steps for sensitivity mode and local dialog configuration
- FAQ entries for smart filtering, sensitivity modes, and local dialog in both READMEs

### Changed
- Default `TELEGRAM_PERMISSION_TIMEOUT` increased from `120` to `300` (5 minutes)
- Hook main flow restructured into three layers: Filter -> Local Dialog -> Telegram
- Installer summary now shows sensitivity mode and local dialog timeout

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
