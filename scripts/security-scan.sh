#!/bin/bash
# Periodic security health check for oh-my-claudecode.
# Run weekly via cron or manually after configuration changes.

set -uo pipefail

ISSUES=0
WARNINGS=0

check() {
  local severity="$1" desc="$2" condition="$3"
  if eval "$condition" 2>/dev/null; then
    echo "[$severity] $desc"
    if [ "$severity" = "FAIL" ]; then ISSUES=$((ISSUES + 1)); fi
    if [ "$severity" = "WARN" ]; then WARNINGS=$((WARNINGS + 1)); fi
  else
    echo "[PASS] $desc"
  fi
}

echo "=== oh-my-claudecode Security Scan ==="
echo "Date: $(date -Iseconds)"
echo ""

check "WARN" "Active autonomous mode state files" \
  "ls .omc/state/*-state.json 2>/dev/null | grep -q ."

check "FAIL" ".omc/ not in .gitignore" \
  "! grep -q '\.omc/' .gitignore 2>/dev/null"

check "FAIL" "~/.omc/config.json has loose permissions" \
  "[ -f ~/.omc/config.json ] && [ \$(stat -c %a ~/.omc/config.json 2>/dev/null || echo 600) != '600' ]"

check "FAIL" ".omc/ files staged in git" \
  "git diff --cached --name-only 2>/dev/null | grep -q '\.omc/'"

check "WARN" "~/.claude/CLAUDE.md baseline not saved" \
  "[ -f ~/.claude/CLAUDE.md ] && [ ! -f ~/.claude/.claude-md-hash ]"

check "WARN" "Bridge bundle checksums not verified" \
  "[ ! -f bridge/checksums-verified.sha256 ]"

check "FAIL" "Pre-commit hook not installed" \
  "[ ! -x .githooks/pre-commit ] && [ ! -x .git/hooks/pre-commit ]"

check "WARN" "Learned skills contain suspicious patterns" \
  "grep -rl 'subprocess\|import os\|__import__' ~/.omc/skills/ 2>/dev/null | grep -q ."

echo ""
echo "=== Results: $ISSUES failure(s), $WARNINGS warning(s) ==="
[ $ISSUES -gt 0 ] && exit 1
exit 0
