#!/usr/bin/env bash
# premortem.sh — fresh-context pre-mortem of the plan (SOP-9).
#
# The checker (SOP-8) attacks artifacts; this attacks the PLAN, before the
# "go". It opens a NEW session that sees ONLY PLAN.md — not the conversation
# the plan was born in, otherwise it just nods — and asks it to narrate how the
# plan failed 12 months out (prompts/arguer.md). The outcome goes under
# "Decisions" with the prefix PRE-MORTEM:, next to the ASSUMED: lines, and the
# user reads it together with the table.
#
# Usage:
#   scripts/premortem.sh              # runs with the available agent CLI, saves logs/agent/premortem_<date>.md
#   scripts/premortem.sh --prompt     # writes only the prompt for a manual session
#
# Result: last line "PREMORTEM: DONE" (exit 0), "PREMORTEM: PROMPT" (prompt written, exit 0),
#         "PREMORTEM: ERROR" (exit 2).

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=lib_agent.sh
source "scripts/lib_agent.sh"

LOGDIR="logs/agent"; mkdir -p "$LOGDIR"
[[ -f PLAN.md ]] || { echo "PLAN.md missing: the pre-mortem runs on the plan, create it first."; echo "PREMORTEM: ERROR"; exit 2; }

STAMP=$(date +%Y%m%d_%H%M%S)
PROMPT="$LOGDIR/premortem_${STAMP}.prompt.md"
OUT="$LOGDIR/premortem_${STAMP}.md"

{
  cat prompts/arguer.md
  echo; echo "---"; echo
  echo "# The plan to attack (PLAN.md, as it is now)"; echo
  cat PLAN.md
} > "$PROMPT"

if [[ "${1:-}" == "--prompt" ]] || ! agent_available; then
  echo "  prompt written to $PROMPT"
  agent_available || agent_missing_hint "$PROMPT"
  echo "  paste the answer into $OUT and report the top three failure modes in PLAN.md as PRE-MORTEM: lines"
  echo "PREMORTEM: PROMPT"
  exit 0
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/premortem.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cp PLAN.md "$TMP/PLAN.md"

echo "  pre-mortem running with $(agent_name) (new session, read-only, sees only PLAN.md)"
if ! agent_run "$TMP" readonly "$PROMPT" "$OUT"; then
  echo "  the agent ($(agent_name)) exited with an error — see ${OUT}.events.log"
  echo "PREMORTEM: ERROR"; exit 2
fi

echo "─ Outcome ($OUT)"
sed 's/^/  /' "$OUT"
echo
echo "  Next step: report in PLAN.md → Decisions the top three failure modes,"
echo "  one per line, with the prefix PRE-MORTEM: and the chosen countermeasure (or 'accepted: <why>')."
echo "PREMORTEM: DONE"
