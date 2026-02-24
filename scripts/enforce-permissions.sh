#!/bin/bash
# Enforce restrictive permissions on OMC sensitive files.
# Run periodically or after installation.

set -euo pipefail

FIXED=0

fix_perms() {
  local target="$1" perm="$2"
  if [ -e "$target" ]; then
    current=$(stat -c %a "$target" 2>/dev/null || stat -f %Lp "$target" 2>/dev/null)
    if [ "$current" != "$perm" ]; then
      chmod "$perm" "$target"
      echo "Fixed: $target ($current -> $perm)"
      FIXED=$((FIXED + 1))
    fi
  fi
}

fix_dir() {
  local dir="$1"
  if [ -d "$dir" ]; then
    fix_perms "$dir" "700"
    find "$dir" -type f \( -name '*.json' -o -name '*.md' -o -name '*.jsonl' \) -print0 | \
      while IFS= read -r -d '' f; do fix_perms "$f" "600"; done
  fi
}

# Global config
fix_perms "$HOME/.omc/config.json" "600"
fix_dir "$HOME/.omc/skills"

# Project-local state
fix_dir ".omc/state"
fix_dir ".omc/skills"
fix_dir ".omc/logs"

echo "Done. Fixed $FIXED file(s)."
