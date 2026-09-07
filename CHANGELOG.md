# Changelog

All notable changes to keel. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

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
