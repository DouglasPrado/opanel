#!/usr/bin/env bash
# PostToolUse(Edit|Write), async — format what was just written.
#
# Runs the formatter the repository already uses, and only when it exists. It
# never fails the tool call: formatting is a convenience, and bin/gate is what
# actually decides whether the code is acceptable.

set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$(pwd)}"
[ -f "$ROOT/.backlog-active" ] || exit 0
cd "$ROOT" 2>/dev/null || exit 0

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)"
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0

case "$FILE" in
  *.rb)
    if [ -x bin/bundle ] || command -v bundle >/dev/null 2>&1; then
      bundle exec rubocop -A --force-exclusion "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
  *.ts|*.tsx)
    if [ -f node_modules/.bin/eslint ]; then
      node_modules/.bin/eslint --fix "$FILE" >/dev/null 2>&1 || true
    fi
    ;;
esac
exit 0
