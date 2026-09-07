#!/usr/bin/env bash
# health_report.sh — compact snapshot of the project state.
# Run at session start (SOP-2, resume protocol).

cd "$(dirname "$0")/.." || exit 1

echo "═ HEALTH REPORT ═ $(date +%Y-%m-%dT%H:%M:%S%z)"

echo "─ Git"
echo "  branch: $(git branch --show-current 2>/dev/null || echo 'n/a')"
echo "  uncommitted changed files: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
git log --oneline -3 2>/dev/null | sed 's/^/  /'

echo "─ Last verify"
if [[ -f logs/agent/last_verify.txt ]]; then
  sed 's/^/  /' logs/agent/last_verify.txt
else
  echo "  never run"
fi

echo "─ PLAN.md"
if [[ -f PLAN.md ]]; then
  head -3 PLAN.md | grep -i "Plan status" | sed 's/^/  /' || true
  grep -E '^\| *[0-9]+ ' PLAN.md | awk -F'|' '
    {gsub(/^ +| +$/,"",$2); gsub(/^ +| +$/,"",$3); gsub(/^ +| +$/,"",$4);
     printf "  #%-3s %-45s %s\n", $2, substr($3,1,45), $4}'
  echo "  ── open tasks: $(grep -cE '^\| *[0-9]+ .*(⬜|🔄|⛔)' PLAN.md)"
  if command -v python3 >/dev/null 2>&1; then
    echo "  ── graph: $(python3 scripts/plan_graph.py --quiet 2>/dev/null | tail -1)"
  fi
else
  echo "  MISSING — create from PLAN.template.md before writing code"
fi

echo "─ PROGRESS.md (last entry)"
if [[ -f PROGRESS.md ]]; then
  awk '/^## /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' PROGRESS.md | sed 's/^/  /'
  echo "  ── total entries: $(grep -c '^## ' PROGRESS.md)"
else
  echo "  missing — created from PROGRESS.template.md when the plan is approved (SOP-10)"
fi

echo "─ Checker verdicts (critical tasks)"
if ls logs/agent/checker_task*.txt >/dev/null 2>&1; then
  for f in logs/agent/checker_task*.txt; do
    printf '  %s: %s (%s)\n' "$(grep '^TASK:' "$f" | cut -d' ' -f2- | sed 's/^/task /')" \
      "$(grep '^VERDICT:' "$f" | cut -d' ' -f2-)" "$(grep '^DATE:' "$f" | cut -d' ' -f2- | cut -c1-16)"
  done
else
  echo "  none"
fi

echo "─ Recent UI screenshots"
if ls logs/agent/*.png >/dev/null 2>&1; then ls -1t logs/agent/*.png | head -4 | sed 's/^/  /'; else echo "  none"; fi
