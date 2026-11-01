#!/usr/bin/env bash
# keel_gate.sh — PreToolUse hook: enforces the planning gate (SOP-0) at WRITE
# time, not only at commit. Works for Claude Code and for Codex (both pass the
# same JSON shape on stdin and both honour exit code 2 = block).
#
# Wired by hooks/hooks.json (plugin) or adapters/claude/claude-settings.json (copy-in).
#
# stdin JSON: { "tool_name": ..., "tool_input": {...}, "cwd": ... }
#   Write / Edit / MultiEdit / NotebookEdit  → tool_input.file_path | notebook_path
#   apply_patch (Codex)                      → file names parsed from the patch text
# Exit 0 = allow. Exit 2 = block, the message on stderr is shown to the agent.
#
# Rule: with PLAN.md missing or in DRAFT only PLAN.md may be written (plus the
# pack's log files). Fan-out workers are unaffected: there the plan is APPROVED.
#
# Scope: the gate acts only in projects that use keel — PLAN.md present, or the
# `.keel/` marker written by `keel init`. Elsewhere it stays silent, so a plugin
# installed once does not lock every other repository. KEEL_GATE=off disables it.

set -uo pipefail
[[ "${KEEL_GATE:-on}" == "off" ]] && exit 0

INPUT=$(cat)
# One python call: tool name, cwd, and the list of files the call would write.
PARSED=$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("\t\t"); sys.exit(0)
ti = d.get("tool_input") or {}
files = []
fp = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
if fp:
    files.append(str(fp))
# Codex apply_patch: the patch text is the only place the paths appear.
for v in ti.values():
    if isinstance(v, str) and "*** Begin Patch" in v:
        files += re.findall(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", v, re.M)
        files += re.findall(r"^\*\*\* Move to: (.+)$", v, re.M)
print("\t".join([str(d.get("tool_name", "")), str(d.get("cwd", "")), "\n".join(f.strip() for f in files)]))
' 2>/dev/null)
TOOL="${PARSED%%$'\t'*}"; REST="${PARSED#*$'\t'}"
CWD="${REST%%$'\t'*}"; FILES="${REST#*$'\t'}"
[[ -n "$FILES" ]] || exit 0   # nothing to write, nothing to gate

# Project root: explicit, or the folder the agent runs in.
ROOT="${KEEL_PROJECT:-${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}}"
[[ -d "$ROOT" ]] || ROOT="$PWD"

# Not a keel project → out of scope. A keel project has PLAN.md, or the .keel/
# marker (`keel init`), or the pack's own AGENTS.md copied in (classic install).
keel_project() {
  [[ -f "$ROOT/PLAN.md" || -d "$ROOT/.keel" ]] && return 0
  [[ -f "$ROOT/AGENTS.md" ]] && grep -q "PLANNING GATE" "$ROOT/AGENTS.md" 2>/dev/null
}
keel_project || exit 0

# Files always allowed: the plan itself, the archive, the log, the pack's log folder, the marker.
GATED=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  case "$(basename "$f")" in PLAN.md|PLAN_ARCHIVE.md|PROGRESS.md) continue ;; esac
  case "$f" in */logs/agent/*|logs/agent/*|*/.keel/*|.keel/*) continue ;; esac
  GATED="$f"; break
done <<< "$FILES"
[[ -n "$GATED" ]] || exit 0

if [[ ! -f "$ROOT/PLAN.md" ]]; then
  cat >&2 <<MSG
PLANNING GATE (SOP-0): PLAN.md does not exist, so $GATED is not written ($TOOL).
Create PLAN.md from PLAN.template.md, present the plan and wait for the user's "go".
If the request is truly simple (a specified one-line change), the user can say "skip the plan".
MSG
  exit 2
fi

if grep -qi "Plan status:.*DRAFT" "$ROOT/PLAN.md"; then
  cat >&2 <<MSG
PLANNING GATE (SOP-0): PLAN.md is in DRAFT, so $GATED is not written ($TOOL).
The plan awaits the user's approval: end the turn with the waiting line and stop.
After the "go", update the header to "Plan status: APPROVED (<date>)" and retry.
MSG
  exit 2
fi

exit 0
