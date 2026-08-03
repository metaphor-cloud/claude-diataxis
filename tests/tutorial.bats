#!/usr/bin/env bats
# Tutorial step extraction and sandboxed verification.
#
# Extraction fidelity used to be structurally guaranteed: every field was
# base64-encoded through the shell pipeline, so tutorial code containing tabs,
# newlines or quotes could not corrupt the loop that consumed it. Extraction now
# writes each block straight from jq, so that property needs real coverage.
#
# These tests assert it end to end rather than by calling internals: the step
# scripts themselves fail unless their code arrived intact, so a tutorial that
# reaches "verified: true" is proof the extraction was byte-faithful.

setup() {
  load 'helpers/test_helper'
  make_sandbox
  make_repo rust proj-rust
  echo '{"version":1}' >"$WORK/diataxis.config.json"
  RESPONSES="$TESTS_DIR/fixtures/rust/responses"
}

tutorial_plan() {
  write_plan '{"pages":[{"slug":"tutorials/get-started","mode":"tutorial","title":"Get started","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"beginner"}]}'
}

@test "tabs, quotes, substitution and newlines survive extraction into step scripts" {
  tutorial_plan
  # Step 0 compares a literal tab against a printf-generated one, echoes both
  # quote kinds and a $(...), and counts embedded newlines. Any mangling by the
  # extractor makes it exit non-zero and the page comes out unverified.
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-tricky.json"
  run dtx generate --mode tutorial
  [ "$status" -eq 0 ]
  grep -q '^verified: true$' "$WORK/docs/tutorials/get-started.md"
}

@test "a console block runs its commands and not its transcript output" {
  tutorial_plan
  # The console step interleaves "$ " commands with output lines, one of which
  # ("this-line-is-transcript-output-not-a-command") is not a command at all.
  # Executing it would abort the step under sh -e, so verification passing is
  # what proves only the "$ " lines were kept.
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-console.json"
  run dtx generate --mode tutorial
  [ "$status" -eq 0 ]
  grep -q '^verified: true$' "$WORK/docs/tutorials/get-started.md"
}

@test "a block in a non-executable language is skipped rather than run as shell" {
  tutorial_plan
  # The step is python, "import sys; sys.exit(1)", which fails immediately if it
  # is ever handed to sh. python is absent from the default
  # verify.executable_languages, so no step script should be written for it and
  # the page verifies with nothing to run.
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-skiplang.json"
  run dtx generate --mode tutorial
  [ "$status" -eq 0 ]
  grep -q '^verified: true$' "$WORK/docs/tutorials/get-started.md"
}

@test "step scripts run in numeric order, so step-10 follows step-9" {
  tutorial_plan
  # Twelve steps: 0 through 10 append their index to order.txt, and step 11
  # compares the result against 0..10. Under a lexicographic sort step-10 would
  # run third and the comparison would fail.
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-order.json"
  run dtx generate --mode tutorial
  [ "$status" -eq 0 ]
  grep -q '^verified: true$' "$WORK/docs/tutorials/get-started.md"
}

# --- the shipped confinement wrapper ----------------------------------------------
#
# share/sandbox/verify-sandbox.sh is what verify.sandbox_command points at. These
# tests drive it the way tutorial_verify does: the step script path as the final
# argument, with the verification directory as the working directory.

SANDBOX_WRAPPER() { printf '%s\n' "$REPO_ROOT/share/sandbox/verify-sandbox.sh"; }

# Run the wrapper on a step script whose body is $1, from a fresh verify dir.
run_wrapped() {
  VDIR="$BATS_TEST_TMPDIR/vdir"
  rm -rf "$VDIR"
  mkdir -p "$VDIR"
  printf '%s\n' "$1" >"$BATS_TEST_TMPDIR/step-0.sh"
  (cd "$VDIR" && sh -c "$(SANDBOX_WRAPPER) \"\$1\"" verify "$BATS_TEST_TMPDIR/step-0.sh" 2>&1)
}

# The wrapper needs a real confinement mechanism; CI runners without either one
# exercise the fail-closed test below instead.
require_confinement() {
  if ! command -v sandbox-exec >/dev/null 2>&1 && ! command -v bwrap >/dev/null 2>&1; then
    skip "no confinement mechanism (sandbox-exec or bwrap) on this host"
  fi
}

@test "sandbox wrapper lets a well-behaved step write inside the verify directory" {
  require_confinement
  run run_wrapped 'mkdir -p sub && echo written >sub/file.txt && cat sub/file.txt'
  [ "$status" -eq 0 ]
  [[ "$output" == *written* ]]
}

@test "sandbox wrapper denies writes outside the verify directory" {
  require_confinement
  # Deliberately not under BATS_TEST_TMPDIR: on macOS that lives inside the
  # per-user Darwin temp dir, which the profile has to keep writable so mktemp
  # works. /tmp is outside it and is the honest test of the boundary.
  escape="/tmp/diataxis-escape-test-$$.txt"
  rm -f "$escape"
  run run_wrapped "echo pwned >'$escape'"
  [ "$status" -ne 0 ]
  [ ! -f "$escape" ]
}

