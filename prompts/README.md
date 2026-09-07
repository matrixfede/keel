# prompts/ — role prompts

The type of agent is, in practice, the system prompt you give it. Here are the
five that cover most cases, already in the pack's style (plain language +
technical term in parentheses, references to the SOPs).

| File | Role | Used by |
|------|------|---------|
| `research.md` | research with sources, "not found" instead of guesses | API use, research tasks |
| `data.md` | data analysis: what it means, not what it contains | API use, analysis tasks |
| `code.md` | code that works in production, surgical changes | API use |
| `arguer.md` | adversary / plan pre-mortem | `scripts/premortem.sh` (SOP-9) |
| `checker.md` + `checker.schema.json` | hostile fresh-context reviewer, 3 checks, KEEP/DROP | `scripts/checker.sh` (SOP-8) |

**Via API**: concatenate `AGENTS.md` + `docs/AGENT_SOP.md` + the role prompt
into the system-instructions field (see the main README, "API use").

**Via an agent CLI** (Codex, Claude Code, Gemini, Cursor, Copilot, OpenCode...):
`AGENTS.md` is already in context (natively or through `adapters/`); to give a
session a role, paste the prompt as the first message.

**Do not change `checker.md` and `arguer.md` in the middle of a job**: they
are the "judge" part of the system, and a judge that changes the rules while
judging is no longer a check. Changes happen between plans, and are versioned.
