#!/usr/bin/env bash
# fanout.sh — parallel execution of a [Pn] group of the plan (SOP-8, the "diamond").
#
# One agent session per task, all at once, each on its own output file declared
# in the "Contracts" section of PLAN.md. No session touches PLAN.md or
# PROGRESS.md: statuses are updated by the main session after convergence.
# At the end a model-free REDUCTION step (zero tokens) checks that every output
# exists, is non-empty and passes its `check:` — only then may the convergence
# task start.
#
# Usage:
#   scripts/fanout.sh P1            # runs group P1
#   scripts/fanout.sh P1 --prompt   # writes only the prompts (one manual session per task)
#   scripts/fanout.sh P1 --reduce   # reduction only, after sessions launched by hand
#
# Requirements: PLAN.md in APPROVED status, valid graph (plan_graph.py), python3.
# Ceiling: FANOUT_MAX tasks per group (default 4) — beyond that it refuses: fan-out
# multiplies tokens by the number of sessions.
# Result: last line "FANOUT: PASS" or "FANOUT: FAIL" (exit 1) — "FANOUT: PROMPT" / "FANOUT: ERROR".

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=lib_agent.sh
source "scripts/lib_agent.sh"

GROUP="${1:-}"; MODE="${2:-run}"
FANOUT_MAX="${FANOUT_MAX:-4}"
LOGDIR="logs/agent"; mkdir -p "$LOGDIR"
pg() { python3 scripts/plan_graph.py "$@"; }   # a function, not a string: bash 3.2 + temporary IFS would not split a string

die() { echo "  $1"; echo "FANOUT: ERROR"; exit 2; }

[[ "$GROUP" =~ ^P[0-9]+$ ]] || die "name the group, e.g.: scripts/fanout.sh P1"
command -v python3 >/dev/null || die "python3 not found (needed to read PLAN.md)"
[[ -f PLAN.md ]] || die "PLAN.md missing"
grep -qi "Plan status:.*APPROVED" PLAN.md || die "the plan is not APPROVED: fan-out runs approved plans only"
pg --quiet >/dev/null || die "the plan graph has errors: fix PLAN.md (python3 scripts/plan_graph.py)"

