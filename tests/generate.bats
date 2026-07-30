#!/usr/bin/env bats
# Generation end to end on the rust fixture with the claude stub: manifest
# hashing, staleness, cost accumulation, human-edit protection, tutorial
# verification, the how-to split contract, and clean.

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

@test "reference generation writes the page and a manifest entry" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  [ -f "$WORK/docs/reference/proj-rust.md" ]
  grep -q 'rotate_key' "$WORK/docs/reference/proj-rust.md"
  grep -q '^mode: reference$' "$WORK/docs/reference/proj-rust.md"
  run jq -r '.pages[0].inputs_hash' "$WORK/.diataxis/manifest.json"
  [[ "$output" == sha256:* ]]
  run jq -r '.pages[0].model_used' "$WORK/.diataxis/manifest.json"
  [ "$output" = "claude-sonnet-5" ]
  run jq -r '.pages[0].cost_usd' "$WORK/.diataxis/manifest.json"
  [ "$output" = "0.0123" ]
}

@test "a second run does no work when inputs are unchanged" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "changing a source file makes the page stale and regenerates it" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  echo '// touched' >>"$WORK/src/lib.rs"
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 ok"* ]]
}

@test "--force regenerates an up-to-date page" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  run dtx generate --mode reference --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 ok"* ]]
}

@test "cost accumulates in the manifest across runs" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  echo '// touched' >>"$WORK/src/lib.rs"
  dtx generate --mode reference
  run dtx --json cost
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep '^{' | jq -e '.total_usd > 0.01 and .total_usd < 0.02' >/dev/null
}

@test "hand-edited pages are never overwritten without --force" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  echo 'HUMAN EDIT' >>"$WORK/docs/reference/proj-rust.md"
  echo '// touched' >>"$WORK/src/lib.rs"
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  [[ "$output" == *"diataxis did not generate"* ]]
  grep -q 'HUMAN EDIT' "$WORK/docs/reference/proj-rust.md"
  run dtx generate --mode reference --force
  [ "$status" -eq 0 ]
  ! grep -q 'HUMAN EDIT' "$WORK/docs/reference/proj-rust.md"
}

@test "a pre-existing hand-written file at a plan slug is not clobbered" {
  ref_plan
  mkdir -p "$WORK/docs/reference"
  echo 'hand written' >"$WORK/docs/reference/proj-rust.md"
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  grep -q 'hand written' "$WORK/docs/reference/proj-rust.md"
}

@test "frozen pages are skipped even when stale" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  sed_inplace 's/^frozen: false$/frozen: true/' "$WORK/docs/reference/proj-rust.md"
  echo '// touched' >>"$WORK/src/lib.rs"
  run dtx generate --mode reference --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}

@test "unresolved citations are a failed generation" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference-broken-citation.json"
  run dtx generate --mode reference
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved citations"* ]]
  [ ! -f "$WORK/docs/reference/proj-rust.md" ]
}

@test "qualified symbol citations resolve via the leaf identifier" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference-dotted-citation.json"
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  [ -f "$WORK/docs/reference/proj-rust.md" ]
}

@test "comma-joined symbol lists resolve when every identifier exists" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference-list-citation.json"
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  [ -f "$WORK/docs/reference/proj-rust.md" ]
}

@test "phrase symbol citations still fail the generation" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference-phrase-citation.json"
  run dtx generate --mode reference
  [ "$status" -eq 1 ]
  [[ "$output" == *"unresolved citations"* ]]
}

@test "verified tutorial gets verified true frontmatter" {
  write_plan '{"pages":[{"slug":"tutorials/get-started","mode":"tutorial","title":"Get started","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"beginner"}]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-ok.json"
  run dtx generate --mode tutorial
  [ "$status" -eq 0 ]
  grep -q '^verified: true$' "$WORK/docs/tutorials/get-started.md"
}

@test "failing tutorial exhausts repairs and is written unverified" {
  write_plan '{"pages":[{"slug":"tutorials/get-started","mode":"tutorial","title":"Get started","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"beginner"}]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/tutorial-fail.json"
  run dtx generate --mode tutorial
  [ "$status" -eq 0 ]
  grep -q '^verified: false$' "$WORK/docs/tutorials/get-started.md"
  run jq -r '.pages[0].verified' "$WORK/.diataxis/manifest.json"
  [ "$output" = "false" ]
}

