#!/usr/bin/env bash
# verify.sh — single validation gate for coding agents.
# Usage: ./scripts/verify.sh [all|static|unit|integration]
# Result: last line "VERIFY: PASS" or "VERIFY: FAIL" + exit code.
#
# Detects the stack present automatically. Deliberately compact output: the
# consumer is an agent, not a human — every superfluous line is burned tokens.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MODE="${1:-all}"
FAIL=0
mkdir -p logs/agent

step() { printf '\n── %s\n' "$1"; }
has()  { command -v "$1" >/dev/null 2>&1; }
run()  { echo "  \$ $*"; "$@" || FAIL=1; }

# Stack detection
PY=0; JS=0
[[ -f pyproject.toml || -f setup.py || -f requirements.txt || -n "$(ls -1 ./*.py 2>/dev/null)" ]] && PY=1
[[ -f package.json ]] && JS=1

# ─────────────────────────────── STATIC ANALYSIS ───────────────────────────────
if [[ "$MODE" == "static" || "$MODE" == "all" ]]; then
  step "Static analysis"
  if [[ $PY -eq 1 ]]; then
    has ruff  && run ruff check . --output-format=concise
    has mypy  && run mypy . --no-error-summary
  fi
  if [[ $JS -eq 1 ]]; then
    has npx && [[ -f tsconfig.json ]] && run npx --no-install tsc --noEmit --pretty false
    has npx && run npx --no-install eslint . --format=compact
  fi
  # Plan graph (SOP-8): cycles, inconsistent groups, tasks without verification or contract.
  if [[ -f PLAN.md ]] && has python3; then
    run python3 scripts/plan_graph.py --quiet
  fi
  # Forgotten debug prints.
  # The pattern is split ("AGENT""DBG") so this script does not match itself;
  # .md files and scripts/ are excluded so the pack's own docs are not flagged.
  DBG=$(grep -rn --exclude-dir={.git,node_modules,logs,.venv,scripts,tests} \
        --exclude="*.md" "AGENT""DBG|" . 2>/dev/null | head -5)
  if [[ -n "$DBG" ]]; then
    echo "  ! temporary debug prints still present — remove before closing the task"
    echo "$DBG" | sed 's/^/    /'
    FAIL=1
  fi
fi

# ──────────────────────────────── UNIT TESTS ────────────────────────────────
if [[ "$MODE" == "unit" || "$MODE" == "all" ]]; then
  step "Unit tests"
  if [[ $PY -eq 1 ]] && has pytest; then
    run pytest -q -x --tb=short -m "not integration"
  fi
  if [[ $JS -eq 1 ]] && has npx; then
    if grep -q '"vitest"' package.json 2>/dev/null; then
      run npx --no-install vitest run --reporter=dot
    elif grep -q '"jest"' package.json 2>/dev/null; then
      run npx --no-install jest --silent
    fi
  fi
fi

# ───────────────────────────── INTEGRATION TESTS ────────────────────────────
if [[ "$MODE" == "integration" || "$MODE" == "all" ]]; then
  step "Integration tests"
  if [[ $PY -eq 1 ]] && has pytest; then
    run pytest -q --tb=short -m integration || true   # no marked tests = not an error
  fi
fi

# ──────────────────────────────────── RESULT ───────────────────────────────────
if [[ $FAIL -eq 0 ]]; then
  RESULT="VERIFY: PASS"
else
  RESULT="VERIFY: FAIL"
fi
echo "$RESULT ($(date +%H:%M:%S), mode=$MODE)" | tee logs/agent/last_verify.txt
exit $FAIL
