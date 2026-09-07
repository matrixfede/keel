#!/usr/bin/env bash
# checker.sh — fresh-context checker for `critical` tasks (SOP-8).
#
# Whoever produces an output is not a good judge of that same output. This
# script opens a NEW session that sees ONLY the artifact (copied to an empty
# temporary folder: no repo, no PLAN.md, no conversation), gives it the hostile
# prompt of prompts/checker.md and records the verdict in a file the pre-commit
# hook checks — with the artifact's hash, so the KEEP expires if the file is
# modified after the review.
#
# Usage:
#   scripts/checker.sh <task#> <artifact> [other_artifact ...]
#       runs the checker with the available agent CLI (see lib_agent.sh) and writes logs/agent/checker_task<N>.txt
#   scripts/checker.sh --prompt <task#> <artifact> [...]
#       writes only the prompt (logs/agent/checker_task<N>.prompt.md) for a manual session
#   scripts/checker.sh --record <task#> KEEP|DROP "<rationale>" <artifact> [...]
#       records a verdict obtained by hand (same file, same hash: the hook sees no difference)
#
# For a diff: first `git diff > logs/agent/task<N>.diff`, then pass that file.
# Result: last line "CHECKER: KEEP" or "CHECKER: DROP" (exit 1) — "CHECKER: ERROR" (exit 2).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=lib_agent.sh
source "scripts/lib_agent.sh"

LOGDIR="logs/agent"; mkdir -p "$LOGDIR"
PROMPT_TPL="prompts/checker.md"
SCHEMA="prompts/checker.schema.json"

usage() { sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

write_verdict() {   # write_verdict <task> <mode> <checks> <verdict> <rationale> <art...>
  local task="$1" mode="$2" checks="$3" verdict="$4" rationale="$5"; shift 5
  local f="$LOGDIR/checker_task${task}.txt"
  {
    echo "TASK: $task"
    echo "DATE: $(now_iso)"
    echo "MODE: $mode"
    for a in "$@"; do
      echo "ARTIFACT: $a"
      echo "SHA256: $(sha256_of "$a")"
    done
    echo "CHECKS: $checks"
    echo "VERDICT: $verdict"
    echo "RATIONALE: $rationale"
  } > "$f"
  echo "  verdict recorded in $f"
  if [[ "$verdict" == "KEEP" ]]; then
    echo "  note in task $task Notes: KEEP (checker $(date +%F))"
    echo "CHECKER: KEEP"; return 0
  else
    echo "  task $task goes back to 🔄 — rationale to report in Notes: $rationale"
    echo "CHECKER: DROP"; return 1
  fi
}

build_prompt() {    # build_prompt <prompt_file> <art...>
  local out="$1"; shift
  { cat "$PROMPT_TPL"; echo; echo "---"; echo; echo "# Artifacts to examine"; echo
    for a in "$@"; do
      echo "=== ARTIFACT: $(basename "$a") ==="
      if grep -Iq . "$a" 2>/dev/null && [[ $(wc -c < "$a") -lt 120000 ]]; then
        cat "$a"
      else
        echo "(non-text or too large to inline: read it from the current folder, it is called $(basename "$a"))"
      fi
      echo; echo "=== END $(basename "$a") ==="; echo
    done
  } > "$out"
}

check_args() {      # every artifact must exist
  for a in "$@"; do
    [[ -f "$a" ]] || { echo "artifact not found: $a"; echo "CHECKER: ERROR"; exit 2; }
  done
}

MODE_RUN=run
if [[ "${1:-}" == "--prompt" ]]; then MODE_RUN=prompt; shift
elif [[ "${1:-}" == "--record" ]]; then MODE_RUN=record; shift
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 2 ]]; then usage
fi

TASK="${1:-}"; shift || usage
[[ "$TASK" =~ ^[0-9]+$ ]] || { echo "task# must be a number, got: $TASK"; usage; }

