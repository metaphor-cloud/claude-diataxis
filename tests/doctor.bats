#!/usr/bin/env bats
# Preamble and doctor failure paths, with claude stubbed on a hermetic PATH.

setup() {
  load 'helpers/test_helper'
  make_sandbox
  make_repo
  echo '{"version":1}' >"$WORK/diataxis.config.json"
}

teardown() {
  chmod -R u+w "$BATS_TEST_TMPDIR" 2>/dev/null || true
}

@test "doctor passes in a healthy environment" {
  run dtx doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"all checks passed"* ]]
}

@test "doctor exit 10 when claude is missing" {
  make_sandbox claude
  run dtx doctor
  [ "$status" -eq 10 ]
  [[ "$output" == *"npm i -g @anthropic-ai/claude-code"* ]]
}

@test "doctor exit 11 when claude is too old" {
  export CLAUDE_STUB_VERSION="2.1.100"
  run dtx doctor
  [ "$status" -eq 11 ]
  [[ "$output" == *"2.1.205"* ]]
}

@test "doctor exit 13 when jq is missing" {
  make_sandbox jq
  run dtx doctor
  [ "$status" -eq 13 ]
}

@test "doctor exit 14 outside a git work tree" {
  WORK="$BATS_TEST_TMPDIR/nogit"
  mkdir -p "$WORK"
  run dtx doctor
  [ "$status" -eq 14 ]
}

@test "doctor exit 12 when auth status reports logged out" {
  export CLAUDE_STUB_AUTH=fail
  run dtx doctor
  [ "$status" -eq 12 ]
  [[ "$output" == *"claude setup-token"* ]]
}

@test "doctor falls back to a live probe when auth status is absent" {
  export CLAUDE_STUB_AUTH=absent
  run dtx doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"probe_ok"* ]]
}

@test "doctor exit 12 when auth status is absent and the probe fails" {
  export CLAUDE_STUB_AUTH=absent
  export CLAUDE_STUB_RESPONSE="$TESTS_DIR/fixtures/rust/responses/empty-result.json"
  run dtx doctor
  [ "$status" -eq 12 ]
}

@test "doctor reports env credential auth methods" {
  STUB_OAUTH=test-token run dtx doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"oauth_token_env"* ]]
}

@test "doctor exit 15 when docs dir is not writable" {
  mkdir -p "$WORK/docs"
  chmod 555 "$WORK/docs"
  run dtx doctor
  chmod 755 "$WORK/docs"
  [ "$status" -eq 15 ]
}

@test "doctor --json emits machine-readable status" {
  run dtx --json doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"command":"doctor"'
  echo "$output" | grep -q '"status":"ok"'
}

@test "doctor warns when subscription auth is not bare-capable" {
  run dtx doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"not bare-capable"* ]]
}

@test "version_ge compares dot-separated versions" {
  run sh -c ". '$REPO_ROOT/lib/preamble.sh'; version_ge 2.1.220 2.1.205"
  [ "$status" -eq 0 ]
  run sh -c ". '$REPO_ROOT/lib/preamble.sh'; version_ge 2.1.100 2.1.205"
  [ "$status" -eq 1 ]
  run sh -c ". '$REPO_ROOT/lib/preamble.sh'; version_ge 3.0.0 2.9.999"
  [ "$status" -eq 0 ]
}
