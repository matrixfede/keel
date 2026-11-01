#!/usr/bin/env bash
# session_start.sh — SessionStart hook (Claude Code and Codex plugins).
#
# A plugin cannot ship a CLAUDE.md / AGENTS.md that every session reads, so the
# rules are injected here: whatever this script prints becomes context for the
# session. It prints the full AGENTS.md only in projects that use keel
# (PLAN.md, `.keel/` marker or the pack's AGENTS.md copied in); elsewhere, one
# line saying how to enable it. If the project already has keel's AGENTS.md
# (classic copy-in install), the agent reads it natively and only the header
# with the pack location is printed.

set -uo pipefail
INPUT=$(cat 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("cwd") or "")
except Exception: print("")' 2>/dev/null)
ROOT="${KEEL_PROJECT:-${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}}"
[[ -d "$ROOT" ]] || ROOT="$PWD"
HOME_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

native=0; enabled=0
[[ -f "$ROOT/AGENTS.md" ]] && grep -q "PLANNING GATE" "$ROOT/AGENTS.md" 2>/dev/null && native=1
[[ -f "$ROOT/PLAN.md" || -d "$ROOT/.keel" || $native -eq 1 ]] && enabled=1

if [[ $enabled -eq 0 ]]; then
  cat <<MSG
[keel] The keel plugin is installed but this project is not set up for it (no PLAN.md, no .keel/).
Nothing is enforced here. To enable the plan gate in this project run: bash "$HOME_DIR/bin/keel" init
(or the /keel:init skill). Full rules: $HOME_DIR/AGENTS.md
MSG
  exit 0
fi

cat <<MSG
[keel] plugin active — keel home: $HOME_DIR — project: $ROOT
Pack commands (run from the project root):
  bash "$HOME_DIR/bin/keel" verify [all|static|unit]   → VERIFY: PASS|FAIL
  bash "$HOME_DIR/bin/keel" graph                      → GRAPH: OK|FAIL      (python3 plan_graph.py)
  bash "$HOME_DIR/bin/keel" check <n> <artifact>       → CHECKER: KEEP|DROP  (critical tasks)
  bash "$HOME_DIR/bin/keel" premortem                  → PREMORTEM: DONE
  bash "$HOME_DIR/bin/keel" fanout P1                  → FANOUT: PASS|FAIL
  bash "$HOME_DIR/bin/keel" health                     → state snapshot (SOP-2)
Templates: $HOME_DIR/PLAN.template.md · $HOME_DIR/PROGRESS.template.md
SOP:       $HOME_DIR/docs/AGENT_SOP.md
In the rules, a path like \`scripts/x\` or \`docs/AGENT_SOP.md\` means "$HOME_DIR/<that path>"; PLAN.md,
PROGRESS.md and logs/agent/ are in the project. The write-time gate (PreToolUse) is active.
MSG

if [[ $native -eq 1 ]]; then
  echo "The project has keel's AGENTS.md: the rules are already in context, they are not repeated here."
  exit 0
fi

echo
cat "$HOME_DIR/AGENTS.md"
