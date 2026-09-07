# PLAN — <task name>

**Plan status: DRAFT — awaiting approval**
<!-- Becomes `APPROVED (<date>)` only when the user gives the go. While it stays DRAFT no code is written. -->

Last update: <ISO-8601> | Session: <n> | Log: `PROGRESS.md`

## Objective

<1-3 sentences: what must be true when the work is finished>

## Active requirements

- R1: <requirement> (source: user, <date>)
- R2: <requirement> (source: user, <date>)

## Plan

| # | Task | Status | Depends on | Verification | Notes |
|---|------|--------|------------|--------------|-------|
| 1 | <description> | ⬜ todo | — | `verify.sh unit` | [P1] |
| 2 | <description> | ⬜ todo | — | `verify.sh unit` | [P1] |
| 3 | <description> | ⬜ todo | 1, 2 | `verify.sh all` | critical |
| 4 | <report/analysis> | ⬜ todo | 3 | rubric (see below) | |
| 5 | ~~<lapsed task>~~ | — | — | — | (removed: R3 withdrawn on <date>) |

- "Depends on" holds only REAL dependencies (X's output feeds Y). Writing
  order is not a dependency — fake edge test, SOP-8.
  Check the graph with `python3 scripts/plan_graph.py` → `GRAPH: OK`.
- `[P1]` = parallel group: tasks runnable in any order or together.
  Every task in a group has an output contract (section "Contracts").
- `critical` = the fresh-context checker (`scripts/checker.sh`) is added to
  the standard verification, and the plan goes through the pre-mortem before
  the go (SOP-9).

Status legend: ⬜ todo · 🔄 in progress · ✅ done · ⛔ blocked

## Contracts

<!-- Mandatory for tasks in parallel groups; recommended for every task that
     produces a file. Exact line shape (plan_graph.py parses it):
     - Task N — OUT: `path/file` — shape: <what it must contain> — check: `<command exiting 0 if the shape holds>`
     "check" is optional but is the only part the fan-out reduction verifies without a model. -->

- Task 1 — OUT: `out/task1.md` — shape: sections "Result" and "Sources", every source dated — check: `grep -q "^## Sources" out/task1.md`
- Task 2 — OUT: `out/task2.tsv` — shape: TSV with header `id<TAB>value`, no blank lines — check: `head -1 out/task2.tsv | grep -q "^id"`

## Rubrics (for tasks with verification `rubric`)

- Task 4 — criteria (all ≥ 8 to close, max 5 passes; pass table in
  `logs/agent/rubric_task4.md`):
  1. <measurable criterion>
  2. <measurable criterion>
  3. <measurable criterion>

## Decisions

- D1: <decision> — rationale: <1 line>
- ASSUMED: <assumption made to fill a gap in the brief — the user sees it and
  can correct it when approving the plan>
- PRE-MORTEM: <failure mode #1 from scripts/premortem.sh> — countermeasure:
  <what changed in the plan, or "accepted: <why>">
- PRE-MORTEM: <failure mode #2> — countermeasure: <...>
- PRE-MORTEM: <failure mode #3> — countermeasure: <...>

## Resume

History does not live here: it lives in `PROGRESS.md` (append-only, one entry
per checkpoint). At session start: `./scripts/health_report.sh`, then read
`PROGRESS.md` in full and resume from the last `NEXT`.
