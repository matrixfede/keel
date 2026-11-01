---
name: keel-check
description: Run keel's fresh-context hostile checker on a critical task's artifact and record the hash-sealed verdict (CHECKER: KEEP|DROP). Use before marking a `critical` task ✅, or when the user asks for a keel check / checker review of a file or diff.
argument-hint: "<task#> <artifact> [more artifacts]"
---

# /keel:check — the checker (SOP-8)

Whoever produced an artifact is not a good judge of it. The checker is a NEW context
that sees only the artifact, runs three independent checks (accurate, current,
references) and answers KEEP or DROP; the script — not the model — computes the final
verdict (KEEP needs the model's KEEP and at least 2 checks out of 3) and seals it with
the artifact's SHA-256 in `logs/agent/checker_task<n>.txt`. The pre-commit hook reads
that file; if the artifact changes afterwards the verdict expires.

Plugin root: `${CLAUDE_PLUGIN_ROOT}`. For a diff, first `git diff > logs/agent/task<n>.diff`.

## Preferred: a separate CLI session

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" check <n> <artifact> [...]
```

Uses the first agent CLI found (codex, claude, gemini, opencode, copilot — `AGENT_BACKEND`
to choose) in a temporary folder holding only a copy of the artifact.

## In Claude Code without a CLI session: the `checker` subagent

1. Launch the `checker` subagent (shipped by this plugin) with the artifact path(s) —
   nothing else: no summary of the work, no plan, no conversation.
2. Save its final answer verbatim to `logs/agent/checker_task<n>.raw.txt`.
3. Record it — the script parses it and decides:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" check --from <n> logs/agent/checker_task<n>.raw.txt <artifact> [...]
   ```

## Afterwards

- `CHECKER: KEEP` → note `KEEP (checker <date>)` in the task's Notes, then ✅.
- `CHECKER: DROP` → the task goes back to 🔄; report the rationale in Notes and fix.
- `CHECKER: ERROR` → no verdict was written; never guess a KEEP.
