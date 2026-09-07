#!/usr/bin/env bash
# run_tests.sh — end-to-end test suite for keel. No agent CLI or network needed:
# agent backends are replaced by fake binaries that record their argv and
# return canned answers, so what is tested is the pack's own logic:
# plan_graph.py, the four pre-commit checks, checker.sh (all backends + parsing),
# premortem.sh, fanout.sh (run / --prompt / --reduce), adapters, claude_gate.sh.
#
# Usage: bash tests/run_tests.sh            (any bash ≥ 3.2; CI runs it on Ubuntu and macOS)
# Result: last line "TESTS: PASS" or "TESTS: FAIL" + exit code.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/keel-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
RESULTS="$WORK/results"; : > "$RESULTS"   # a file, not counters: ok/bad often run inside pipelines (subshells)

ok()   { echo ok  >> "$RESULTS"; echo "  ✓ $1"; }
bad()  { echo bad >> "$RESULTS"; echo "  ✗ $1"; }
# expect <description> <expected-substring> <<< "<actual output>"
expect() { local out; out=$(cat); if grep -qF -- "$2" <<< "$out"; then ok "$1"; else bad "$1 — expected '$2', got: $(echo "$out" | tail -3 | tr '\n' '|')"; fi; }

echo "═ keel tests ═ bash $BASH_VERSION"

# ── fixture: a fresh copy of the pack inside a git repo ─────────────────────
R="$WORK/repo"; mkdir -p "$R"
cp -r "$ROOT"/. "$R"/ ; rm -rf "$R/.git" "$R/tests" "$R/logs"
cd "$R" && git init -q && git config user.email t@t && git config user.name t && git config commit.gpgsign false
mkdir -p logs/agent out && echo "logs/" > .gitignore
bash scripts/install_git_hook.sh >/dev/null
cat > PLAN.md <<'EOF'
# PLAN — test
**Plan status: DRAFT — awaiting approval**
## Objective
Exercise the pack.
## Active requirements
- R1: everything must work (source: user, 2026-01-01)
## Plan
| # | Task | Status | Depends on | Verification | Notes |
|---|------|--------|------------|--------------|-------|
| 1 | write a | ⬜ todo | — | `verify.sh unit` | [P1] |
| 2 | write b | ⬜ todo | — | `verify.sh unit` | [P1] |
| 3 | merge | ⬜ todo | 1, 2 | `verify.sh all` | critical |
## Contracts
- Task 1 — OUT: `out/a.md` — shape: markdown with a title — check: `grep -q "^# " out/a.md`
- Task 2 — OUT: `out/b.tsv` — shape: TSV with an id header — check: `head -1 out/b.tsv | grep -q "^id"`
## Decisions
- D1: none
EOF
echo "merged" > merged.txt

