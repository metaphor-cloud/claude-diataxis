# shellcheck shell=sh
# claude.sh: the only place that shells out to `claude` for generation.
# Every call: pinned model, read-only tools, structured JSON out, budget caps.
# The harness owns the filesystem; Claude never writes files.

# claude_files_mode MODE: which prompt/schema files a mode uses.
# reference_bulk shares the reference contract.
claude_files_mode() {
  case "$1" in
    reference_bulk) printf 'reference\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# claude_system_prompt_file MODE: materialise the system prompt with the
# configured voice conventions appended, once per run per mode.
claude_system_prompt_file() {
  _fm=$(claude_files_mode "$1")
  _merged="$DIATAXIS_TMPDIR/system-$_fm.md"
  if [ ! -f "$_merged" ]; then
    {
      cat "$DIATAXIS_ROOT/prompts/system/$_fm.md"
      config_style_instructions
    } >"$_merged"
  fi
  printf '%s\n' "$_merged"
}

# claude_run MODE MAX_TURNS OUT_FILE TASK_PROMPT
# Builds the full argv and either executes it (writing the CLI's JSON result
# to OUT_FILE) or, under --dry-run, prints the exact argv to stdout, one
# argument per line, first line "claude", terminated by a blank line.
#
# POSIX sh has no local variables and claude_run is called inline from other
# functions mid-flight, so every variable here is _cr_-prefixed to avoid
# clobbering the caller's state (a bare _mode here once overwrote the
# caller's _mode when reference routed to reference_bulk).
claude_run() {
  _cr_mode=$1
  _cr_max_turns=$2
  _cr_out=$3
  _cr_task_prompt=$4
  _cr_fm=$(claude_files_mode "$_cr_mode")

  _cr_model=$(cfg_model "$_cr_mode")
  if [ -z "$_cr_model" ]; then
    die "$EX_CONFIG" "no model configured for mode '$_cr_mode'"
  fi
  _cr_effort=$(cfg_effort "$_cr_mode")
  _cr_schema=$(jq -c . "$DIATAXIS_ROOT/schemas/$_cr_fm.json")
  _cr_system=$(claude_system_prompt_file "$_cr_mode")

  # --strict-mcp-config with no --mcp-config loads zero MCP servers. The
  # harness only allows Read/Grep/Glob, so ambient MCP servers (including
  # half-configured or policy-blocked ones) are pure noise and can fail the
  # call. This matters most without --bare, where user config is in play.
  set -- -p \
    --model "$_cr_model" \
    --append-system-prompt-file "$_cr_system" \
    --allowedTools "Read,Grep,Glob" \
    --permission-mode dontAsk \
    --strict-mcp-config \
    --output-format json \
    --json-schema "$_cr_schema" \
    --max-turns "$_cr_max_turns"
  if [ -n "$_cr_effort" ]; then
    set -- "$@" --effort "$_cr_effort"
  fi
  # Overload resilience on the expensive judgment calls. Auth, billing,
  # rate-limit and request-size errors do not trigger fallback, so non-zero
  # exits are still handled below.
  case "$_cr_model" in
    *opus*) set -- "$@" --fallback-model "$(cfg -r '.models.fallback')" ;;
  esac
  # Second belt on top of the harness-side budget accounting.
  _cr_rem=$(budget_remaining)
  if [ -n "$_cr_rem" ]; then
    set -- "$@" --max-budget-usd "$_cr_rem"
  fi
  _cr_settings=$(cfg_settings_file)
  if [ -n "$_cr_settings" ]; then
    set -- "$@" --settings "$DIATAXIS_WORKSPACE/$_cr_settings"
  fi
  if [ "${DIATAXIS_USE_BARE:-0}" -eq 1 ]; then
    set -- --bare "$@"
  fi
  set -- "$@" "$_cr_task_prompt"

  if [ "${DIATAXIS_DRY_RUN:-0}" -eq 1 ]; then
    printf 'claude\n'
    printf '%s\n' "$@"
    printf '\n'
    return 0
  fi

  budget_require "$_cr_mode call"
  # Progress by default: model calls take seconds to minutes and a silent
  # harness looks hung. One line going in, one line coming back.
  log "  -> $_cr_mode: calling $_cr_model${_cr_effort:+ (effort $_cr_effort)}, up to $_cr_max_turns turns..."
  _cr_start=$(date +%s)
  _cr_errf="$DIATAXIS_TMPDIR/claude-stderr.$$"
  _cr_rc=0
  # Run from the workspace root so Read/Grep/Glob see the repository.
  (cd "$DIATAXIS_WORKSPACE" && claude "$@" </dev/null) >"$_cr_out" 2>"$_cr_errf" || _cr_rc=$?
  if [ "$_cr_rc" -ne 0 ]; then
    _cr_errtxt=$(cat "$_cr_errf" 2>/dev/null || true)
    _cr_restxt=$(jq -r '.result // empty' "$_cr_out" 2>/dev/null || true)
    case "$_cr_errtxt $_cr_restxt" in
      *"not_found_error"*|*"model"*"not available"*|*"model"*"not permitted"*|*"Unknown model"*|*"invalid model"*)
        die "$EX_MODEL_UNAVAILABLE" "model '$_cr_model' rejected by the API: $_cr_errtxt$_cr_restxt"
        ;;
      *"budget"*|*"Budget"*)
        die "$EX_BUDGET" "per-call budget cap hit during $_cr_mode call: $_cr_errtxt$_cr_restxt"
        ;;
    esac
    _cr_hint=''
    if [ -z "$_cr_errtxt$_cr_restxt" ] && [ -n "$_cr_rem" ]; then
      _cr_hint=" | no error output: the per-call --max-budget-usd cap (\$$_cr_rem remaining of \$${DIATAXIS_BUDGET_USD}) likely stopped this call mid-run. Raise --budget-usd or budget_usd in config, or generate fewer pages per run"
    fi
    die "$EX_GENERIC" "claude exited $_cr_rc for mode $_cr_mode: ${_cr_errtxt:-(no stderr)}${_cr_restxt:+ | result: $_cr_restxt}$_cr_hint"
  fi
  if ! jq -e . "$_cr_out" >/dev/null 2>&1; then
    die "$EX_GENERIC" "claude returned non-JSON output for mode $_cr_mode"
  fi
  if [ "$(jq -r '.is_error // false' "$_cr_out")" = "true" ]; then
    die "$EX_GENERIC" "claude reported an error for mode $_cr_mode: $(jq -r '.result // "unknown"' "$_cr_out")"
  fi
  budget_add "$(jq -r '.total_cost_usd // 0' "$_cr_out")"
  log "  <- $_cr_mode: done in $(( $(date +%s) - _cr_start ))s (\$$(claude_cost "$_cr_out"))"
  return 0
}

# claude_structured OUT_FILE: print the validated structured result.
# Read from .structured_output, not .result. Empty output means the call
# failed to produce schema-conforming output, which is a failed generation.
claude_structured() {
  jq -ce '.structured_output // empty' "$1" 2>/dev/null
}

# claude_cost OUT_FILE: the call's cost in USD.
claude_cost() {
  jq -r '.total_cost_usd // 0' "$1" 2>/dev/null || printf '0\n'
}

# claude_model_used OUT_FILE: the concrete model that actually answered,
# resolved from the modelUsage breakdown (the alias the config asked for may
# have been resolved, or fallback may have engaged).
claude_model_used() {
  jq -r '
    .modelUsage // {}
    | to_entries
    | if length == 0 then ""
      else (max_by(.value.outputTokens // .value.output_tokens // 0) | .key)
      end' "$1" 2>/dev/null || true
}
