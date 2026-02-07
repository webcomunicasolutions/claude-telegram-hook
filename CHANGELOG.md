# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.3.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.3.0
[0.2.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.2.0
[0.1.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.1.0
