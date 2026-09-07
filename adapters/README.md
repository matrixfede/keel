# adapters/ — getting every agent to read AGENTS.md

The pack has a single rules file, `AGENTS.md`, in the standard of the same
name (agents.md). Many agents read it on their own from the project root; for
the others, here are the small "bridge" files to copy into the project.

```bash
bash adapters/install_adapter.sh claude      # CLAUDE.md importing AGENTS.md + write-time hook
bash adapters/install_adapter.sh gemini      # .gemini/settings.json: reads AGENTS.md as a context file
bash adapters/install_adapter.sh aider       # .aider.conf.yml: read AGENTS.md + SOP
bash adapters/install_adapter.sh all         # all three
```

| Agent | Reads `AGENTS.md`? | What it needs | Fresh session (`lib_agent.sh`) |
|---|---|---|---|
| **OpenAI Codex** (CLI/IDE) | yes, native | nothing | `codex exec` — OS sandbox, JSON schema |
| **Claude Code** | no (reads `CLAUDE.md`) | `adapters/claude/CLAUDE.md` (`@AGENTS.md`) | `claude -p --restricted` / `acceptEdits` |
| **Gemini CLI** | no (reads `GEMINI.md`) | `adapters/gemini/.gemini/settings.json` → `context.fileName: ["AGENTS.md","GEMINI.md"]` | `gemini -p --approval-mode plan\|yolo` |
| **Cursor** (IDE and `cursor-agent`) | yes, native | nothing (`.cursor/rules` optional) | `custom` backend |
| **GitHub Copilot** (CLI, coding agent) | yes, native | nothing | `copilot -p --allow-all-tools` |
| **OpenCode** | yes, native | nothing | `opencode run --agent plan` / `--auto` |
| **Aider** | no | `adapters/aider/.aider.conf.yml` (`read:`) | `custom` backend (`aider --message`) |
| **Pi coding agent** | yes (AGENTS.md in cwd) | nothing | `custom` backend |
| **Windsurf / Cline / Roo / Amp / Jules** | mostly yes | if not: copy a `CLAUDE.md`-style file under the name the agent expects | `custom` backend or by hand |

CLIs whose non-interactive invocation was verified (real flags, not inferred):
codex-cli 0.153, claude-code 2.1, gemini-cli 0.58, opencode 1.18, copilot-cli
1.0. For the others use `AGENT_BACKEND=custom` with two commands:

```bash
# example: pi coding agent
export AGENT_BACKEND=custom
export AGENT_CMD_READONLY='cd "$WORKDIR" && pi -p "$(cat "$PROMPT_FILE")" > "$OUT_FILE"'
export AGENT_CMD_WRITE='cd "$WORKDIR" && pi -p "$(cat "$PROMPT_FILE")" > "$OUT_FILE"'
# example: aider (write only; for the read-only checker use --prompt and --record)
export AGENT_CMD_WRITE='cd "$WORKDIR" && aider --yes-always --no-git --message "$(cat "$PROMPT_FILE")" > "$OUT_FILE"'
```

## What does NOT depend on the agent (and therefore works everywhere)

- `PLAN.md`, `PROGRESS.md`, the table, the contracts, the rubrics: markdown.
- `plan_graph.py`: standard python3.
- The pre-commit hook: git. It is the same for every agent and is the only
  place where the rules are enforced in a way that cannot be bypassed,
  whichever model is working.
- `checker.sh`, `premortem.sh`, `fanout.sh` in `--prompt` / `--record` /
  `--reduce` mode: they work with any agent, even via a web chat, by pasting
  the prompt into a new session.

## What depends on the agent

- **The gate at write time** (not only at commit): only Claude Code exposes a
  documented `PreToolUse` hook that can block Write/Edit while the plan is
  DRAFT — it is in `adapters/claude/claude-settings.json` (copied to
  `.claude/settings.json`) + `scripts/hooks/claude_gate.sh`. For the other
  agents the gate remains an instruction plus the pre-commit hook.
- **The sandbox of parallel sessions**: Codex has an operating-system sandbox
  (`workspace-write`); Claude Code, Gemini and Copilot work with auto-approved
  permissions and no sandbox, so fan-out there calls for more caution (or a
  container).
- **Schema-constrained output**: Codex only (`--output-schema`). For the
  others the prompt asks for JSON and `checker.sh` extracts it tolerantly; if
  it cannot, `CHECKER: ERROR` and no verdict — never a guessed KEEP.
