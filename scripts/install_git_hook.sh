#!/usr/bin/env bash
# install_git_hook.sh — installs a pre-commit hook that deterministically enforces
# four rules of the kit:
#   1. no code commits while the plan is DRAFT (planning gate)
#   2. no `critical` task closed ✅ without the checker's verdict FILE with a
#      still-valid artifact hash (SOP-8) — writing KEEP in Notes is not enough
#   3. no commit with a broken plan graph (plan_graph.py → GRAPH: FAIL)
#   4. no lines removed from PROGRESS.md: the log is append-only (SOP-10)
#
# This is the deterministic enforcement that holds for ANY agent (Codex, Claude
# Code, Gemini CLI, Cursor, Copilot, OpenCode...): the rules in AGENTS.md are
# instructions the model may skip; this hook is not.
# It does not intercept writes to disk, only commits — but that is where
# unapproved work becomes permanent, so it is the point that matters.
#
# Usage:  bash scripts/install_git_hook.sh
# Bypass: git commit --no-verify   (for the cases where you know what you are doing)

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
[[ -d .git ]] || { echo "Not a git repository."; exit 1; }

mkdir -p .git/hooks
cat > .git/hooks/pre-commit <<'HOOK'
#!/usr/bin/env bash
# Pre-commit hook of the plan-driven agent pack (keel). Four checks, all deterministic.

[[ -f PLAN.md ]] || exit 0

STAGED=$(git diff --cached --name-only | grep -v '^PLAN.md$' | grep -v '^PLAN_ARCHIVE.md$' | grep -v '^PROGRESS.md$' || true)

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else echo "no-sha256-tool"; fi
}

# --- Check 1: plan in DRAFT + code changes ---
if grep -qi "Plan status:.*DRAFT" PLAN.md && [[ -n "$STAGED" ]]; then
  cat >&2 <<'MSG'

  COMMIT BLOCKED — the plan is still DRAFT.

  PLAN.md says "Plan status: DRAFT — awaiting approval", but this commit
  contains code changes. The plan must be approved before working.

  If you approved the plan, update the PLAN.md header:
      Plan status: APPROVED (YYYY-MM-DD)

  To proceed anyway: git commit --no-verify

MSG
  exit 1
fi

# --- Check 2: critical ✅ task without a valid checker verdict ---
# For every table row with `critical` and ✅, logs/agent/checker_task<N>.txt must
# exist with VERDICT: KEEP and, for every ARTIFACT listed, a SHA256 hash still
# equal to the current file's. KEEP written in Notes does not count: the same
# agent that did the work would write it.
BAD=""
while IFS= read -r line; do
  n=$(echo "$line" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
  [[ "$n" =~ ^[0-9]+$ ]] || continue
  f="logs/agent/checker_task${n}.txt"
  if [[ ! -f "$f" ]]; then BAD+="  task $n: missing $f (run scripts/checker.sh $n <artifact>)"$'\n'; continue; fi
  if ! grep -q '^VERDICT: KEEP' "$f"; then BAD+="  task $n: verdict in $f is not KEEP"$'\n'; continue; fi
  art=""
  while IFS= read -r vl; do
    case "$vl" in
      ARTIFACT:*) art="${vl#ARTIFACT: }" ;;
      SHA256:*)
        want="${vl#SHA256: }"
        if [[ ! -f "$art" ]]; then BAD+="  task $n: the reviewed artifact no longer exists: $art"$'\n'
        elif [[ "$(sha256_of "$art")" != "$want" ]]; then
          BAD+="  task $n: $art changed after the checker's review — rerun scripts/checker.sh $n $art"$'\n'
        fi ;;
    esac
  done < "$f"
done < <(grep -E '^\|' PLAN.md | grep '✅' | grep -i 'critical' | grep -v '~~')

if [[ -n "$BAD" ]]; then
  cat >&2 <<'MSG'

  COMMIT BLOCKED — critical task closed without a valid checker (SOP-8).

  Tasks marked `critical` require the hostile fresh-context review before
  closing, recorded by scripts/checker.sh with the artifact's hash. Detail:

MSG
  printf '%s' "$BAD" >&2
  echo >&2
  echo "  To proceed anyway: git commit --no-verify" >&2
  echo >&2
  exit 1
fi

# --- Check 3: plan graph ---
if command -v python3 >/dev/null 2>&1 && [[ -f scripts/plan_graph.py ]]; then
  if ! OUT=$(python3 scripts/plan_graph.py --quiet 2>&1); then
    cat >&2 <<'MSG'

  COMMIT BLOCKED — the plan graph has errors (SOP-8).

MSG
    echo "$OUT" | sed 's/^/  /' >&2
    echo >&2
    echo "  Fix PLAN.md (python3 scripts/plan_graph.py for details). Bypass: git commit --no-verify" >&2
    echo >&2
    exit 1
  fi
fi

# --- Check 4: PROGRESS.md is append-only ---
if git diff --cached --name-only | grep -q '^PROGRESS.md$' && git cat-file -e HEAD:PROGRESS.md 2>/dev/null; then
  REMOVED=$(git diff --cached -U0 -- PROGRESS.md | grep -E '^-[^-]' | grep -v '^---' || true)
  if [[ -n "$REMOVED" ]]; then
    cat >&2 <<'MSG'

  COMMIT BLOCKED — lines removed from PROGRESS.md (SOP-10).

  The progress log can only get longer: never rewrite or delete entries.
  Lines this commit would remove:

MSG
    echo "$REMOVED" | head -10 | sed 's/^/  /' >&2
    echo >&2
    echo "  Restore the lines (git checkout HEAD -- PROGRESS.md and append again). Bypass: git commit --no-verify" >&2
    echo >&2
    exit 1
  fi
fi

exit 0
HOOK

chmod +x .git/hooks/pre-commit
echo "Pre-commit hook installed in .git/hooks/pre-commit"
echo "Checks: plan in DRAFT · checker with hash for critical tasks · plan graph · PROGRESS.md append-only"
echo "Test:  git commit --allow-empty -m test   (must pass: no code files)"
