#!/usr/bin/env bats
# The documented exit code contract: budget, model availability, check modes.

setup() {
  load 'helpers/test_helper'
  make_sandbox
  make_repo rust proj-rust
  echo '{"version":1}' >"$WORK/diataxis.config.json"
  RESPONSES="$TESTS_DIR/fixtures/rust/responses"
}

ref_plan() {
  write_plan '{"pages":[{"slug":"reference/proj-rust","mode":"reference","title":"proj-rust reference","rationale":"derived","sources":["src/lib.rs"],"priority":2,"audience":"developer"}]}'
}

@test "exit 20 when the budget is already exhausted" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  run dtx --budget-usd 0 generate --mode reference
  [ "$status" -eq 20 ]
  [[ "$output" == *"budget"* ]]
}

@test "exit 21 when the model is rejected by the API" {
  ref_plan
  export CLAUDE_STUB_EXIT=1
  export CLAUDE_STUB_STDERR="API error: Unknown model claude-sonnet-5"
  run dtx generate --mode reference
  [ "$status" -eq 21 ]
}

@test "check requires bare-capable auth (exit 16 on subscription)" {
  ref_plan
  run dtx check
  [ "$status" -eq 16 ]
}

@test "check exit 31 when a planned page was never generated" {
  ref_plan
  STUB_OAUTH=tok run dtx check
  [ "$status" -eq 31 ]
}

@test "check exit 31 when sources changed after generation" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  echo '// touched' >>"$WORK/src/lib.rs"
  STUB_OAUTH=tok run dtx check
  [ "$status" -eq 31 ]
}

@test "check exit 0 when everything is generated and fresh" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  STUB_OAUTH=tok run dtx check
  [ "$status" -eq 0 ]
}

@test "check exit 30 when audit findings hit the configured severities" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  mkdir -p "$WORK/docs"
  echo '# stray notes' >"$WORK/docs/notes.md"
  echo '{"version":1,"audit":{"fail_on":["error","warning"]}}' >"$WORK/diataxis.config.json"
  STUB_OAUTH=tok run dtx check
  [ "$status" -eq 30 ]
  [[ "$output" == *"orphan"* ]]
}

@test "orphan warnings do not fail check under the default fail_on" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  mkdir -p "$WORK/docs"
  echo '# stray notes' >"$WORK/docs/notes.md"
  STUB_OAUTH=tok run dtx check
  [ "$status" -eq 0 ]
}

@test "check exit 32 on an unverified tutorial" {
  write_plan '{"pages":[{"slug":"tutorials/get-started","mode":"tutorial","title":"Get started","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"beginner"}]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-fail.json"
  dtx generate --mode tutorial
  STUB_OAUTH=tok run dtx check
  [ "$status" -eq 32 ]
}

@test "verify.required false downgrades unverified tutorials to pass" {
  write_plan '{"pages":[{"slug":"tutorials/get-started","mode":"tutorial","title":"Get started","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"beginner"}]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-fail.json"
  dtx generate --mode tutorial
  echo '{"version":1,"verify":{"required":false}}' >"$WORK/diataxis.config.json"
  STUB_OAUTH=tok run dtx check
  [ "$status" -eq 0 ]
}

@test "audit reports findings but exits 0" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  export CLAUDE_STUB_RESPONSE="$RESPONSES/audit.json"
  run dtx audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"unverified_code"* ]]
}

@test "generic argument errors exit 1" {
  run dtx frobnicate
  [ "$status" -eq 1 ]
  run dtx --mode
  [ "$status" -eq 1 ]
}