# ── fake agent CLIs ─────────────────────────────────────────────────────────
FAKE="$WORK/fakebin"; mkdir -p "$FAKE"; : > "$FAKE/argv.log"
for c in codex claude gemini opencode copilot; do
cat > "$FAKE/$c" <<'EOF'
#!/usr/bin/env bash
me=$(basename "$0"); echo "$me $*" >> "$(dirname "$0")/argv.log"
stdin=""; [[ -t 0 ]] || stdin=$(cat)
out=""; args=("$@")
# codex writes its last message to the -o file; the others print to stdout
if [[ "$me" == "codex" ]]; then while [[ $# -gt 0 ]]; do case "$1" in -o) out="$2"; shift;; esac; shift; done; fi
if grep -q "FANOUT WORKER" <<< "$stdin${args[*]}"; then
  n=$(grep -m1 -oE "task [0-9]+" <<< "$stdin${args[*]}" | awk '{print $2}')
  if [[ $n == 1 ]]; then echo "# A" > out/a.md; else printf 'id\tv\n' > out/b.tsv; fi
  ans=$(printf 'done.\n\nTASK %s: DONE\n' "$n")
elif grep -q "pre-mortem" <<< "$stdin${args[*]}"; then ans="PLAN IN ONE SENTENCE: test"
else ans="${FAKE_ANSWER:-}"; fi
if [[ -n "$out" ]]; then echo "$ans" > "$out"; else echo "$ans"; fi
EOF
chmod +x "$FAKE/$c"; done
NOAGENT_PATH="/usr/bin:/bin:/usr/local/bin"   # no agent CLI visible
AGENT_PATH="$FAKE:$PATH"
KEEP3='{"check_accurate":{"result":"PASS","note":"ok"},"check_current":{"result":"PASS","note":"ok"},"check_references":{"result":"PASS","note":"ok"},"verdict":"KEEP","rationale":"tried to break it, holds"}'
KEEP1='{"check_accurate":{"result":"PASS","note":"ok"},"check_current":{"result":"FAIL","note":"old"},"check_references":{"result":"FAIL","note":"dead link"},"verdict":"KEEP","rationale":"meh"}'

echo "─ plan_graph.py"
cp PLAN.md PLAN.bak
python3 scripts/plan_graph.py --quiet | expect "valid plan → GRAPH: OK" "GRAPH: OK"
python3 scripts/plan_graph.py --group P1 | tr '\n' ' ' | expect "--group P1 lists tasks 1 2" "1 2"
python3 scripts/plan_graph.py --contract 2 | expect "--contract 2 returns OUT" "out/b.tsv"
python3 scripts/plan_graph.py --task 1 | expect "--task 1 includes CHECK" "CHECK: grep"
cp PLAN.template.md PLAN.md; python3 scripts/plan_graph.py --quiet | expect "template itself is a valid plan" "GRAPH: OK"
cat > PLAN.md <<'EOF'
**Plan status: APPROVED (2026-01-01)**
## Plan
| # | Task | Status | Depends on | Verification | Notes |
|---|------|--------|------------|--------------|-------|
| 1 | a | ⬜ todo | 3 | `verify.sh unit` | [P1] |
| 2 | b | ⬜ todo | 1 | `verify.sh unit` | [P1] |
| 3 | c | ⬜ todo | 2 | | critical |
| 4 | d | ✅ done | 9 | `verify.sh all` | |
## Contracts
- Task 1 — OUT: `out/a.md` — shape: x
EOF
OUTG=$(python3 scripts/plan_graph.py --quiet)
expect "same-group dependency detected" "both in [P1]" <<< "$OUTG"
expect "missing verification detected" "no verification declared" <<< "$OUTG"
expect "unknown dependency detected" "does not exist" <<< "$OUTG"
expect "missing contract detected" "has no output contract" <<< "$OUTG"
expect "cycle detected" "cycle in the dependencies" <<< "$OUTG"
expect "broken plan → GRAPH: FAIL" "GRAPH: FAIL" <<< "$OUTG"
cp PLAN.bak PLAN.md

echo "─ pre-commit hook"
git add -A >/dev/null && git commit -qm init && ok "initial commit (pack + DRAFT plan, no code) passes"
echo "print(1)" > app.py; git add app.py
git commit -qm x 2>&1 | expect "check 1: DRAFT + code → blocked" "still DRAFT"
sed -i.bak 's/DRAFT — awaiting approval/APPROVED (2026-01-01)/' PLAN.md && rm -f PLAN.md.bak
git add -A && git commit -qm approved && ok "APPROVED + code → commit passes"
sed -i.bak 's/| 3 | merge | ⬜ todo/| 3 | merge | ✅ done/' PLAN.md && rm -f PLAN.md.bak
git add -A; git commit -qm x 2>&1 | expect "check 2: critical ✅ without verdict → blocked" "missing logs/agent/checker_task3.txt"
PATH="$NOAGENT_PATH" bash scripts/checker.sh --record 3 KEEP "holds" merged.txt | expect "checker --record KEEP" "CHECKER: KEEP"
git add -A && git commit -qm closed && ok "critical ✅ with valid verdict → commit passes"
echo "x" >> merged.txt; git add -A
git commit -qm x 2>&1 | expect "check 2: artifact changed after KEEP → blocked" "changed after the checker"
git checkout -q HEAD -- merged.txt; git reset -q
sed -i.bak 's/| 1, 2 |/| 1, 2, 7 |/' PLAN.md && rm -f PLAN.md.bak; git add PLAN.md
git commit -qm x 2>&1 | expect "check 3: broken graph → blocked" "plan graph has errors"
git checkout -q HEAD -- PLAN.md; git reset -q
cp PROGRESS.template.md PROGRESS.md && git add PROGRESS.md && git commit -qm progress && ok "PROGRESS.md created"
printf '\n## 2026-01-02 09:00\n- DID: test\n- DECIDED: —\n- BLOCKED: —\n- NEXT: task 4\n' >> PROGRESS.md
git add PROGRESS.md && git commit -qm append && ok "PROGRESS.md append → commit passes"
sed -i.bak '/^## 2026-01-01 10:00/,/^- NEXT: task 1/d' PROGRESS.md && rm -f PROGRESS.md.bak; git add PROGRESS.md
git commit -qm x 2>&1 | expect "check 4: lines removed from PROGRESS.md → blocked" "lines removed from PROGRESS.md"
git checkout -q HEAD -- PROGRESS.md; git reset -q

echo "─ checker.sh"
PATH="$NOAGENT_PATH" bash scripts/checker.sh 3 merged.txt | expect "no agent → prompt mode" "CHECKER: PROMPT"
for be in codex claude gemini opencode copilot; do
  PATH="$AGENT_PATH" AGENT_BACKEND=$be FAKE_ANSWER="Here you go:
\`\`\`json
$KEEP3
\`\`\`" bash scripts/checker.sh 3 merged.txt | expect "backend $be: JSON in a fence → KEEP" "CHECKER: KEEP"
done
PATH="$AGENT_PATH" AGENT_BACKEND=claude FAKE_ANSWER="$KEEP1" bash scripts/checker.sh 3 merged.txt | expect "model KEEP with 1/3 → downgraded to DROP" "CHECKER: DROP"
PATH="$AGENT_PATH" AGENT_BACKEND=claude FAKE_ANSWER='CHECK-1 accurate: PASS — ok
CHECK-2 current: PASS — ok
CHECK-3 references: FAIL — x
VERDICT: KEEP
RATIONALE: fine' bash scripts/checker.sh 3 merged.txt | expect "line-format fallback parsed" "CHECKER: KEEP"
PATH="$AGENT_PATH" AGENT_BACKEND=claude FAKE_ANSWER='garbage' bash scripts/checker.sh 3 merged.txt | expect "unreadable answer → ERROR, no verdict" "CHECKER: ERROR"
PATH="$AGENT_PATH" AGENT_BACKEND=custom AGENT_CMD_READONLY='echo "$FAKE_ANSWER" > "$OUT_FILE"' AGENT_CMD_WRITE=true FAKE_ANSWER="$KEEP3" bash scripts/checker.sh 3 merged.txt | expect "custom backend" "CHECKER: KEEP"
grep -q "codex exec --skip-git-repo-check --ephemeral --color never -C .* -s read-only -o .* --output-schema .*checker.schema.json -" "$FAKE/argv.log" && ok "codex argv: exec, read-only sandbox, -o, --output-schema" || bad "codex argv"
grep -q "claude -p --output-format text --no-session-persistence --restricted --tools Read,Glob,Grep" "$FAKE/argv.log" && ok "claude argv: -p, --restricted, read tools only" || bad "claude argv"
grep -q "gemini -p .* --approval-mode plan -o text" "$FAKE/argv.log" && ok "gemini argv: --approval-mode plan" || bad "gemini argv"
grep -q "opencode run --dir .* --agent plan" "$FAKE/argv.log" && ok "opencode argv: run --agent plan" || bad "opencode argv"
grep -q -- "--allow-all-tools --no-ask-user --deny-tool shell --deny-tool write" "$FAKE/argv.log" && ok "copilot argv: deny shell/write" || bad "copilot argv"
grep -c "checker_task3.raw.txt" "$FAKE/argv.log" >/dev/null && ok "artifact copied to a temp dir (fresh context), not the repo" || bad "tmp dir"

echo "─ premortem.sh"
PATH="$NOAGENT_PATH" bash scripts/premortem.sh | expect "no agent → prompt mode" "PREMORTEM: PROMPT"
PATH="$AGENT_PATH" AGENT_BACKEND=claude bash scripts/premortem.sh | expect "with agent → DONE" "PREMORTEM: DONE"
ls logs/agent/premortem_*.prompt.md >/dev/null 2>&1 && grep -q "Arguer / pre-mortem" "$(ls logs/agent/premortem_*.prompt.md | head -1)" && ok "prompt = arguer.md + PLAN.md" || bad "premortem prompt"

echo "─ fanout.sh"
rm -f out/*
PATH="$AGENT_PATH" AGENT_BACKEND=claude bash scripts/fanout.sh P1 | expect "run: 2 workers + reduction → PASS" "FANOUT: PASS"
grep -q "claude -p --output-format text --no-session-persistence --permission-mode acceptEdits" "$FAKE/argv.log" && ok "worker argv: acceptEdits" || bad "worker argv"
grep -q "FANOUT WORKER — task 1" logs/agent/fanout_P1_task1.prompt.md && ok "worker prompt opens with FANOUT WORKER" || bad "worker prompt"
PATH="$NOAGENT_PATH" bash scripts/fanout.sh P1 --prompt | expect "--prompt without agent" "FANOUT: PROMPT"
PATH="$NOAGENT_PATH" bash scripts/fanout.sh P1 --reduce | expect "--reduce with outputs present → PASS" "FANOUT: PASS"
printf 'x\n' > out/b.tsv
PATH="$NOAGENT_PATH" bash scripts/fanout.sh P1 --reduce | expect "--reduce with failing check → FAIL" "check failed"
PATH="$NOAGENT_PATH" FANOUT_MAX=1 bash scripts/fanout.sh P1 --prompt | expect "FANOUT_MAX ceiling enforced" "the ceiling is 1"
sed -i.bak 's/APPROVED (2026-01-01)/DRAFT — awaiting approval/' PLAN.md && rm -f PLAN.md.bak
PATH="$NOAGENT_PATH" bash scripts/fanout.sh P1 --prompt | expect "DRAFT plan refused" "not APPROVED"
git checkout -q HEAD -- PLAN.md

echo "─ verify.sh / health_report.sh"
PATH="$NOAGENT_PATH" bash scripts/verify.sh static | expect "verify static includes the graph" "VERIFY: PASS"
bash scripts/health_report.sh | expect "health report shows graph line" "graph: GRAPH: OK"
bash scripts/health_report.sh | expect "health report shows last PROGRESS entry" "NEXT: task 4"
bash scripts/health_report.sh | expect "health report lists checker verdicts" "task 3: KEEP"

echo "─ adapters / claude_gate.sh"
bash adapters/install_adapter.sh all | expect "install_adapter all" "created: .claude/settings.json"
[[ -f CLAUDE.md && -f .gemini/settings.json && -f .aider.conf.yml ]] && ok "bridge files created" || bad "bridge files"
bash adapters/install_adapter.sh claude | expect "second run does not overwrite" "already exists"
echo '{"tool_name":"Write","tool_input":{"file_path":"src/app.py"}}' | bash scripts/hooks/claude_gate.sh; [[ $? -eq 0 ]] && ok "claude_gate: APPROVED → allow" || bad "claude_gate approved"
sed -i.bak 's/APPROVED (2026-01-01)/DRAFT — awaiting approval/' PLAN.md && rm -f PLAN.md.bak
echo '{"tool_name":"Write","tool_input":{"file_path":"src/app.py"}}' | bash scripts/hooks/claude_gate.sh 2>/dev/null; [[ $? -eq 2 ]] && ok "claude_gate: DRAFT → block (exit 2)" || bad "claude_gate draft"
echo '{"tool_name":"Edit","tool_input":{"file_path":"/x/PLAN.md"}}' | bash scripts/hooks/claude_gate.sh; [[ $? -eq 0 ]] && ok "claude_gate: DRAFT but PLAN.md → allow" || bad "claude_gate plan"
git checkout -q HEAD -- PLAN.md

echo "─ syntax"
for f in scripts/*.sh scripts/hooks/*.sh adapters/*.sh; do bash -n "$f" || bad "syntax $f"; done; ok "bash -n on every script"
python3 -m py_compile scripts/plan_graph.py scripts/agent_logging.py && ok "py_compile" || bad "py_compile"
python3 -c 'import json,sys; [json.load(open(p)) for p in sys.argv[1:]]' prompts/checker.schema.json adapters/claude/claude-settings.json adapters/gemini/.gemini/settings.json && ok "json files parse" || bad "json"

PASS=$(grep -c '^ok$' "$RESULTS"); FAIL=$(grep -c '^bad$' "$RESULTS")
echo
echo "  passed: $PASS  failed: $FAIL"
if [[ "$FAIL" -eq 0 ]]; then echo "TESTS: PASS"; exit 0; else echo "TESTS: FAIL"; exit 1; fi
