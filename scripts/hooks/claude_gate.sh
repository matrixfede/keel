#!/usr/bin/env bash
# claude_gate.sh — kept for compatibility with existing .claude/settings.json files.
# The gate now lives in keel_gate.sh (Claude Code and Codex share it).
exec bash "$(dirname "$0")/keel_gate.sh"
