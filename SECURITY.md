# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in claude-telegram-hook, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please email: **security@webcomunica.com**

Or use [GitHub's private vulnerability reporting](https://github.com/webcomunicasolutions/claude-telegram-hook/security/advisories/new).

### What to include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response timeline

- **Acknowledgment**: within 48 hours
- **Initial assessment**: within 7 days
- **Fix or mitigation**: as soon as reasonably possible

## Security Considerations

This project handles sensitive data (Telegram bot tokens). Please follow these practices:

1. **Never commit your bot token or chat ID** to version control.
2. Store credentials in environment variables or the `.env` file (permissions 600).
3. The `.env` file is excluded from git via `.gitignore`.
4. The hook validates that responses come only from the authorized `CHAT_ID`.
5. Set `TELEGRAM_FALLBACK_ON_ERROR` to `"deny"` in production environments.
