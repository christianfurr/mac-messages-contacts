#!/bin/bash
# Install this skill into ~/.claude/skills.
# Default: symlink (repo stays canonical). --copy: copy files instead.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="$HOME/.claude/skills/mac-messages-contacts"

mkdir -p "$HOME/.claude/skills"
rm -rf "$TARGET"

if [ "${1:-}" = "--copy" ]; then
  mkdir -p "$TARGET"
  cp "$REPO_DIR/SKILL.md" "$TARGET/"
  cp -R "$REPO_DIR/scripts" "$TARGET/"
  echo "Copied skill to $TARGET"
else
  ln -s "$REPO_DIR" "$TARGET"
  echo "Symlinked $TARGET -> $REPO_DIR"
fi

echo "Restart Claude Code to pick up the skill."
