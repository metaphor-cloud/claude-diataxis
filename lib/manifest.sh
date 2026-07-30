# shellcheck shell=sh
# manifest.sh: hashing, staleness, cost accounting, human-edit protection.
# The manifest (.diataxis/manifest.json) is committed and is what makes runs
# deterministic: same inputs, same manifest, no work done.

manifest_path() { printf '%s\n' "$DIATAXIS_WORKSPACE/.diataxis/manifest.json"; }

manifest_read() {
  if [ -f "$(manifest_path)" ]; then
    cat "$(manifest_path)"
  else
    printf '{"version":1,"pages":[]}\n'
  fi
}

# manifest_write JSON: atomic replace.
manifest_write() {
  mkdir -p "$DIATAXIS_WORKSPACE/.diataxis"
  _tmp="$DIATAXIS_WORKSPACE/.diataxis/.manifest.tmp.$$"
  printf '%s' "$1" | jq . >"$_tmp"
  mv "$_tmp" "$(manifest_path)"
}

# manifest_get_page SLUG: print the page entry JSON, or nothing.
manifest_get_page() {
  manifest_read | jq -c --arg slug "$1" '.pages[] | select(.slug == $slug)' 2>/dev/null || true
}

# manifest_upsert_page ENTRY_JSON: replace or append the entry for its slug.
manifest_upsert_page() {
  _m=$(manifest_read)
  _new=$(printf '%s' "$_m" | jq -c --argjson entry "$1" '
    .pages = ([.pages[] | select(.slug != $entry.slug)] + [$entry]
              | sort_by(.slug))')
  manifest_write "$_new"
}

# manifest_delete_page SLUG
manifest_delete_page() {
  _m=$(manifest_read)
  _new=$(printf '%s' "$_m" | jq -c --arg slug "$1" '
    .pages = [.pages[] | select(.slug != $slug)]')
  manifest_write "$_new"
}

# manifest_set_meta KEY JSON_VALUE: set a top-level key (auth_method,
# workspaces inventory strategies, ...).
manifest_set_meta() {
  _m=$(manifest_read)
  _new=$(printf '%s' "$_m" | jq -c --arg k "$1" --argjson v "$2" '.[$k] = $v')
  manifest_write "$_new"
}

# --- input hashing ------------------------------------------------------------

# compute_inputs_hash MODE SOURCES PLAN_ENTRY_JSON
#   MODE: tutorial|howto|reference|explanation
#   SOURCES: newline-separated workspace-relative source paths
#   PLAN_ENTRY_JSON: the page's entry in .diataxis/plan.json
# Covers, in a stable order: the content of every listed source file, the
# system prompt file, the task template, the schema, the config's model block,
# and the plan entry. Any change makes the page stale.
compute_inputs_hash() {
  _mode=$1
  _sources=$2
  _plan_entry=$3
  {
    printf '%s\n' "$_sources" | grep -v '^$' | LC_ALL=C sort | while IFS= read -r _p; do
      if [ -f "$DIATAXIS_WORKSPACE/$_p" ]; then
        printf 'src:%s:%s\n' "$_p" "$(sha256_file "$DIATAXIS_WORKSPACE/$_p")"
      else
        printf 'src:%s:missing\n' "$_p"
      fi
    done
    printf 'system:%s\n' "$(sha256_file "$DIATAXIS_ROOT/prompts/system/$_mode.md")"
    printf 'task:%s\n' "$(sha256_file "$DIATAXIS_ROOT/prompts/task/$_mode.tmpl")"
    printf 'schema:%s\n' "$(sha256_file "$DIATAXIS_ROOT/schemas/$_mode.json")"
    printf 'models:%s\n' "$(sha256_string "$(cfg '.models')")"
    printf 'plan:%s\n' "$(sha256_string "$_plan_entry")"
  } | sha256_stream | sed 's/^/sha256:/'
}

# page_is_stale SLUG CURRENT_INPUTS_HASH: exit 0 when regeneration is needed.
page_is_stale() {
  _entry=$(manifest_get_page "$1")
  if [ -z "$_entry" ]; then
    return 0
  fi
  _recorded=$(printf '%s' "$_entry" | jq -r '.inputs_hash // empty')
  [ "$_recorded" != "$2" ]
}

# --- human-edit protection ------------------------------------------------------

# page_disk_status SLUG ABS_PATH: prints one of
#   absent   file does not exist on disk
#   clean    file matches the recorded content_hash
#   edited   file differs from what was generated (a human touched it)
#   unknown  file exists but no content_hash recorded
page_disk_status() {
  _entry=$(manifest_get_page "$1")
  if [ ! -f "$2" ]; then
    printf 'absent\n'
    return 0
  fi
  _recorded=$(printf '%s' "$_entry" | jq -r '.content_hash // empty' 2>/dev/null || true)
  if [ -z "$_recorded" ]; then
    printf 'unknown\n'
    return 0
  fi
  if [ "sha256:$(sha256_file "$2")" = "$_recorded" ]; then
    printf 'clean\n'
  else
    printf 'edited\n'
  fi
}

# page_is_frozen SLUG ABS_PATH: exit 0 when the page must never be regenerated,
# from either the manifest entry or a `frozen: true` frontmatter key.
page_is_frozen() {
  _entry=$(manifest_get_page "$1")
  if [ -n "$_entry" ] && [ "$(printf '%s' "$_entry" | jq -r '.frozen // false')" = "true" ]; then
    return 0
  fi
  if [ -f "$2" ] && sed -n '2,/^---$/p' "$2" | grep -q '^frozen: true$'; then
    return 0
  fi
  return 1
}

# --- cost accounting ------------------------------------------------------------

DIATAXIS_RUN_SPENT=0

# budget_remaining: print remaining USD for this run, or nothing if unbudgeted.
budget_remaining() {
  if [ -z "${DIATAXIS_BUDGET_USD:-}" ] || [ "${DIATAXIS_BUDGET_USD:-}" = "null" ]; then
    return 0
  fi
  awk_float_sub "$DIATAXIS_BUDGET_USD" "$DIATAXIS_RUN_SPENT"
}

# budget_require: die EX_BUDGET when the budget is already spent, naming what
# remains undone rather than half-generating.
budget_require() {
  _pending=${1:-remaining work}
  _rem=$(budget_remaining)
  if [ -n "$_rem" ] && ! awk_float_lt 0 "$_rem"; then
    die "$EX_BUDGET" \
      "budget of \$$DIATAXIS_BUDGET_USD exhausted (spent \$$DIATAXIS_RUN_SPENT this run); refusing to start: $_pending. Raise --budget-usd or budget_usd in config"
  fi
}

# budget_add COST: accumulate run spend.
budget_add() {
  DIATAXIS_RUN_SPENT=$(awk_float_add "$DIATAXIS_RUN_SPENT" "$1")
}

# manifest_total_cost: lifetime spend recorded in the manifest.
manifest_total_cost() {
  manifest_read | jq '[.pages[].cost_usd // 0] | add // 0'
}
