# Changelog

All notable changes to keel. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [1.1.0] — 2026-09-28

keel as a plugin — Claude Code and Codex — without giving up the copy-in install.

### Added
- Plugin manifests: `.claude-plugin/plugin.json` + `marketplace.json` (Claude Code),
  `plugin.json` / `.codex-plugin/plugin.json` + `.agents/plugins/marketplace.json`
  (Codex, portable agent-plugins format). The repository is its own marketplace.
- `hooks/hooks.json`: `SessionStart` injects `AGENTS.md` (only in projects that use
  keel), `PreToolUse` enforces the planning gate at write time — shared by both agents.
- Six skills (`keel`, `keel-init`, `keel-status`, `keel-check`, `keel-premortem`,
  `keel-fanout`) and two Claude Code subagents (`checker`, `arguer`) built from the
  role prompts.
- `bin/keel`: one entry point for every script wherever the pack lives.
- `scripts/init_project.sh` (`keel init`): `.keel/` marker, `logs/agent/`,
  `.gitignore`, pre-commit hook.
- `checker.sh --from <task> <response> <artifact>`: records a checker response
  obtained elsewhere (subagent, web chat); the script still computes the verdict.
- `scripts/lib_paths.sh`: `KEEL_HOME` (the pack) and `KEEL_PROJECT` (the project)
  resolved once, for every script. `plan_graph.py` honours `KEEL_PROJECT`.

### Changed
- `scripts/hooks/claude_gate.sh` → `scripts/hooks/keel_gate.sh`: reads `cwd` from
  the hook JSON, understands Codex `apply_patch`, and stays silent in projects that
  do not use keel (so a globally installed plugin does not lock every repository).
  `KEEL_GATE=off` disables it. The old name remains as a wrapper.
- The pre-commit hook keeps its own copy of `plan_graph.py` next to itself, so it
  works without the pack in the project (plugin layout, collaborators, CI).
- Every script `cd`s to the project and reaches the pack via `KEEL_HOME`; behaviour
  in the copy-in layout is unchanged.
- `AGENTS.md`: a short paragraph on where the pack lives.

## [1.0.0] — 2026-09-07

First public release.

- Planning gate with `PLAN.md` as the agent's external working memory and
  `PROGRESS.md` as an append-only progress log.
- Verification gate (`verify.sh`) and plan graph validator (`plan_graph.py`)
  with output contracts and execution waves.
- Rubric loop with per-pass log, plan pre-mortem (`premortem.sh`), fresh-context
  checker with hash-sealed verdicts (`checker.sh`), parallel fan-out with
  model-free reduction (`fanout.sh`).
- Pre-commit hook with four deterministic checks; write-time gate for Claude Code.
- Agent-agnostic backend layer (`lib_agent.sh`: Codex, Claude Code, Gemini CLI,
  OpenCode, Copilot, custom) and `adapters/` for agents that do not read
  `AGENTS.md` natively.
- Role prompts (research, data, code, arguer, checker), 61-check test suite,
  CI on Ubuntu and macOS, MIT license, documentation site.
