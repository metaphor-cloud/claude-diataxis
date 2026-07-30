#!/usr/bin/env bats
# Language adapters: detection via init, and plan output against the golden
# plan.json for each fixture repo.

setup() {
  load 'helpers/test_helper'
  make_sandbox
}

plan_matches_golden() {
  local lang="$1" dirname="$2"
  make_repo "$lang" "$dirname"
  echo '{"version":1}' >"$WORK/diataxis.config.json"
  export CLAUDE_STUB_RESPONSE="$TESTS_DIR/fixtures/$lang/responses/plan.json"
  run dtx plan
  [ "$status" -eq 0 ]
  local actual expected
  actual=$(jq -S '{pages: .pages}' "$WORK/.diataxis/plan.json")
  expected=$(jq -S . "$TESTS_DIR/fixtures/$lang/golden-plan.json")
  if [ "$actual" != "$expected" ]; then
    echo "expected: $expected" >&2
    echo "actual:   $actual" >&2
    return 1
  fi
}

detects_adapter() {
  local lang="$1" dirname="$2" expect="$3"
  make_repo "$lang" "$dirname"
  run dtx init
  [ "$status" -eq 0 ]
  [ "$(jq -r '.workspaces[0].adapter' "$WORK/diataxis.config.json")" = "$expect" ]
}

@test "rust: init detects the adapter" { detects_adapter rust proj-rust rust; }
@test "go: init detects the adapter" { detects_adapter go proj-go go; }
@test "python: init detects the adapter" { detects_adapter python proj-py python; }
@test "typescript: init detects the adapter" { detects_adapter typescript proj-ts typescript; }
@test "shell: init detects the adapter" { detects_adapter shell proj-sh shell; }

@test "rust: plan matches the golden plan" { plan_matches_golden rust proj-rust; }
@test "go: plan matches the golden plan" { plan_matches_golden go proj-go; }
@test "python: plan matches the golden plan" { plan_matches_golden python proj-py; }
@test "typescript: plan matches the golden plan" { plan_matches_golden typescript proj-ts; }
@test "shell: plan matches the golden plan" { plan_matches_golden shell proj-sh; }

@test "shell: inventory marks underscore names internal and finds constants" {
  make_repo shell proj-sh
  run bash -c "cd '$WORK' && DIATAXIS_ROOT='$REPO_ROOT' sh -c '. \"$REPO_ROOT/lib/adapters/shell.sh\"; adapter_symbol_inventory'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -es '
    (map(select(.name == "rotate_key")) | .[0].visibility == "public") and
    (map(select(.name == "_internal_helper")) | .[0].visibility == "internal") and
    (map(select(.name == "KEY_ROTATION_LIMIT")) | .[0].kind == "constant") and
    (map(select(.name == "usage")) | .[0].path == "bin/keytool")' >/dev/null
}

@test "shell: adapter does not claim repos owned by another language" {
  make_repo rust proj-rust
  printf '#!/bin/sh\necho build\n' >"$WORK/build.sh"
  (cd "$WORK" && git add build.sh \
    && git -c user.email=t@example.com -c user.name=t commit -qm build)
  run dtx init
  [ "$status" -eq 0 ]
  [ "$(jq -r '.workspaces[0].adapter' "$WORK/diataxis.config.json")" = "rust" ]
}

@test "plan never writes prose" {
  make_repo rust proj-rust
  echo '{"version":1}' >"$WORK/diataxis.config.json"
  export CLAUDE_STUB_RESPONSE="$TESTS_DIR/fixtures/rust/responses/plan.json"
  run dtx plan
  [ "$status" -eq 0 ]
  [ ! -d "$WORK/docs" ] || [ -z "$(find "$WORK/docs" -name '*.md' 2>/dev/null)" ]
}

@test "generate refuses pages that are not in the plan" {
  make_repo rust proj-rust
  echo '{"version":1}' >"$WORK/diataxis.config.json"
  write_plan '{"pages":[]}'
  run dtx generate --page how-to/invented
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
}
