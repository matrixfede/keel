#!/usr/bin/env bash
# lib_paths.sh — where the pack lives and where the project lives.
# Include with: source "$(dirname "$0")/lib_paths.sh"   (every pack script does)
#
# keel can run in two layouts, and every script must work in both:
#   copy-in  — the pack is copied into the project (README "Install"): pack root == project root.
#   plugin   — the pack is installed once, as a Claude Code / Codex plugin, and used from
#              many projects: pack root is the plugin folder, project root is wherever
#              PLAN.md lives.
#
# Two variables come out of this file:
#   KEEL_HOME     pack root: prompts/, scripts/, templates, docs/AGENT_SOP.md.
#                 Resolved from this file's own location; override with KEEL_HOME=.
#   KEEL_PROJECT  project root: PLAN.md, PROGRESS.md, logs/agent/, .git.
#                 Resolution order: $KEEL_PROJECT · $CLAUDE_PROJECT_DIR · nearest ancestor
#                 of $PWD holding PLAN.md or .keel/ · git top-level of $PWD · $PWD.
#
# Scripts `cd "$KEEL_PROJECT"` and reach the pack with "$KEEL_HOME/...". Relative paths
# such as `scripts/plan_graph.py` in the rules are therefore relative to KEEL_HOME.

if [[ -z "${KEEL_HOME:-}" ]]; then
  KEEL_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export KEEL_HOME

_keel_find_project() {
  local d
  if [[ -n "${KEEL_PROJECT:-}" ]]; then (cd "$KEEL_PROJECT" 2>/dev/null && pwd); return; fi
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -d "$CLAUDE_PROJECT_DIR" ]]; then (cd "$CLAUDE_PROJECT_DIR" && pwd); return; fi
  d="$PWD"
  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ -f "$d/PLAN.md" || -d "$d/.keel" ]]; then echo "$d"; return; fi
    d="$(dirname "$d")"
  done
  if d="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$d" ]]; then echo "$d"; return; fi
  echo "$PWD"
}
KEEL_PROJECT="$(_keel_find_project)"
export KEEL_PROJECT

# True when the pack is copied into the project (the classic layout).
keel_is_copy_in() { [[ "$KEEL_HOME" == "$KEEL_PROJECT" ]]; }

# Path of a pack script/file, printed the way the reader should type it:
# short in copy-in mode, absolute in plugin mode.
keel_cmd() {  # keel_cmd scripts/checker.sh  →  scripts/checker.sh | /abs/plugin/scripts/checker.sh
  if keel_is_copy_in; then echo "$1"; else echo "$KEEL_HOME/$1"; fi
}
