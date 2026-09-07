# Changelog

All notable changes to keel. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] — 2026-09-07

First public release, under the MIT license, as `keel`.

### Added
- Visual identity: `assets/logo.svg`, `assets/logo-dark.svg`, `assets/icon.svg`; landing
  page with explanatory diagrams in `docs/index.html` (GitHub Pages, source `docs/`).
- `tests/run_tests.sh`: 61 end-to-end checks with fake agent backends (no CLI,
  no network); GitHub Actions on Ubuntu and macOS (bash 3.2) plus shellcheck.
- `LICENSE` (MIT), `CONTRIBUTING.md`, `.editorconfig`, `.gitignore`.

### Changed
- Every document, prompt, script message and comment translated to English.
  Plan markers are now English: `Plan status: DRAFT | APPROVED`, `Depends on`,
  `Verification`, `critical`, `## Contracts` with `shape:`, `## Objective`,
  `## Active requirements`, `## Decisions`, `ASSUMED:`, `PRE-MORTEM:`,
  `(removed: ...)`, `(reopened by user: ...)`.
- The checker's JSON keys are English (`check_accurate`, `check_current`,
  `check_references`, `result`, `note`, `verdict`, `rationale`); the verdict
  file uses `RATIONALE:`.
- `AGENTS.md` §5: the agent answers in the language the user writes in.

### Migration from the Italian v2.1 pack
Existing `PLAN.md` files need their markers renamed (see "Changed"); the
table structure, emoji statuses and `[P]` labels are unchanged.

## [2.1.0] — 2026-09-06 (pre-release, Italian)

### Added
- `scripts/lib_agent.sh`: selectable backend (`AGENT_BACKEND` = codex | claude |
  gemini | opencode | copilot | custom | auto) with flags verified on the real
  CLIs; replaces `lib_codex.sh`.
- `adapters/`: bridge files for Claude Code (`CLAUDE.md` importing `AGENTS.md`
  + `PreToolUse` hook enforcing the gate at write time), Gemini CLI
  (`.gemini/settings.json` → `context.fileName`), Aider (`.aider.conf.yml`);
  installer and compatibility matrix.
- `scripts/hooks/claude_gate.sh`.

### Changed
- All model-specific wording removed from the rules.
- The checker asks for JSON in the prompt and parses it tolerantly (pure JSON,
  fenced JSON, JSON amid text, or the line format), since only Codex enforces
  a schema from the CLI.

### Fixed
- macOS stock bash 3.2 compatibility: no `mapfile`, no associative arrays,
  safe empty-array expansion under `set -u`, `plan_graph` invoked through a
  function (temporary `IFS` broke string splitting), portable `date`.
- Backends that `cd` into the working folder received relative paths.

## [2.0.0] — 2026-09-06 (pre-release, Italian)

Innested the three levels of *Agents, Loops, Graphs* (A. Figura, 2026).

### Added
- `PROGRESS.md` append-only progress log (SOP-10) and `PROGRESS.template.md`.
- Rubric loop pass table, score-drop stop, vague-criterion rule through the
  gate, "is the loop worth it" conditions (SOP-7).
- Plan pre-mortem from a fresh context (SOP-9, `premortem.sh`, `prompts/arguer.md`).
- Fresh-context checker as a script with artifact hash in the verdict file;
  three checks with the 2-of-3 rule; verdict computed by the script
  (`checker.sh`, `prompts/checker.md`, `checker.schema.json`).
- `plan_graph.py`: cycles, group consistency, missing verification or
  contract, execution waves; output contracts (`## Contracts`).
- `fanout.sh`: one session per task, model-free reduction, `FANOUT WORKER`
  mode in `AGENTS.md`.
- Role prompts: research, data, code.
- Pre-commit hook grew from 2 to 4 checks (verdict file with hash instead of a
  `KEEP` string in Notes; plan graph; `PROGRESS.md` append-only).

### Fixed
- `verify.sh` passed `--pretty=False` to mypy, which mypy rejects (static
  verification always failed where mypy was installed).
- `health_report.sh` did not print "none" when no screenshots existed.

## [1.x] — 2026-08 (internal, Italian)

Original plan-driven pack for a single agent: planning gate, `PLAN.md` as
external working memory, `verify.sh`, SOP-0..SOP-8, two-check pre-commit hook.
