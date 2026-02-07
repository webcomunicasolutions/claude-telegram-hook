# Contributing to claude-telegram-hook

Thanks for your interest in contributing! Here are some guidelines to help you get started.

## Reporting Issues

- Open a GitHub issue with a clear, descriptive title.
- Include steps to reproduce the problem.
- Attach relevant log output (sanitize any tokens or secrets first).
- Mention your OS and shell version (e.g., bash 5.1 on Ubuntu 22.04).

## Submitting Pull Requests

1. Fork the repository and create a feature branch from `main`.
2. Keep your changes focused -- one PR per feature or fix.
3. Write a clear description of what your PR does and why.
4. Make sure existing functionality still works before submitting.

## Code Style

- All scripts are written in **Bash**.
- Run [ShellCheck](https://www.shellcheck.net/) on your scripts before submitting. No warnings should remain.
- Use meaningful variable names and add comments for non-obvious logic.
- Keep functions short and single-purpose.

## Testing Your Changes

Test your changes locally by simulating hook input. Pipe JSON into the hook script:

```bash
echo '{"session_id":"test","tool_name":"Bash","tool_input":{"command":"git push"}}' | ./scripts/hook_permission_telegram.sh
```

Verify that:
- The Telegram message is sent correctly.
- The response (approve/reject) is handled as expected.
- Edge cases (timeout, network error) fall back gracefully.

## Be Kind and Constructive

- Treat every contributor with respect.
- Give constructive feedback in code reviews.
- Assume good intent.
- We are all here to learn and build something useful together.
