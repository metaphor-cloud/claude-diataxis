#!/usr/bin/env bats
# Config load and validation.

setup() {
  load 'helpers/test_helper'
  make_sandbox
  make_repo rust proj-rust
}

@test "config that is not JSON fails with exit 2" {
  echo '{broken' >"$WORK/diataxis.config.json"
  run dtx plan
  [ "$status" -eq 2 ]
}

@test "unknown config key fails with the offending JSON pointer" {
  echo '{"version":1,"bogus":true}' >"$WORK/diataxis.config.json"
  run dtx plan
  [ "$status" -eq 2 ]
  [[ "$output" == *"/bogus"* ]]
}

@test "wrong config value type fails with the offending JSON pointer" {
  echo '{"version":1,"budget_usd":"five"}' >"$WORK/diataxis.config.json"
  run dtx plan
  [ "$status" -eq 2 ]
  [[ "$output" == *"/budget_usd"* ]]
}

@test "invalid nested enum fails with the full pointer" {
  echo '{"version":1,"models":{"plan":{"model":"claude-opus-5","effort":"extreme"}}}' \
    >"$WORK/diataxis.config.json"
  run dtx plan
  [ "$status" -eq 2 ]
  [[ "$output" == *"/models/plan/effort"* ]]
}

@test "missing config fails subcommands that need it" {
  run dtx plan
  [ "$status" -eq 2 ]
  [[ "$output" == *"diataxis init"* ]]
}

@test "doctor tolerates a missing config" {
  run dtx doctor
  [ "$status" -eq 0 ]
}

@test "defaults are merged under a minimal config" {
  echo '{"version":1}' >"$WORK/diataxis.config.json"
  run dtx --dry-run plan
  [ "$status" -eq 0 ]
  assert_argv_contains "claude-opus-5"
  assert_argv_contains "high"
}

@test "config model override wins over the default" {
  echo '{"version":1,"models":{"plan":{"model":"claude-sonnet-5","effort":"low"}}}' \
    >"$WORK/diataxis.config.json"
  run dtx --dry-run plan
  [ "$status" -eq 0 ]
  assert_argv_contains "claude-sonnet-5"
  assert_argv_missing "claude-opus-5"
}

@test "init writes a config with the detected adapter and scaffolds docs" {
  rm -f "$WORK/diataxis.config.json"
  run dtx init
  [ "$status" -eq 0 ]
  [ -f "$WORK/diataxis.config.json" ]
  [ "$(jq -r '.workspaces[0].adapter' "$WORK/diataxis.config.json")" = "rust" ]
  [ -d "$WORK/docs/tutorials" ]
  [ -d "$WORK/docs/how-to" ]
  [ -d "$WORK/docs/reference" ]
  [ -d "$WORK/docs/explanation" ]
  [ -d "$WORK/.diataxis" ]
}

@test "init leaves an existing config untouched" {
  echo '{"version":1,"docs_dir":"documentation"}' >"$WORK/diataxis.config.json"
  run dtx init
  [ "$status" -eq 0 ]
  [ "$(jq -r '.docs_dir' "$WORK/diataxis.config.json")" = "documentation" ]
}
