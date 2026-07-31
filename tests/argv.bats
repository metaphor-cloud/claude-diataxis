#!/usr/bin/env bats
# Model routing and invocation shape, asserted against the --dry-run argv.
# No live calls are made anywhere in this file.

setup() {
  load 'helpers/test_helper'
  make_sandbox
  make_repo rust proj-rust
  echo '{"version":1}' >"$WORK/diataxis.config.json"
  write_plan '{"pages":[
    {"slug":"tutorials/get-started","mode":"tutorial","title":"Get started","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"beginner"},
    {"slug":"how-to/rotate-a-signing-key","mode":"howto","title":"Rotate a signing key","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"developer"},
    {"slug":"explanation/architecture","mode":"explanation","title":"Architecture","rationale":"r","sources":["src/lib.rs"],"priority":2,"audience":"developer"},
    {"slug":"reference/proj-rust","mode":"reference","title":"proj-rust reference","rationale":"derived","sources":["src/lib.rs"],"priority":2,"audience":"developer"}
  ]}'
}

@test "howto routes to sonnet at medium effort without fallback" {
  run dtx --dry-run generate --mode howto
  [ "$status" -eq 0 ]
  assert_argv_contains "claude-sonnet-5"
  assert_argv_contains "--effort"
  assert_argv_contains "medium"
  assert_argv_missing "--fallback-model"
}

@test "tutorial routes to opus at high effort with sonnet fallback" {
  run dtx --dry-run generate --mode tutorial
  [ "$status" -eq 0 ]
  assert_argv_contains "claude-opus-5"
  assert_argv_contains "high"
  assert_argv_contains "--fallback-model"
  assert_argv_contains "claude-sonnet-5"
}

@test "explanation routes to opus with fallback" {
  run dtx --dry-run generate --mode explanation
  [ "$status" -eq 0 ]
  assert_argv_contains "claude-opus-5"
  assert_argv_contains "--fallback-model"
}

@test "reference routes to sonnet" {
  run dtx --dry-run generate --mode reference
  [ "$status" -eq 0 ]
  assert_argv_contains "claude-sonnet-5"
  assert_argv_contains '"symbols"'
}

@test "plan routes to opus at high effort" {
  run dtx --dry-run plan
  [ "$status" -eq 0 ]
  assert_argv_contains "claude-opus-5"
  assert_argv_contains "high"
}

@test "every call is read-only, structured and turn-capped" {
  run dtx --dry-run generate --mode howto
  [ "$status" -eq 0 ]
  assert_argv_contains "Read,Grep,Glob"
  assert_argv_contains "--permission-mode"
  assert_argv_contains "dontAsk"
  assert_argv_contains "--strict-mcp-config"
  assert_argv_contains "--output-format"
  assert_argv_contains "--json-schema"
  assert_argv_contains "--max-turns"
  assert_argv_contains "24"
  assert_argv_contains "--append-system-prompt-file"
}

@test "budget flag becomes a per-call --max-budget-usd belt" {
  run dtx --dry-run --budget-usd 2 generate --mode howto
  [ "$status" -eq 0 ]
  assert_argv_contains "--max-budget-usd"
  assert_argv_contains "2.0000"
}

@test "env credential auth passes --bare" {
  STUB_OAUTH=test-token run dtx --dry-run generate --mode howto
  [ "$status" -eq 0 ]
  assert_argv_contains "--bare"
}

@test "subscription auth omits --bare and warns" {
  run dtx --dry-run generate --mode howto
  [ "$status" -eq 0 ]
  # The warning prose mentions --bare, so assert on exact argv lines.
  ! printf '%s\n' "$output" | grep -qx -- '--bare'
  [[ "$output" == *"not bare-capable"* ]]
}

@test "config bare=true with subscription auth fails with exit 16" {
  echo '{"version":1,"bare":true}' >"$WORK/diataxis.config.json"
  run dtx --dry-run generate --mode howto
  [ "$status" -eq 16 ]
}

@test "unknown mode is rejected" {
  run dtx --dry-run generate --mode prose
  [ "$status" -eq 1 ]
}

@test "concurrency is capped at 4" {
  run dtx --dry-run --concurrency 9 generate --mode howto
  [ "$status" -eq 0 ]
}

@test "per-mode max_turns override reaches the argv" {
  echo '{"version":1,"models":{"howto":{"model":"claude-sonnet-5","effort":"medium","max_turns":12}}}' \
    >"$WORK/diataxis.config.json"
  run dtx --dry-run generate --mode howto
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -A1 -x -- '--max-turns' | grep -qx '12'
}

@test "reference_bulk defaults to fewer turns" {
  run sh -c "DIATAXIS_ROOT='$REPO_ROOT'; . '$REPO_ROOT/lib/preamble.sh'; . '$REPO_ROOT/lib/config.sh'; \
    DIATAXIS_CONFIG='' DIATAXIS_WORKSPACE='$WORK' DIATAXIS_BUDGET_USD='' config_load 1; \
    cfg_max_turns reference_bulk; cfg_max_turns howto"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "12" ]
  [ "${lines[1]}" = "24" ]
}

@test "generate --priority limits pages to that priority and better" {
  write_plan '{"pages":[
    {"slug":"how-to/first-thing","mode":"howto","title":"Do the first thing","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"developer"},
    {"slug":"how-to/later-thing","mode":"howto","title":"Do the later thing","rationale":"r","sources":["src/lib.rs"],"priority":3,"audience":"developer"}
  ]}'
  run dtx --dry-run generate --priority 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1/1] how-to/first-thing"* ]]
  [[ "$output" != *"how-to/later-thing"* ]]
  run dtx --dry-run generate
  [ "$status" -eq 0 ]
  [[ "$output" == *"how-to/later-thing"* ]]
}

@test "invalid --priority is rejected" {
  run dtx --dry-run generate --priority 9
  [ "$status" -eq 1 ]
}
