#!/usr/bin/env bash
# claude_gate.sh — PreToolUse hook for Claude Code: enforces the planning gate
# at WRITE time, not only at commit (adapters/claude/claude-settings.json).
#
# Claude Code passes on stdin a JSON with tool_name and tool_input.file_path.
# Exit 0 = allow. Exit 2 = block and show Claude the message on stderr.
#
# Rule (SOP-0): with PLAN.md missing or in DRAFT only PLAN.md may be written
# (plus the pack's log files). Fan-out workers are unaffected: there the plan is
# APPROVED by definition.

set -uo pipefail
INPUT=$(cat)
FILE=$(printf '%s' "$INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path") or d.get("tool_input",{}).get("notebook_path") or "")
except Exception: print("")' 2>/dev/null)

# Always allowed: the plan itself, the archive, the log, the pack's log folder.
case "$(basename "${FILE:-}")" in
  PLAN.md|PLAN_ARCHIVE.md|PROGRESS.md|"") exit 0 ;;
esac
case "$FILE" in
  */logs/agent/*|logs/agent/*) exit 0 ;;
esac

# Project root: where PLAN.md lives relative to the cwd (Claude runs hooks from the root).
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

if [[ ! -f "$ROOT/PLAN.md" ]]; then
  cat >&2 <<MSG
PLANNING GATE (SOP-0): PLAN.md does not exist, so $FILE is not written.
Create PLAN.md from PLAN.template.md, present the plan and wait for the user's "go".
If the request is truly simple (a specified one-line change), the user can say "skip the plan".
MSG
  exit 2
fi

if grep -qi "Plan status:.*DRAFT" "$ROOT/PLAN.md"; then
  cat >&2 <<MSG
PLANNING GATE (SOP-0): PLAN.md is in DRAFT, so $FILE is not written.
The plan awaits the user's approval: end the turn with the waiting line and stop.
After the "go", update the header to "Plan status: APPROVED (<date>)" and retry.
MSG
  exit 2
fi

exit 0
