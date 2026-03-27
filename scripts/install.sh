#!/usr/bin/env bash
# Install orchestrator into a target project.
# Symlinks slash commands and imports CLAUDE.md cluster context.
#
# Usage:
#   ~/Git/orchestrator/scripts/install.sh /path/to/project
#   cd my-project && ~/Git/orchestrator/scripts/install.sh .

set -euo pipefail

ORCH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-.}"
TARGET="$(cd "$TARGET" && pwd)"

if [ "$ORCH_DIR" = "$TARGET" ]; then
  echo "Error: target directory is the orchestrator repo itself."
  exit 1
fi

echo "Orchestrator: $ORCH_DIR"
echo "Target:       $TARGET"
echo ""

# --- 1. Symlink slash commands ---
mkdir -p "$TARGET/.claude/commands"

for cmd in "$ORCH_DIR"/commands/*.md; do
  [ -f "$cmd" ] || continue
  name="$(basename "$cmd")"
  link="$TARGET/.claude/commands/orch-${name}"

  if [ -L "$link" ]; then
    echo "  ↻ orch-${name} (already linked)"
  else
    ln -s "$cmd" "$link"
    echo "  ✓ orch-${name}"
  fi
done

# --- 2. Symlink scripts ---
mkdir -p "$TARGET/scripts"

for script in "$ORCH_DIR"/scripts/*.sh; do
  [ -f "$script" ] || continue
  name="$(basename "$script")"
  # Don't symlink install.sh into the target
  [ "$name" = "install.sh" ] && continue
  link="$TARGET/scripts/orch-${name}"

  if [ -L "$link" ]; then
    echo "  ↻ orch-${name} (already linked)"
  else
    ln -s "$script" "$link"
    echo "  ✓ scripts/orch-${name}"
  fi
done

# --- 3. Import CLAUDE.md context ---
CLAUDE_MD="$TARGET/CLAUDE.md"
IMPORT_LINE="@import ${ORCH_DIR}/CLAUDE.md"

if [ -f "$CLAUDE_MD" ] && grep -qF "$IMPORT_LINE" "$CLAUDE_MD"; then
  echo "  ↻ CLAUDE.md already imports orchestrator context"
else
  # Append import to existing CLAUDE.md or create one
  if [ -f "$CLAUDE_MD" ]; then
    echo "" >> "$CLAUDE_MD"
    echo "$IMPORT_LINE" >> "$CLAUDE_MD"
    echo "  ✓ Appended import to existing CLAUDE.md"
  else
    echo "$IMPORT_LINE" > "$CLAUDE_MD"
    echo "  ✓ Created CLAUDE.md with orchestrator import"
  fi
fi

echo ""
echo "Done. Orchestrator commands available as /orch-gpu-status etc."