if [[ "$MODE_RUN" == "record" ]]; then
  VERDICT="${1:-}"; RATIONALE="${2:-}"; shift 2 || usage
  [[ "$VERDICT" == "KEEP" || "$VERDICT" == "DROP" ]] || { echo "verdict must be KEEP or DROP"; usage; }
  [[ $# -ge 1 ]] || usage
  check_args "$@"
  write_verdict "$TASK" manual "recorded by hand" "$VERDICT" "$RATIONALE" "$@"
  exit $?
fi

[[ $# -ge 1 ]] || usage
check_args "$@"
PROMPT="$LOGDIR/checker_task${TASK}.prompt.md"
build_prompt "$PROMPT" "$@"

if [[ "$MODE_RUN" == "prompt" ]] || ! agent_available; then
  echo "  prompt written to $PROMPT"
  agent_available || agent_missing_hint "$PROMPT"
  echo "  then: scripts/checker.sh --record $TASK KEEP|DROP \"<rationale>\" $*"
  echo "CHECKER: PROMPT"
  exit 0
fi

# Fresh context: temporary folder with only a copy of the artifacts.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/checker.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
for a in "$@"; do cp "$a" "$TMP/"; done
OUT="$LOGDIR/checker_task${TASK}.raw.txt"

echo "  checker running with $(agent_name) (new session, read-only, sees only: $*)"
if ! agent_run "$TMP" readonly "$PROMPT" "$OUT" "$SCHEMA"; then
  echo "  the agent ($(agent_name)) exited with an error — see ${OUT}.events.log"
  echo "CHECKER: ERROR"; exit 2
fi

# The final verdict is computed by the script, not the model:
# KEEP only if the model says KEEP AND at least two checks out of three are PASS.
# Tolerant reading: pure JSON (codex with schema), JSON inside a ```json block or
# amid text (claude, gemini, opencode, copilot), or the line format
# "CHECK-1 ...: PASS|FAIL / VERDICT: KEEP|DROP / RATIONALE: ..." as a last resort.
PARSED=$(python3 - "$OUT" <<'PY'
import json, re, sys
raw = open(sys.argv[1], encoding="utf-8", errors="replace").read()

def from_json(txt):
    d = json.loads(txt)
    checks = {k: str(d[f"check_{k}"]["result"]).upper() for k in ("accurate", "current", "references")}
    return checks, str(d["verdict"]).upper(), str(d["rationale"])

def parse(raw):
    try:
        return from_json(raw)
    except Exception:
        pass
    m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.S)
    if m:
        try: return from_json(m.group(1))
        except Exception: pass
    start, end = raw.find("{"), raw.rfind("}")
    if start != -1 and end > start:
        try: return from_json(raw[start:end + 1])
        except Exception: pass
    checks = {}
    for k, pat in (("accurate", r"CHECK-1[^\n]*?:\s*(PASS|FAIL)"), ("current", r"CHECK-2[^\n]*?:\s*(PASS|FAIL)"),
                   ("references", r"CHECK-3[^\n]*?:\s*(PASS|FAIL)")):
        m = re.search(pat, raw, re.I)
        if not m: raise ValueError("unrecognized format (neither JSON nor CHECK-n/VERDICT lines)")
        checks[k] = m.group(1).upper()
    v = re.search(r"VERDICT:\s*(KEEP|DROP)", raw, re.I)
    if not v: raise ValueError("VERDICT missing")
    mo = re.search(r"RATIONALE:\s*(.+)", raw, re.S)
    return checks, v.group(1).upper(), (mo.group(1) if mo else "").strip()

try:
    checks, verdict_model, rationale = parse(raw)
except Exception as e:
    print(f"ERROR\t-\t{type(e).__name__}: {e}"); sys.exit(0)
passes = sum(1 for v in checks.values() if v == "PASS")
verdict = "KEEP" if (verdict_model == "KEEP" and passes >= 2) else "DROP"
rationale = str(rationale).replace("\n", " ").strip()
if verdict_model == "KEEP" and passes < 2:
    rationale = f"[model verdict KEEP downgraded: only {passes}/3 checks passed] " + rationale
notes = " ".join(f"{k}={v}" for k, v in checks.items())
print(f"{verdict}\t{notes}\t{rationale}")
PY
)
IFS=$'\t' read -r VERDICT CHECKS RATIONALE <<< "$PARSED"
if [[ "$VERDICT" == "ERROR" ]]; then
  echo "  checker response unreadable ($RATIONALE) — see $OUT"
  echo "CHECKER: ERROR"; exit 2
fi
echo "  $CHECKS"
write_verdict "$TASK" "$(agent_name)" "$CHECKS" "$VERDICT" "$RATIONALE" "$@"
