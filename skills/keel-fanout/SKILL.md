---
name: keel-fanout
description: Run a parallel group [Pn] of an APPROVED keel plan — one session per task, then a model-free reduction that checks every output contract (FANOUT: PASS|FAIL). Use when the approved plan has a parallel group and the user asked for, or approved, parallel execution.
argument-hint: "<P1> [--prompt|--reduce]"
---

# /keel:fanout — the diamond (SOP-8)

Preconditions, all checked by the script: `PLAN.md` is `APPROVED`, `GRAPH: OK`, every
task in the group has an output contract (file, shape, `check:`), at most `FANOUT_MAX`
tasks (default 4).

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" fanout P1            # workers in parallel + reduction
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" fanout P1 --prompt   # only the prompts, one manual session per task
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" fanout P1 --reduce   # reduction only, after sessions run by hand
```

In Claude Code without a CLI: launch one subagent per prompt in `logs/agent/fanout_P1_task<n>.prompt.md`
(all at once), then run `--reduce`. Workers never touch `PLAN.md` or `PROGRESS.md`.

After `FANOUT: PASS` the main session runs each task's verification, marks ✅ and
appends the `PROGRESS.md` entry. After `FANOUT: FAIL` convergence does not start.
