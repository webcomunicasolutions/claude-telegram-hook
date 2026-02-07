# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/webcomunicasolutions/claude-telegram-hook/releases/tag/v0.1.0
