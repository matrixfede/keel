#!/usr/bin/env bash
# keel_gate.sh — PreToolUse hook: enforces the planning gate (SOP-0) at WRITE
# time, not only at commit. Works across Claude Code, OpenAI Codex, and Google
# Antigravity (auto-detecting the hook JSON contract on stdin).
#
# Wired by:
#   - hooks/hooks.json                          (Claude Code & Codex plugins)
#   - hooks.json                                (Google Antigravity plugin)
#   - adapters/claude/claude-settings.json      (Claude Code copy-in)
#
# Protocols supported:
#   1) Claude Code / Codex stdin: { "tool_name": ..., "tool_input": {...}, "cwd": ... }
#        Allow -> exit 0 (silent)
#        Block -> message on stderr, exit 2
#   2) Antigravity stdin: { "toolCall": { "name": ..., "args": { "Path": ... } }, "cwd": ..., "workspacePaths": [...] }
#        Allow -> stdout JSON {"decision":"allow"}, exit 0
#        Block -> stdout JSON {"decision":"deny","reason":"..."}, exit 0
#
# Rule: with PLAN.md missing or in DRAFT only PLAN.md may be written (plus the
# pack's log files and Antigravity's external artifactDirectoryPath). Fan-out
# workers are unaffected: there the plan is APPROVED.
#
# Scope: the gate acts only in projects that use keel — PLAN.md present, the
# `.keel/` marker written by `keel init`, or keel's AGENTS.md copied in.
# Elsewhere it stays silent, so a plugin installed once does not lock every
# other repository. KEEL_GATE=off disables it.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

# Parse protocol, tool name, cwd, artifact dir, and target file list in one Python call.
PARSED=$(printf '%s' "$INPUT" | python3 -c '
import json, re, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("claude\t\t\t\t"); sys.exit(0)

if not isinstance(d, dict):
    print("claude\t\t\t\t"); sys.exit(0)

if "toolCall" in d:
    proto = "antigravity"
    tc = d.get("toolCall") or {}
    tool = tc.get("name") or ""
    args = tc.get("args") or {}
    files = []
    for k in ("Path", "TargetFile", "file_path", "notebook_path", "path"):
        if args.get(k):
            files.append(str(args[k]))
    ws = d.get("workspacePaths") or []
    cwd = d.get("cwd") or (ws[0] if ws else "")
    art = d.get("artifactDirectoryPath") or ""
else:
    proto = "claude"
    tool = d.get("tool_name") or ""
    ti = d.get("tool_input") or {}
    files = []
    fp = ti.get("file_path") or ti.get("notebook_path") or ti.get("path")
    if fp:
        files.append(str(fp))
    for v in ti.values():
        if isinstance(v, str) and "*** Begin Patch" in v:
            files += re.findall(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$", v, re.M)
            files += re.findall(r"^\*\*\* Move to: (.+)$", v, re.M)
    cwd = d.get("cwd") or ""
    art = ""

print("\t".join([proto, str(tool), str(cwd), str(art), "\n".join(f.strip() for f in files if str(f).strip())]))
' 2>/dev/null)

PROTO="${PARSED%%$'\t'*}"; REST="${PARSED#*$'\t'}"
TOOL="${REST%%$'\t'*}";    REST="${REST#*$'\t'}"
CWD="${REST%%$'\t'*}";     REST="${REST#*$'\t'}"
ART_DIR="${REST%%$'\t'*}"; FILES="${REST#*$'\t'}"

allow_out() {
  if [[ "$PROTO" == "antigravity" ]]; then
    printf '{"decision":"allow"}\n'
  fi
  exit 0
}

deny_out() {
  local msg="$1"
  if [[ "$PROTO" == "antigravity" ]]; then
    MSG_ENV="$msg" python3 -c 'import json, os; print(json.dumps({"decision": "deny", "reason": os.environ["MSG_ENV"]}))'
    exit 0
  else
    printf '%s\n' "$msg" >&2
    exit 2
  fi
}

[[ "${KEEL_GATE:-on}" == "off" ]] && allow_out
[[ -n "$FILES" ]] || allow_out   # nothing to write, nothing to gate

# Project root: explicit, or the folder the agent runs in.
ROOT="${KEEL_PROJECT:-${CLAUDE_PROJECT_DIR:-${CWD:-$PWD}}}"
[[ -d "$ROOT" ]] || ROOT="$PWD"

# Not a keel project → out of scope. A keel project has PLAN.md, or the .keel/
# marker (`keel init`), or the pack's own AGENTS.md copied in (classic install).
keel_project() {
  [[ -f "$ROOT/PLAN.md" || -d "$ROOT/.keel" ]] && return 0
  [[ -f "$ROOT/AGENTS.md" ]] && grep -q "PLANNING GATE" "$ROOT/AGENTS.md" 2>/dev/null
}
keel_project || allow_out

# Files always allowed: the plan itself, the archive, the log, the pack's log folder,
# the marker, and Antigravity's external artifact/scratch directory.
GATED=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  case "$(basename "$f")" in PLAN.md|PLAN_ARCHIVE.md|PROGRESS.md) continue ;; esac
  case "$f" in */logs/agent/*|logs/agent/*|*/.keel/*|.keel/*) continue ;; esac
  if [[ -n "$ART_DIR" && "$f" == "$ART_DIR"/* ]]; then continue; fi
  GATED="$f"; break
done <<< "$FILES"
[[ -n "$GATED" ]] || allow_out

if [[ ! -f "$ROOT/PLAN.md" ]]; then
  deny_out "PLANNING GATE (SOP-0): PLAN.md does not exist, so $GATED is not written ($TOOL).
Create PLAN.md from PLAN.template.md, present the plan and wait for the user's \"go\".
If the request is truly simple (a specified one-line change), the user can say \"skip the plan\"."
fi

if grep -qi "Plan status:.*DRAFT" "$ROOT/PLAN.md"; then
  deny_out "PLANNING GATE (SOP-0): PLAN.md is in DRAFT, so $GATED is not written ($TOOL).
The plan awaits the user's approval: end the turn with the waiting line and stop.
After the \"go\", update the header to \"Plan status: APPROVED (<date>)\" and retry."
fi

allow_out
