#!/usr/bin/env bash
# lib_agent.sh — the only place in the pack where an agent is invoked in
# non-interactive mode. Used by checker.sh, premortem.sh and fanout.sh.
# Include with: source "scripts/lib_agent.sh"
#
# The pack is agent-agnostic: the backend is chosen here, the scripts always
# call the same three functions (agent_available, agent_run, agent_missing_hint).
#
# Environment variables (all optional):
#   AGENT_BACKEND   codex | claude | gemini | opencode | copilot | custom | auto (default: auto)
#                   auto = the first available in this order: codex, claude, gemini, opencode, copilot
#   AGENT_MODEL     model to pass to the backend (default: the one configured in the agent)
#   AGENT_FLAGS     extra flags appended to the backend command (default: empty)
#   AGENT_BIN       binary name/path, if different from the backend default
#   AGENT_CMD_READONLY / AGENT_CMD_WRITE   (custom backend only) bash command receiving the
#                   variables PROMPT_FILE, WORKDIR, OUT_FILE and MODEL — e.g. for pi, aider, cursor-agent
#
# Flags verified on: codex-cli 0.153, claude-code 2.1, gemini-cli 0.58, opencode 1.18, copilot-cli 1.0.
# If your version differs, fix it HERE, in one place.
#
# Contract of agent_run <workdir> <mode> <prompt_file> <out_file> [schema_file]:
#   workdir   folder the agent sees as its root. For checker and pre-mortem it is a
#             temporary folder holding only a copy of the artifact: THAT is what makes
#             the context fresh, whatever the agent.
#   mode      readonly | write
#   out_file  where the agent's final message lands (text)
#   schema    optional JSON Schema: used where the backend supports it (codex); elsewhere
#             the prompt asks for JSON and the reader extracts it tolerantly.
#   Backend diagnostics in <out_file>.events.log.

_agent_pick() {
  local b="${AGENT_BACKEND:-auto}"
  if [[ "$b" != "auto" ]]; then echo "$b"; return; fi
  for c in codex claude gemini opencode copilot; do
    command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }
  done
  echo "none"
}
AGENT="$(_agent_pick)"

_agent_default_bin() {
  case "$AGENT" in
    codex) echo codex ;; claude) echo claude ;; gemini) echo gemini ;;
    opencode) echo opencode ;; copilot) echo copilot ;; *) echo "" ;;
  esac
}
AGENT_BIN="${AGENT_BIN:-$(_agent_default_bin)}"

agent_name() { echo "$AGENT"; }

agent_available() {
  case "$AGENT" in
    none) return 1 ;;
    custom) [[ -n "${AGENT_CMD_READONLY:-}" && -n "${AGENT_CMD_WRITE:-}" ]] ;;
    *) command -v "$AGENT_BIN" >/dev/null 2>&1 ;;
  esac
}

# portable sha256 (macOS: shasum, Linux: sha256sum)
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else echo "no-sha256-tool"; fi
}

now_iso() { date +%Y-%m-%dT%H:%M:%S%z; }

agent_run() {
  local workdir="$1" mode="$2" prompt_file="$3" out_file="$4" schema="${5:-}"
  # Absolute paths: some backends `cd` into the working folder.
  [[ "$prompt_file" = /* ]] || prompt_file="$PWD/$prompt_file"
  [[ "$out_file"    = /* ]] || out_file="$PWD/$out_file"
  [[ -n "$schema" && "$schema" != /* ]] && schema="$PWD/$schema"
  local log="${out_file}.events.log" model="${AGENT_MODEL:-}"
  # shellcheck disable=SC2206
  local extra=(${AGENT_FLAGS:-})

  case "$AGENT" in

    codex)
      # Operating-system sandbox: read-only, or write limited to the workspace.
      local sb="read-only"; [[ "$mode" == "write" ]] && sb="workspace-write"
      local a=(exec --skip-git-repo-check --ephemeral --color never -C "$workdir" -s "$sb" -o "$out_file")
      [[ -n "$model" ]] && a+=(-m "$model")
      [[ -n "$schema" ]] && a+=(--output-schema "$schema")
      "$AGENT_BIN" "${a[@]}" ${extra[@]+"${extra[@]}"} - < "$prompt_file" > "$log" 2>&1 ;;

    claude)
      # --restricted: no Bash, no user/project CLAUDE.md → genuinely fresh context.
      # In write mode: edits auto-approved, shell limited to the pack's scripts.
      local a=(-p --output-format text --no-session-persistence)
      if [[ "$mode" == "readonly" ]]; then a+=(--restricted --tools "Read,Glob,Grep")
      else a+=(--permission-mode acceptEdits --allowedTools "Bash(./scripts/*) Bash(bash scripts/*) Bash(python3 scripts/*)"); fi
      [[ -n "$model" ]] && a+=(--model "$model")
      (cd "$workdir" && "$AGENT_BIN" "${a[@]}" ${extra[@]+"${extra[@]}"} < "$prompt_file" > "$out_file" 2> "$log") ;;

    gemini)
      # --approval-mode plan = read-only; yolo = everything auto-approved. The prompt comes from stdin.
      local am="plan"; [[ "$mode" == "write" ]] && am="yolo"
      local a=(-p "Follow the instructions received on stdin." --approval-mode "$am" -o text)
      [[ -n "$model" ]] && a+=(-m "$model")
      (cd "$workdir" && "$AGENT_BIN" "${a[@]}" ${extra[@]+"${extra[@]}"} < "$prompt_file" > "$out_file" 2> "$log") ;;

    opencode)
      # "plan" agent = no edits; --auto = permissions auto-approved.
      local a=(run --dir "$workdir")
      if [[ "$mode" == "readonly" ]]; then a+=(--agent plan); else a+=(--auto); fi
      [[ -n "$model" ]] && a+=(-m "$model")
      "$AGENT_BIN" "${a[@]}" ${extra[@]+"${extra[@]}"} "$(cat "$prompt_file")" < /dev/null > "$out_file" 2> "$log" ;;

    copilot)
      # Non-interactive mode requires --allow-all-tools; in read-only mode shell and write are denied.
      local a=(-p "$(cat "$prompt_file")" --allow-all-tools --no-ask-user)
      [[ "$mode" == "readonly" ]] && a+=(--deny-tool shell --deny-tool write)
      [[ -n "$model" ]] && a+=(--model "$model")
      (cd "$workdir" && "$AGENT_BIN" "${a[@]}" ${extra[@]+"${extra[@]}"} < /dev/null > "$out_file" 2> "$log") ;;

    custom)
      local cmd="$AGENT_CMD_READONLY"; [[ "$mode" == "write" ]] && cmd="$AGENT_CMD_WRITE"
      PROMPT_FILE="$prompt_file" WORKDIR="$workdir" OUT_FILE="$out_file" MODEL="$model" \
        bash -c "$cmd" > "$log" 2>&1 ;;

    *)
      echo "no agent backend available (AGENT_BACKEND=$AGENT)" > "$log"; return 127 ;;
  esac
}

# Standard message when no agent is available: the prompt stays on file, used by hand.
agent_missing_hint() {
  local prompt_file="$1"
  cat <<MSG
  No agent CLI found (codex, claude, gemini, opencode, copilot; AGENT_BACKEND=${AGENT_BACKEND:-auto}).
  The fresh-context session must be opened by hand, with any agent:
  1. Open a NEW session (empty chat, not the working one).
  2. Paste the content of: $prompt_file
  3. Record the outcome with the command shown below.
MSG
}