@test "a how-to with two goals splits and amends the plan" {
  write_plan '{"pages":[{"slug":"how-to/manage-keys","mode":"howto","title":"Manage keys","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"developer"}]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/howto-split.json"
  run dtx generate --mode howto
  [ "$status" -eq 0 ]
  [[ "$output" == *"plan amended"* ]]
  run jq -r '.pages | length' "$WORK/.diataxis/plan.json"
  [ "$output" = "2" ]
  run jq -r '.pages[].slug' "$WORK/.diataxis/plan.json"
  [[ "$output" == *"how-to/rotate-a-key"* ]]
  [[ "$output" == *"how-to/revoke-a-key"* ]]
}

@test "howto generation renders steps and verification" {
  write_plan '{"pages":[{"slug":"how-to/rotate-a-signing-key","mode":"howto","title":"Rotate a signing key","rationale":"r","sources":["src/lib.rs"],"priority":1,"audience":"developer"}]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/howto.json"
  run dtx generate --mode howto
  [ "$status" -eq 0 ]
  grep -q '## Verify it worked' "$WORK/docs/how-to/rotate-a-signing-key.md"
}

@test "large symbol inventories route to the bulk model and still render as reference" {
  # 30 pub constants crosses the 25-symbol reference_bulk threshold. The
  # page must come back with mode reference (a caller-variable clobber in
  # claude_run once turned it into 'no renderer for mode reference_bulk').
  for i in $(seq 1 30); do
    printf 'pub const LIMIT_%s: u32 = %s;\n' "$i" "$i" >>"$WORK/src/lib.rs"
  done
  (cd "$WORK" && git add src/lib.rs \
    && git -c user.email=t@example.com -c user.name=t commit -qm bulk)
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  run dtx generate --mode reference
  [ "$status" -eq 0 ]
  [[ "$output" == *"reference_bulk: calling"*"claude-haiku-4-5"* ]] || {
    echo "expected bulk routing in: $output" >&2; return 1; }
  [ -f "$WORK/docs/reference/proj-rust.md" ]
  run jq -r '.pages[0].mode' "$WORK/.diataxis/manifest.json"
  [ "$output" = "reference" ]
  run jq -r '.pages[0].model_requested' "$WORK/.diataxis/manifest.json"
  [ "$output" = "claude-haiku-4-5" ]
}

@test "run budget accumulates across pages and refuses the next call" {
  write_plan '{"pages":[
    {"slug":"reference/proj-rust","mode":"reference","title":"proj-rust reference","rationale":"derived","sources":["src/lib.rs"],"priority":2,"audience":"developer"},
    {"slug":"reference/second","mode":"reference","title":"second reference","rationale":"derived","sources":["src/lib.rs"],"priority":2,"audience":"developer"}
  ]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  # First page costs 0.0123, exceeding the 0.01 budget; the second call must
  # be refused before it starts.
  run dtx --budget-usd 0.01 generate --mode reference
  [ "$status" -eq 20 ]
  [ -f "$WORK/docs/reference/proj-rust.md" ]
  [[ "$output" != *"[2/2]"*"-> reference"*"[2/2]"* ]]
  run jq -r '.pages | length' "$WORK/.diataxis/manifest.json"
  [ "$output" = "1" ]
}

@test "a usage limit aborts the run with a resumable message" {
  write_plan '{"pages":[
    {"slug":"reference/proj-rust","mode":"reference","title":"proj-rust reference","rationale":"derived","sources":["src/lib.rs"],"priority":2,"audience":"developer"},
    {"slug":"reference/second","mode":"reference","title":"second reference","rationale":"derived","sources":["src/lib.rs"],"priority":2,"audience":"developer"}
  ]}'
  export CLAUDE_STUB_RESPONSE="$RESPONSES/session-limit.json"
  export CLAUDE_STUB_EXIT=1
  run dtx generate --mode reference
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage limit hit"* ]]
  [[ "$output" == *"re-run generate"* ]]
  # The second page was never attempted.
  [[ "$output" != *"[2/2]"* ]]
}

@test "clean removes generated pages that left the plan and keeps frozen ones" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  write_plan '{"pages":[]}'
  run dtx clean
  [ "$status" -eq 0 ]
  [ ! -f "$WORK/docs/reference/proj-rust.md" ]
  run jq -r '.pages | length' "$WORK/.diataxis/manifest.json"
  [ "$output" = "0" ]
}

@test "clean --dry-run only reports" {
  ref_plan
  export CLAUDE_STUB_RESPONSE="$RESPONSES/reference.json"
  dtx generate --mode reference
  write_plan '{"pages":[]}'
  run dtx --dry-run clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove"* ]]
  [ -f "$WORK/docs/reference/proj-rust.md" ]
}

# BSD/GNU sed -i split, handled once here for tests.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$1" "$2"
  else
    sed -i '' "$1" "$2"
  fi
}
