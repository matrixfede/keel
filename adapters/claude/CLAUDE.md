# CLAUDE.md

The operating rules of this repository are in `AGENTS.md` (agents.md standard),
shared with the other coding agents. They are imported here in full:

@AGENTS.md

Note for Claude Code: the planning gate is also enforced at write time by
`.claude/settings.json` (`PreToolUse` hook → `scripts/hooks/claude_gate.sh`):
with `PLAN.md` missing or in `DRAFT`, every Write/Edit on files other than
`PLAN.md` is refused with the reason. It is not an error to work around: it is
the gate doing its job.
