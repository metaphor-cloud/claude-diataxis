#!/usr/bin/env bats
# Opt-in live smoke test. Requires DIATAXIS_LIVE=1 and real claude auth.
# Capped at --budget-usd 0.50.

setup() {
  load 'helpers/test_helper'
  if [ "${DIATAXIS_LIVE:-0}" != "1" ]; then
    skip "set DIATAXIS_LIVE=1 to run the live smoke test"
  fi
  make_repo rust proj-rust
  echo '{"version":1}' >"$WORK/diataxis.config.json"
}

# Live runs use the real PATH, not the sandbox.
dtx_live() {
  (cd "$WORK" && "$DIATAXIS_BIN" "$@")
}

@test "live: doctor passes" {
  run dtx_live doctor
  [ "$status" -eq 0 ]
}

@test "live: plan produces a valid inventory under budget" {
  run dtx_live --budget-usd 0.50 plan
  [ "$status" -eq 0 ]
  [ -f "$WORK/.diataxis/plan.json" ]
  run jq -e '.pages | length >= 1' "$WORK/.diataxis/plan.json"
  [ "$status" -eq 0 ]
}
