#!/bin/bash
# Generate or verify integrity manifest for learned skill files.
# Usage:
#   scripts/skill-integrity.sh [skills-dir] generate  # Create manifest
#   scripts/skill-integrity.sh [skills-dir] verify     # Check against manifest

set -euo pipefail

SKILLS_DIR="${1:-$HOME/.omc/skills/omc-learned}"
MANIFEST="$SKILLS_DIR/.manifest.json"
ACTION="${2:-verify}"

generate() {
  if [ ! -d "$SKILLS_DIR" ]; then
    echo "Skills directory not found: $SKILLS_DIR"
    exit 1
  fi

  echo "{" > "$MANIFEST"
  first=true
  for f in "$SKILLS_DIR"/*.md; do
    [ -f "$f" ] || continue
    hash=$(sha256sum "$f" | cut -d' ' -f1)
    name=$(basename "$f")
    if [ "$first" = true ]; then first=false; else echo "," >> "$MANIFEST"; fi
    printf '  "%s": "%s"' "$name" "$hash" >> "$MANIFEST"
  done
  echo "" >> "$MANIFEST"
  echo "}" >> "$MANIFEST"
  chmod 600 "$MANIFEST"
  echo "Manifest generated: $MANIFEST"
}

verify() {
  if [ ! -f "$MANIFEST" ]; then
    echo "No manifest found at $MANIFEST"
    echo "Run: $0 $SKILLS_DIR generate"
    exit 1
  fi

  violations=0
  for f in "$SKILLS_DIR"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    expected=$(python3 -c "import json,sys; m=json.load(open('$MANIFEST')); print(m.get('$name','MISSING'))" 2>/dev/null || echo "PARSE_ERROR")
    actual=$(sha256sum "$f" | cut -d' ' -f1)

    if [ "$expected" = "MISSING" ]; then
      echo "NEW (untracked): $name"
      violations=$((violations + 1))
    elif [ "$expected" = "PARSE_ERROR" ]; then
      echo "ERROR: Cannot parse manifest"
      exit 1
    elif [ "$expected" != "$actual" ]; then
      echo "MODIFIED: $name"
      violations=$((violations + 1))
    fi
  done

  if [ $violations -gt 0 ]; then
    echo "ALERT: $violations skill file(s) have integrity violations!"
    exit 1
  else
    echo "All skill files match manifest."
  fi
}

case "$ACTION" in
  generate) generate ;;
  verify) verify ;;
  *) echo "Usage: $0 [skills-dir] [generate|verify]" ;;
esac
