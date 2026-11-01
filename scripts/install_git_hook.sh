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
# Usage:  bash scripts/install_git_hook.sh        (from the project; as a plugin: `keel hook`)
# Bypass: git commit --no-verify   (for the cases where you know what you are doing)
#
# The hook must keep working when the pack is not in the project (plugin layout,
# a collaborator without the plugin, a CI checkout): plan_graph.py is therefore
# copied next to the hook, into the git hooks folder, and the hook uses that copy.

set -euo pipefail
# shellcheck source=lib_paths.sh
source "$(dirname "$0")/lib_paths.sh"
cd "$KEEL_PROJECT" || exit 1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository: $KEEL_PROJECT"; exit 1; }
HOOKS_DIR="$(git rev-parse --git-path hooks)"

mkdir -p "$HOOKS_DIR"
cp "$KEEL_HOME/scripts/plan_graph.py" "$HOOKS_DIR/keel_plan_graph.py"
cat > "$HOOKS_DIR/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# Pre-commit hook of the plan-driven agent pack (keel). Four checks, all deterministic.
# Self-contained: plan_graph.py is the copy installed next to this hook.

cd "$(git rev-parse --show-toplevel)" || exit 1
[[ -f PLAN.md ]] || exit 0
PLAN_GRAPH="$(git rev-parse --git-path hooks)/keel_plan_graph.py"
[[ -f "$PLAN_GRAPH" ]] || PLAN_GRAPH="scripts/plan_graph.py"

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
  if [[ ! -f "$f" ]]; then BAD+="  task $n: missing $f (run the keel checker: scripts/checker.sh $n <artifact>, or /keel:check)"$'\n'; continue; fi
  if ! grep -q '^VERDICT: KEEP' "$f"; then BAD+="  task $n: verdict in $f is not KEEP"$'\n'; continue; fi
  art=""
  while IFS= read -r vl; do
    case "$vl" in
      ARTIFACT:*) art="${vl#ARTIFACT: }" ;;
      SHA256:*)
        want="${vl#SHA256: }"
        if [[ ! -f "$art" ]]; then BAD+="  task $n: the reviewed artifact no longer exists: $art"$'\n'
        elif [[ "$(sha256_of "$art")" != "$want" ]]; then
          BAD+="  task $n: $art changed after the checker's review — rerun the keel checker on $art (task $n)"$'\n'
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
if command -v python3 >/dev/null 2>&1 && [[ -f "$PLAN_GRAPH" ]]; then
  if ! OUT=$(python3 "$PLAN_GRAPH" --quiet 2>&1); then
    cat >&2 <<'MSG'

  COMMIT BLOCKED — the plan graph has errors (SOP-8).

MSG
    echo "$OUT" | sed 's/^/  /' >&2
    echo >&2
    echo "  Fix PLAN.md (python3 $PLAN_GRAPH for details). Bypass: git commit --no-verify" >&2
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

chmod +x "$HOOKS_DIR/pre-commit"
echo "Pre-commit hook installed in $HOOKS_DIR/pre-commit (plan_graph.py copied alongside)"
echo "Checks: plan in DRAFT · checker with hash for critical tasks · plan graph · PROGRESS.md append-only"
echo "Test:  git commit --allow-empty -m test   (must pass: no code files)"
