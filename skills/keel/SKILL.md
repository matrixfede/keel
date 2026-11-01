---
name: keel
description: Plan-driven operating rules for coding work — plan first in PLAN.md and stop for the user's "go", verify before marking ✅, append-only PROGRESS.md, fresh-context checker for critical tasks. Use at the start of any complex task (implement, add, integrate, refactor, migrate, fix, optimize, extend, rewrite; more than one file or more than three steps), whenever PLAN.md exists in the project, or when the user mentions keel, the plan gate, PLAN.md or PROGRESS.md.
---

# keel — the operating rules

keel is installed as a plugin: the pack (rules, scripts, prompts, templates) lives in
the plugin folder — the directory two levels above this file, `${CLAUDE_PLUGIN_ROOT}`
in Claude Code — while `PLAN.md`, `PROGRESS.md` and `logs/agent/` live in the project.

## Do this now

1. Read the rules in full: `AGENTS.md` at the plugin root. They are binding and start
   with the planning gate: **no code is written until the user approves the plan.**
2. If the task is complex (see the classification in the rules), read
   `docs/AGENT_SOP.md` at the plugin root, then write `PLAN.md` in the project from
   `PLAN.template.md` (plugin root), validate the graph, and **end the turn** with:
   `Plan awaiting approval. Reply "go" to proceed, or state your corrections.`
3. If the project has no `.keel/` folder and no `PLAN.md`, the write-time gate is not
   armed for it yet: tell the user and offer `/keel:init` (it also installs the
   pre-commit hook).

## Pack commands

Run from the project root. `KEEL` below is the plugin root.

| Command | Last line |
|---|---|
| `bash "$KEEL/bin/keel" graph` | `GRAPH: OK` / `GRAPH: FAIL` — plan table as a graph (SOP-8) |
| `bash "$KEEL/bin/keel" verify [all\|static\|unit]` | `VERIFY: PASS` / `VERIFY: FAIL` — required before every ✅ |
| `bash "$KEEL/bin/keel" check <n> <artifact>` | `CHECKER: KEEP` / `DROP` — critical tasks, hash-sealed verdict |
| `bash "$KEEL/bin/keel" premortem` | `PREMORTEM: DONE` — before the go, if a task is critical or hard to undo |
| `bash "$KEEL/bin/keel" fanout P1` | `FANOUT: PASS` / `FAIL` — parallel group, approved plans only |
| `bash "$KEEL/bin/keel" health` | state snapshot, run at session start (SOP-2) |

The last line decides, never the impression. In the rules, a path such as
`scripts/checker.sh` or `docs/AGENT_SOP.md` means that file under the plugin root.

## What is enforced, and by what

- **Write time**: a PreToolUse hook (`scripts/hooks/keel_gate.sh`) refuses Write/Edit/
  apply_patch on any file other than `PLAN.md` while the plan is missing or `DRAFT`.
  It is not an error to work around: it is the gate doing its job.
- **Commit time**: the pre-commit hook installed by `/keel:init` — no code while
  `DRAFT`, no critical ✅ without a valid checker verdict, no broken graph, no line
  removed from `PROGRESS.md`.
