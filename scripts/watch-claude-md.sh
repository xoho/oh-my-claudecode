#!/bin/bash
# Detect unexpected modifications to ~/.claude/CLAUDE.md.
# Usage:
#   scripts/watch-claude-md.sh save    # Save current hash as baseline
#   scripts/watch-claude-md.sh check   # Check against saved baseline

set -euo pipefail

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
HASH_FILE="$HOME/.claude/.claude-md-hash"

save_hash() {
  if [ ! -f "$CLAUDE_MD" ]; then
    echo "No ~/.claude/CLAUDE.md found."
    exit 1
  fi
  sha256sum "$CLAUDE_MD" | cut -d' ' -f1 > "$HASH_FILE"
  chmod 600 "$HASH_FILE"
  echo "Saved hash: $(cat "$HASH_FILE")"
}

check_hash() {
  if [ ! -f "$HASH_FILE" ]; then
    echo "No baseline hash found. Run: $0 save"
    exit 1
  fi
  if [ ! -f "$CLAUDE_MD" ]; then
    echo "WARNING: ~/.claude/CLAUDE.md has been deleted!"
    exit 1
  fi
  EXPECTED=$(cat "$HASH_FILE")
  CURRENT=$(sha256sum "$CLAUDE_MD" | cut -d' ' -f1)
  if [ "$EXPECTED" != "$CURRENT" ]; then
    echo "WARNING: ~/.claude/CLAUDE.md has been modified!"
    echo "Expected: $EXPECTED"
    echo "Current:  $CURRENT"
    exit 1
  fi
  echo "OK: ~/.claude/CLAUDE.md matches baseline."
}

case "${1:-check}" in
  save) save_hash ;;
  check) check_hash ;;
  *) echo "Usage: $0 [save|check]" ;;
esac
