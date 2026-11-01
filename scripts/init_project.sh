#!/usr/bin/env bash
# init_project.sh — sets up the CURRENT project to work with keel installed as a
# plugin (or from any folder). Idempotent: run it again after an update.
#
# It creates only what must live in the project and survive without the pack:
#   .keel/config          marker: tells the gate and the session hook that this project uses keel
#   logs/agent/           where verify/checker/premortem/fanout write (added to .gitignore)
#   .git/hooks/pre-commit the four deterministic checks, with its own copy of plan_graph.py
# It does NOT create PLAN.md: the agent does, from PLAN.template.md, when a complex task arrives.
#
# Usage: bash scripts/init_project.sh [project_dir]     (or: keel init [project_dir])

set -euo pipefail
[[ -n "${1:-}" ]] && export KEEL_PROJECT="$1"
# shellcheck source=lib_paths.sh
source "$(dirname "$0")/lib_paths.sh"
cd "$KEEL_PROJECT" || exit 1

VERSION=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version","?"))' "$KEEL_HOME/.claude-plugin/plugin.json" 2>/dev/null || echo "?")

echo "keel init — project: $KEEL_PROJECT"
echo "            pack:    $KEEL_HOME"

mkdir -p .keel
{
  echo "# keel marker — this project uses the plan-driven operating layer (https://github.com/matrixfede/keel)."
  echo "# Presence of this folder switches on the write-time gate and the session rules of the keel plugin."
  echo "keel_version: $VERSION"
  echo "initialised: $(date +%F)"
} > .keel/config
echo "  .keel/config written"

mkdir -p logs/agent
if [[ -f .gitignore ]] && grep -qxE 'logs/?' .gitignore; then :; else echo "logs/" >> .gitignore; echo "  logs/ added to .gitignore"; fi

if git rev-parse --git-dir >/dev/null 2>&1; then
  bash "$KEEL_HOME/scripts/install_git_hook.sh" | sed 's/^/  /'
else
  echo "  not a git repository: pre-commit hook skipped (git init, then: keel hook)"
fi

if [[ -f AGENTS.md ]] && grep -q "PLANNING GATE" AGENTS.md; then
  echo "  AGENTS.md from keel already in the project: rules load natively."
else
  echo "  Rules are injected by the plugin at session start (SessionStart hook)."
  echo "  For agents without the plugin, copy $KEEL_HOME/AGENTS.md into the project (or append it to yours)."
fi
echo "  Templates: $KEEL_HOME/PLAN.template.md · $KEEL_HOME/PROGRESS.template.md"
echo "KEEL: READY"
