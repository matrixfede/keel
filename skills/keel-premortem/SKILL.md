---
name: keel-premortem
description: Run keel's fresh-context pre-mortem on PLAN.md before asking for the go — a separate session assumes the plan failed and explains why; the top three failure modes enter the plan as PRE-MORTEM lines with a countermeasure each. Use in the plan turn when a task is critical or hard to undo (migrations, deletions, pipelines in use), or when the user asks for a pre-mortem.
---

# /keel:premortem — attack the plan before the go (SOP-9)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" premortem            # with an agent CLI; result in logs/agent/premortem_<stamp>.md
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" premortem --prompt   # writes only the prompt, for a session opened by hand
```

Without a CLI, in Claude Code, launch the `arguer` subagent shipped by this plugin
with the content of `PLAN.md` only — not the conversation it was born in, otherwise it
just nods — and paste its answer into `logs/agent/premortem_<date>.md`.

Then, in `PLAN.md` → Decisions, add the top three failure modes, one per line:

```
- PRE-MORTEM: <failure mode> → <countermeasure adopted in the plan>   or   accepted: <why>
```

Show them to the user together with the table. Last line: `PREMORTEM: DONE`.
