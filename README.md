<p align="left">
  <img src="assets/logo.svg" alt="keel" width="240">
</p>

**A plan-driven operating layer for coding agents — any agent, any model.**

[![tests](https://github.com/matrixfede/keel/actions/workflows/ci.yml/badge.svg)](https://github.com/matrixfede/keel/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![site](https://img.shields.io/badge/site-matrixfede.github.io%2Fkeel-2F6F8F)](https://matrixfede.github.io/keel/)

keel is a small set of markdown rules, templates and shell scripts you drop into
a repository so that a coding agent — Codex, Claude Code, Gemini CLI, Cursor,
GitHub Copilot, OpenCode, Aider or Pi — works the same way on every complex
task: **plan first, get the plan approved, verify before closing, keep an
append-only record, and never grade its own work.**

No framework, no server, no SDK. Markdown, bash (3.2+, a stock Mac is fine),
python3 standard library, git.

## Install

```bash
git clone https://github.com/matrixfede/keel.git /tmp/keel
cd /path/to/your/project
cp -r /tmp/keel/{AGENTS.md,prompts,adapters,scripts,PLAN.template.md,PROGRESS.template.md} .
mkdir -p docs && cp /tmp/keel/docs/AGENT_SOP.md docs/
chmod +x scripts/*.sh scripts/hooks/*.sh adapters/*.sh
mkdir -p logs/agent && echo "logs/" >> .gitignore
bash scripts/install_git_hook.sh                 # pre-commit hook, 4 deterministic checks
bash adapters/install_adapter.sh claude          # only for Claude Code, Gemini CLI or Aider (claude|gemini|aider|all)
git add -A && git commit -m "chore: add keel"
```

Codex, Cursor, Copilot, OpenCode and Pi read `AGENTS.md` natively. Claude Code,
Gemini CLI and Aider get a one-line bridge file from `adapters/install_adapter.sh`.
If the project already has an `AGENTS.md`, append keel's to it instead of
overwriting.

## How it works

1. **You describe a problem**, not a command.
2. **The agent writes `PLAN.md` and stops.** Objective, dated requirements, a
   task table with a verification per row, output contracts, the plan graph
   validated (`GRAPH: OK`), and — for critical or hard-to-undo work — a
   pre-mortem run from a fresh context. It ends with
   `Plan awaiting approval. Reply "go" to proceed, or state your corrections.`
3. **You reply `go`**, or correct the plan; it stays `DRAFT` until you do.
4. **The agent works task by task.** `🔄` → verification runs → `✅` only on
   PASS. Every checkpoint appends an entry to `PROGRESS.md`. Every action is
   explained in plain words — what, why, effect — in the language you write in.

To skip the gate once, say so explicitly: "skip the plan".

## What's in the box

| | |
|---|---|
| `AGENTS.md` | The rules: planning gate, status marking, verification gate, communication style, working method. Standard `agents.md` file. |
| `docs/AGENT_SOP.md` | Operating procedures SOP-0 … SOP-10. |
| `PLAN.template.md` · `PROGRESS.template.md` | Working memory (state) and progress log (append-only history). |
| `scripts/verify.sh` | Validation gate for code — lint, types, tests, plan graph → `VERIFY: PASS\|FAIL`. |
| `scripts/plan_graph.py` | Reads the plan table as a graph: cycles, fake independence, missing verification or contract, execution waves → `GRAPH: OK\|FAIL`. |
| `scripts/checker.sh` | Fresh-context hostile review of critical tasks; verdict file with the artifact's SHA-256 → `CHECKER: KEEP\|DROP`. |
| `scripts/premortem.sh` | Plan pre-mortem from a fresh context → `PREMORTEM: DONE`. |
| `scripts/fanout.sh` | One session per task of a parallel group, then a model-free reduction → `FANOUT: PASS\|FAIL`. |
| `scripts/lib_agent.sh` | The only place an agent CLI is invoked: `codex`, `claude`, `gemini`, `opencode`, `copilot`, `custom`. |
| `scripts/install_git_hook.sh` | Pre-commit hook: no code while `DRAFT`; no critical `✅` without a valid verdict; no broken graph; no line removed from `PROGRESS.md`. |
| `scripts/hooks/claude_gate.sh` | Claude Code only: the gate enforced at write time via `PreToolUse`. |
| `prompts/` | Role prompts — research, data, code, arguer (pre-mortem), checker (+ JSON schema). |
| `adapters/` | Bridge files and the agent compatibility matrix. |
| `tests/run_tests.sh` | 61 end-to-end checks; no agent CLI or network needed. |

## The three levels

**Agent.** `PLAN.md` says where the work is; `PROGRESS.md` says how it got
there, one DID / DECIDED / BLOCKED / NEXT entry per checkpoint, never
rewritten. Before approval, `premortem.sh` asks a fresh session not "is the plan
good?" but "it failed — why?", and the top three answers enter the plan with a
countermeasure each.

**Loop.** Outputs a test can't judge (documents, analyses) are verified against
a rubric of 3–5 measurable criteria approved with the plan. Each pass logs a
row — weakest criterion, score, what changed, new score. A score that drops
stops the loop; a criterion that stays weakest three times is reworded through
the gate. Two stop conditions, always: success or ceiling.

**Graph.** "Depends on" holds real dependencies only; `plan_graph.py` proves
it and prints the execution waves. Tasks in a parallel group declare an output
contract — file, shape, a runnable check — so the next node can consume the
result with nobody in between. `fanout.sh` runs a group in parallel and
reduces without a model. Critical tasks pass through `checker.sh`: a new
session in a folder holding only a copy of the artifact, three independent
checks, at least two out of three, verdict computed by the script and sealed
with the artifact's hash so it expires if the file changes.

## Compatibility

Everything binding is markdown, standard python3 and git — identical for every
agent. What varies is isolated in two places: how an agent reads `AGENTS.md`
(`adapters/`) and how a fresh session is opened (`scripts/lib_agent.sh`).

| Agent | `AGENTS.md` | Fresh sessions |
|---|---|---|
| OpenAI Codex | native | `codex exec`, OS sandbox, JSON schema |
| Claude Code | `CLAUDE.md` bridge + write-time hook | `claude -p --restricted` |
| Gemini CLI | `.gemini/settings.json` bridge | `gemini -p --approval-mode plan\|yolo` |
| Cursor · GitHub Copilot · OpenCode · Pi | native | `copilot -p`, `opencode run`, or `custom` |
| Aider | `.aider.conf.yml` bridge | `custom` |

Without any CLI, `checker.sh`, `premortem.sh` and `fanout.sh` write the prompt
for a session you open by hand — any agent, even a web chat — and record the
outcome with `--record` / `--reduce`. Details in [`adapters/README.md`](adapters/README.md).

## API use

Concatenate `AGENTS.md`, `docs/AGENT_SOP.md` and, optionally, a role prompt
into the system-instructions field of any provider. `prompts/checker.schema.json`
is a JSON schema for structured checker responses.

## Tests

```bash
bash tests/run_tests.sh        # 61 checks · fake agent backends · Ubuntu and macOS (bash 3.2) in CI
```

## License

[MIT](LICENSE) © 2026 Federico Gabrielli
