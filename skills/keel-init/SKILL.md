---
name: keel-init
description: Set up the current project for keel — .keel/ marker, logs/agent/, .gitignore entry and the pre-commit hook with its four deterministic checks. Use when the user asks to enable, install or initialise keel (or "the plan gate") in a project, or when the keel session banner says the project is not set up.
disable-model-invocation: false
argument-hint: "[project_dir]"
---

# /keel:init — arm keel in this project

Run, from the project root (the plugin root is `${CLAUDE_PLUGIN_ROOT}`, two levels
above this file):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/bin/keel" init
```

It is idempotent. It creates in the project:

- `.keel/config` — marker: switches on the write-time gate and the session rules here
- `logs/agent/` and the `logs/` line in `.gitignore`
- `.git/hooks/pre-commit` with its own copy of `plan_graph.py` (survives without the plugin)

It does **not** create `PLAN.md`: that is written when a complex task arrives, from
`PLAN.template.md` at the plugin root. Last line on success: `KEEL: READY`.

Then tell the user, in plain words: what was created, that from now on complex tasks
start with a plan they must approve, and that `git commit --no-verify` bypasses the
hook when they know what they are doing. Commit `.keel/` and `.gitignore` if they want
collaborators' plugins to arm too.
