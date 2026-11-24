# Changelog

All notable changes to keel. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [1.2.0] — 2026-11-24

Google Antigravity (`agy` CLI, IDE, Antigravity 2.0) plugin and headless CLI backend.

### Added
- Native Google Antigravity plugin support alongside Claude Code and Codex:
  - Root `hooks.json` in Antigravity's lifecycle format (`SessionStart` + `PreToolUse`
    matching `write_file`, `edit_file`, and CLI write step names).
  - `plugin.json`: square `assets/icon.svg` logo, `displayName`, and `suggestedPrompts`
    for Antigravity Customizations UI (`agy plugin validate` passes with 2 agents,
    1 hook, 6 skills).
- `agy` backend in `scripts/lib_agent.sh` (verified on `agy` 1.5): `--mode plan --sandbox`
  for read-only fresh-context sessions, `--mode auto --dangerously-skip-permissions`
  for unattended fan-out workers, and native `--json-schema` enforcement for `checker.sh`.
- End-to-end tests in `tests/run_tests.sh` covering `agy` CLI invocation, Antigravity
  `PreToolUse` JSON allow/deny/artifactDirectoryPath handling, and `SessionStart`
  `injectSteps` JSON output.

### Changed
- `scripts/hooks/keel_gate.sh` and `scripts/hooks/session_start.sh` are now polymorphic:
  they auto-detect Antigravity's camelCase JSON contracts (`toolCall` / `conversationId`)
  and return structured JSON (`{"decision":"allow"|"deny"}` / `{"injectSteps":[...]}`),
  while preserving plain-text / `exit 2` behaviour for Claude Code and Codex.
- `agents/checker.md` and `agents/arguer.md` frontmatter updated to YAML array `tools:
  [read_file, Read, Glob, Grep]` with `subagent: true` / `mainAgent: false`, loading
  cleanly in both Antigravity and Claude Code.
- Skill instructions (`skills/*/SKILL.md`) resolve the plugin root portably across
  Claude Code, Codex, and Antigravity.

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
