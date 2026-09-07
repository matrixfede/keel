# Contributing to keel

Thanks for considering it. keel is small on purpose; the bar for adding things
is "does this make an agent more reliable on a real repository, for every agent,
without adding a dependency".

## Ground rules

- **Markdown, bash 3.2, python3 stdlib, git.** No new runtime dependencies. If
  a change needs bash 4+ (`mapfile`, associative arrays, `${var,,}`), find
  another way: stock macOS ships 3.2 and CI runs the suite there.
- **Agent-agnostic.** Anything that invokes an agent goes through
  `scripts/lib_agent.sh`. Anything about how an agent reads `AGENTS.md` goes
  in `adapters/`. Rules and SOPs never name a model.
- **Deterministic where it counts.** If a rule can be enforced by the hook or
  a script, enforce it there rather than only in prose. If it cannot, say so
  in the docs instead of pretending.
- **The judge does not change mid-job.** `prompts/checker.md`,
  `prompts/arguer.md` and the hook are the "judge" part of the system. Changes
  to them need a rationale in the PR and a test.
- **Surgical diffs.** The pack asks agents for this; we hold ourselves to it too.

## Running the tests

```bash
bash tests/run_tests.sh          # 61 checks, ~20 s, no agent CLI or network needed
shellcheck -x -S warning scripts/*.sh scripts/hooks/*.sh adapters/*.sh tests/*.sh
```

If you have an old bash around (or build 3.2 from source), run the suite with
it too: `/path/to/bash-3.2 tests/run_tests.sh`.

## Adding an agent backend

1. Add a `case` branch in `scripts/lib_agent.sh::agent_run` with the real
   flags of that CLI for a read-only run and a write run. Verify them against
   the installed CLI's `--help`, and note the version in the file header.
2. Add the agent to the auto-detect list only if it is a first-class CLI with
   a non-interactive mode.
3. Add the argv assertion in `tests/run_tests.sh` (a fake binary with that
   name is generated automatically; add the name to the `for c in ...` loop).
4. Add a row to the matrix in `adapters/README.md`, including what the agent
   cannot provide (sandbox, schema output, write-time hook).

## Adding an SOP or changing the plan format

The plan markers (`Plan status:`, `Depends on`, `## Contracts`, `shape:`,
`critical`, `[Pn]`, the emoji statuses) are parsed by `plan_graph.py`,
`fanout.sh`, `health_report.sh`, the pre-commit hook and `claude_gate.sh`.
Change them in all five, update `PLAN.template.md`, and add a test. Bump the
major version: existing `PLAN.md` files break.

## Commit messages and PRs

Conventional-commit style (`feat:`, `fix:`, `docs:`, `test:`, `chore:`). A PR
description says what changed, why, and how it was verified — the same
what / why / effect the pack asks of agents. Update `CHANGELOG.md` under
"Unreleased".
