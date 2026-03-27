#!/usr/bin/env bash
# Remove orchestrator symlinks and imports from a target project.
#
# Usage:
#   ~/Git/orchestrator/scripts/uninstall.sh /path/to/project

set -euo pipefail

ORCH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-.}"
TARGET="$(cd "$TARGET" && pwd)"

echo "Removing orchestrator from: $TARGET"
echo ""

# --- 1. Remove command symlinks ---
for link in "$TARGET"/.claude/commands/orch-*.md; do
  [ -L "$link" ] || continue
  rm "$link"
  echo "  ✗ $(basename "$link")"
done

# --- 2. Remove script symlinks ---
for link in "$TARGET"/scripts/orch-*.sh; do
  [ -L "$link" ] || continue
  rm "$link"
  echo "  ✗ scripts/$(basename "$link")"
done

# --- 3. Remove CLAUDE.md import ---
CLAUDE_MD="$TARGET/CLAUDE.md"
IMPORT_LINE="@import ${ORCH_DIR}/CLAUDE.md"

if [ -f "$CLAUDE_MD" ] && grep -qF "$IMPORT_LINE" "$CLAUDE_MD"; then
  grep -vF "$IMPORT_LINE" "$CLAUDE_MD" > "$CLAUDE_MD.tmp"
  mv "$CLAUDE_MD.tmp" "$CLAUDE_MD"
  # Remove file if it's now empty
  if [ ! -s "$CLAUDE_MD" ]; then
    rm "$CLAUDE_MD"
    echo "  ✗ Removed empty CLAUDE.md"
  else
    echo "  ✗ Removed import from CLAUDE.md"
  fi
fi

echo ""
echo "Done."
