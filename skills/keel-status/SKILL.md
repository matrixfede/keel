---
name: keel-status
description: Show the keel state snapshot of the project — plan status and open tasks, graph result, last verify, last PROGRESS.md entry, checker verdicts. Use at session start (resume protocol, SOP-2), when the user asks where the work stands, or before resuming an interrupted plan.
---

# /keel:status — health report (SOP-2)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" health
```

Read it, then apply the resume protocol: `PLAN.md` is the source of truth over anything
remembered from conversation. Report to the user in plain words: plan status, the task
in progress, blockers, and what comes next. Do not start a task from here without the
plan being `APPROVED`.