# shellcheck disable=SC2207  # bash 3.2 (macOS) has no mapfile; output is one integer per line
TASKS=( $(pg --group "$GROUP") )
[[ ${#TASKS[@]} -gt 0 ]] || die "no task in group [$GROUP]"
if [[ ${#TASKS[@]} -gt "$FANOUT_MAX" ]]; then
  die "group [$GROUP] has ${#TASKS[@]} tasks, the ceiling is $FANOUT_MAX (FANOUT_MAX=<n> to raise it — with judgment)"
fi

section() {  # section "<h2 title>" → content of that PLAN.md section
  awk -v h="## $1" '$0==h{f=1;next} /^## /{f=0} f' PLAN.md
}

for N in "${TASKS[@]}"; do
  P="$LOGDIR/fanout_${GROUP}_task${N}.prompt.md"
  {
    cat <<EOF
FANOUT WORKER — task $N of group [$GROUP]

You are a parallel worker session launched by the main session.
The plan is already APPROVED: the planning gate is satisfied, do NOT re-plan and
do NOT stop to ask for approval. The style and method rules of AGENTS.md
(sections 5 and 6) still apply.

Worker rules — binding:
- Execute ONLY the task below. Nothing else, even if you notice things to fix:
  report them in your final message.
- Do NOT modify PLAN.md or PROGRESS.md: the main session updates them.
- Write the result EXACTLY to the declared OUT file and respect its SHAPE.
  If there is a CHECK, run it yourself before finishing: it must pass.
- Run the task's required verification and report the result.
- Do not touch other tasks' output files.
- End your final message with ONE line, the last one:
      TASK $N: DONE
  or, if you cannot complete:
      TASK $N: BLOCKED — <one-line reason>

## Plan objective
$(section "Objective")

## Active requirements
$(section "Active requirements")

## Your task
$(pg --task "$N")
EOF
  } > "$P"
done

if [[ "$MODE" == "--prompt" ]] || { [[ "$MODE" == "run" ]] && ! agent_available; }; then
  echo "  prompts written:"; for N in "${TASKS[@]}"; do echo "    $LOGDIR/fanout_${GROUP}_task${N}.prompt.md"; done
  agent_available || echo "  No agent CLI found (AGENT_BACKEND=${AGENT_BACKEND:-auto})."
  echo "  Open a NEW session for every prompt (one per task, all together); when they are done,"
  echo "  run the reduction alone with: scripts/fanout.sh $GROUP --reduce"
  echo "FANOUT: PROMPT"; exit 0
fi

PLAN_BEFORE=$(sha256_of PLAN.md)
PROG_BEFORE=$([[ -f PROGRESS.md ]] && sha256_of PROGRESS.md || echo none)

if [[ "$MODE" == "run" ]]; then
  echo "  fan-out [$GROUP]: ${#TASKS[@]} $(agent_name) sessions in parallel (tasks ${TASKS[*]})"
  PIDS=()   # indexed array in the same order as TASKS (no associative arrays: bash 3.2)
  for N in "${TASKS[@]}"; do
    agent_run "$PWD" write "$LOGDIR/fanout_${GROUP}_task${N}.prompt.md" "$LOGDIR/fanout_${GROUP}_task${N}.md" &
    PIDS+=($!)
  done
  i=0
  for N in "${TASKS[@]}"; do
    if wait "${PIDS[$i]}"; then echo "    task $N: session finished"; else echo "    task $N: agent exited with an error (see $LOGDIR/fanout_${GROUP}_task${N}.md.events.log)"; fi
    i=$((i+1))
  done
fi

# ───────────────────────── REDUCTION (model-free) ─────────────────────────
echo "─ Reduction [$GROUP]"
FAIL=0
for N in "${TASKS[@]}"; do
  IFS=$'\t' read -r OUT _SHAPE CHECK < <(pg --contract "$N")   # shape is for humans; the check is what we can run
  MSG="$LOGDIR/fanout_${GROUP}_task${N}.md"
  status="ok"
  if [[ ! -s "$OUT" ]]; then status="OUT missing or empty ($OUT)"
  elif [[ -n "$CHECK" ]] && ! bash -c "$CHECK" >/dev/null 2>&1; then status="check failed: $CHECK"
  elif [[ -f "$MSG" ]] && ! tail -5 "$MSG" | grep -q "TASK $N: DONE"; then status="the worker did not declare DONE: $(tail -1 "$MSG" | cut -c1-80)"
  fi
  [[ "$status" == "ok" ]] || FAIL=1
  printf '  task %-3s %-40s %s\n' "$N" "$OUT" "$status"
done
if [[ "$MODE" == "run" ]]; then
  if [[ "$(sha256_of PLAN.md)" != "$PLAN_BEFORE" ]]; then echo "  ✗ PLAN.md was modified by a worker: check with git diff PLAN.md"; FAIL=1; fi
  if [[ "$PROG_BEFORE" != "none" && "$(sha256_of PROGRESS.md)" != "$PROG_BEFORE" ]]; then echo "  ✗ PROGRESS.md was modified by a worker"; FAIL=1; fi
fi

if [[ $FAIL -eq 0 ]]; then
  echo "  every output of group [$GROUP] exists and passes its check: the convergence task may start."
  echo "  The main session now: runs each task's required verification, marks ✅, appends the PROGRESS.md entry."
  echo "FANOUT: PASS"
else
  echo "  at least one task did not deliver: do NOT start convergence; failed tasks stay ⬜/🔄 in the plan."
  echo "FANOUT: FAIL"; exit 1
fi