@test "sandbox wrapper denies writes into the harness's own run directory" {
  require_confinement
  # The harness run directory holds other pages' step scripts and intermediate
  # JSON, and it sits inside the writable Darwin temp dir, so it needs its own
  # deny rule. Without it one tutorial's step could rewrite the next page's
  # script before it executes.
  local harness="$BATS_TEST_TMPDIR/harness-tmp"
  rm -rf "$harness"
  mkdir -p "$harness/page-1"
  printf 'echo original\n' >"$harness/page-1/step-0.sh"
  VDIR="$harness/page-0/run"
  mkdir -p "$VDIR"
  printf '%s\n' "echo tampered >'$harness/page-1/step-0.sh'" >"$BATS_TEST_TMPDIR/step-0.sh"
  run env DIATAXIS_TMPDIR="$harness" sh -c \
    "cd '$VDIR' && $(SANDBOX_WRAPPER) \"\$1\"" verify "$BATS_TEST_TMPDIR/step-0.sh"
  [ "$status" -ne 0 ]
  grep -q '^echo original$' "$harness/page-1/step-0.sh"
}

@test "sandbox wrapper still allows writes to its own verify dir inside the harness tmpdir" {
  require_confinement
  # The deny rule above covers the harness run directory, and the verification
  # directory sits underneath it, so rule order in the profile decides whether
  # any tutorial can run at all. This is the regression guard for that ordering.
  local harness="$BATS_TEST_TMPDIR/harness-tmp2"
  rm -rf "$harness"
  VDIR="$harness/page-0/run"
  mkdir -p "$VDIR"
  printf 'echo written >inside.txt && cat inside.txt\n' >"$BATS_TEST_TMPDIR/step-0.sh"
  run env DIATAXIS_TMPDIR="$harness" sh -c \
    "cd '$VDIR' && $(SANDBOX_WRAPPER) \"\$1\"" verify "$BATS_TEST_TMPDIR/step-0.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *written* ]]
}

@test "sandbox wrapper denies writes into the invoking user's home" {
  require_confinement
  run run_wrapped 'echo pwned >"$HOME/DIATAXIS_ESCAPE.txt"'
  [ "$status" -ne 0 ]
  [ ! -f "$HOME/DIATAXIS_ESCAPE.txt" ]
}

@test "sandbox wrapper denies network access" {
  require_confinement
  # Resolution and connection both fail under the profile; either way the step
  # must not succeed. No external service is contacted when the sandbox works.
  run run_wrapped 'curl -sS --max-time 5 https://example.com >/dev/null'
  [ "$status" -ne 0 ]
  [[ "$output" != *"NETWORK REACHED"* ]]
}

@test "sandbox wrapper keeps mktemp working inside the sandbox" {
  require_confinement
  # macOS mktemp -t ignores TMPDIR and resolves the per-user Darwin temp dir
  # through confstr(), which the profile has to allow explicitly or ordinary
  # tooling breaks for reasons unrelated to the tutorial.
  run run_wrapped 't=$(mktemp -t probe) && echo tmpok >"$t" && cat "$t"'
  [ "$status" -eq 0 ]
  [[ "$output" == *tmpok* ]]
}

@test "sandbox wrapper propagates a failing step's own exit status" {
  require_confinement
  run run_wrapped 'exit 3'
  [ "$status" -eq 3 ]
}

@test "sandbox wrapper fails closed when no confinement mechanism exists" {
  # A PATH with coreutils but no sandbox-exec and no bwrap. The step script
  # would print a marker if it ran; the wrapper must refuse instead of falling
  # back to unconfined host execution.
  local pbin="$BATS_TEST_TMPDIR/pbin"
  rm -rf "$pbin"
  mkdir -p "$pbin"
  local t p
  for t in sh env dirname basename getconf mkdir cat; do
    p=$(command -v "$t" 2>/dev/null) || continue
    ln -sf "$p" "$pbin/$t"
  done
  mkdir -p "$BATS_TEST_TMPDIR/vdir"
  printf 'echo SHOULD_NOT_RUN\n' >"$BATS_TEST_TMPDIR/step-0.sh"
  run env PATH="$pbin" "$pbin/sh" -c \
    "$(SANDBOX_WRAPPER) \"\$1\"" verify "$BATS_TEST_TMPDIR/step-0.sh"
  [ "$status" -eq 78 ]
  [[ "$output" != *SHOULD_NOT_RUN* ]]
  [[ "$output" == *"no confinement mechanism available"* ]]
}

@test "sandbox wrapper refuses a missing or absent step script" {
  run "$(SANDBOX_WRAPPER)"
  [ "$status" -eq 78 ]
  [[ "$output" == *"no step script given"* ]]

  run "$(SANDBOX_WRAPPER)" "$BATS_TEST_TMPDIR/does-not-exist.sh"
  [ "$status" -eq 78 ]
  [[ "$output" == *"step script not found"* ]]
}
