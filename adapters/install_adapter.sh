#!/usr/bin/env bash
# install_adapter.sh — copies the "bridge" files for a specific agent into the project.
# Usage: bash adapters/install_adapter.sh claude|gemini|aider|all
# Never overwrites existing files: if one is found, it tells you what to paste by hand.

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
HERE="adapters"

put() {  # put <source relative to adapters/> <destination relative to the root>
  local src="$HERE/$1" dst="$2"
  if [[ -e "$dst" ]]; then
    echo "  already exists: $dst — not overwritten. Merge the content of $src by hand"
  else
    mkdir -p "$(dirname "$dst")"; cp "$src" "$dst"; echo "  created: $dst"
  fi
}

do_claude() {
  echo "Claude Code:"
  put claude/CLAUDE.md CLAUDE.md
  put claude/claude-settings.json .claude/settings.json
  chmod +x scripts/hooks/claude_gate.sh 2>/dev/null || true
  echo "  (the PreToolUse hook enforces the gate at write time: scripts/hooks/claude_gate.sh)"
}
do_gemini() {
  echo "Gemini CLI:"
  put gemini/.gemini/settings.json .gemini/settings.json
  echo "  (alternatively: create GEMINI.md with a single line '@./AGENTS.md')"
}
do_aider() {
  echo "Aider:"
  put aider/.aider.conf.yml .aider.conf.yml
}

case "${1:-}" in
  claude) do_claude ;;
  gemini) do_gemini ;;
  aider)  do_aider ;;
  all)    do_claude; do_gemini; do_aider ;;
  *) echo "Usage: bash adapters/install_adapter.sh claude|gemini|aider|all"; exit 2 ;;
esac
echo "Codex, Cursor, Copilot, OpenCode and Pi read AGENTS.md on their own: no adapter needed."
