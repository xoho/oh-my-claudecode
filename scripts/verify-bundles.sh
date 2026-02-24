#!/bin/bash
# Verify that committed bridge bundles match a clean source rebuild.
# Exit 0 if match, exit 1 if divergence detected.

set -euo pipefail

echo "=== Bundle Verification ==="
echo "Date: $(date -Iseconds)"

# Save committed checksums
echo "Saving committed bundle checksums..."
sha256sum bridge/*.cjs | sort > /tmp/omc-committed.sha256
cat /tmp/omc-committed.sha256

# Clean rebuild
echo "Rebuilding from source..."
npm ci --ignore-scripts
npm run build

# Compare
echo "Comparing checksums..."
sha256sum bridge/*.cjs | sort > /tmp/omc-rebuilt.sha256

if diff /tmp/omc-committed.sha256 /tmp/omc-rebuilt.sha256 > /dev/null 2>&1; then
  echo "PASS: All bundles match source rebuild."
  cp /tmp/omc-rebuilt.sha256 bridge/checksums-verified.sha256
  exit 0
else
  echo "FAIL: Bundle mismatch detected!"
  echo ""
  echo "Committed:"
  cat /tmp/omc-committed.sha256
  echo ""
  echo "Rebuilt:"
  cat /tmp/omc-rebuilt.sha256
  echo ""
  diff /tmp/omc-committed.sha256 /tmp/omc-rebuilt.sha256 || true
  exit 1
fi
