# Shared bats helpers. Each test gets a hermetic sandbox PATH (a directory of
# symlinks to real tools plus the claude stub) and a throwaway git repo.

TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
DIATAXIS_BIN="$REPO_ROOT/bin/diataxis"

SANDBOX_TOOLS="jq git awk sed grep sort head tail find wc tr cut date mktemp
basename dirname cat cp mv rm mkdir ls base64 xargs shasum sha256sum uname env
sh bash touch chmod true false"

# make_sandbox [tools to omit...]: build the sandbox PATH directory.
# Pass tool names (or "claude") to leave them out.
make_sandbox() {
  SANDBOX_BIN="$BATS_TEST_TMPDIR/sbin"
  rm -rf "$SANDBOX_BIN"
  mkdir -p "$SANDBOX_BIN"
  local omit=" $* "
  local t p
  for t in $SANDBOX_TOOLS; do
    case "$omit" in *" $t "*) continue ;; esac
    p=$(command -v "$t" 2>/dev/null) || continue
    ln -sf "$p" "$SANDBOX_BIN/$t"
  done
  case "$omit" in
    *" claude "*) ;;
    *)
      cp "$TESTS_DIR/helpers/claude" "$SANDBOX_BIN/claude"
      chmod +x "$SANDBOX_BIN/claude"
      ;;
  esac
  export SANDBOX_BIN
}

# make_repo [fixture] [dirname]: create a throwaway git repo, optionally from
# tests/fixtures/<fixture>/repo. The directory name matters: derived reference
# slugs for root-level modules use it.
make_repo() {
  local fixture="${1:-}"
  local name="${2:-proj}"
  WORK="$BATS_TEST_TMPDIR/$name"
  rm -rf "$WORK"
  mkdir -p "$WORK"
  if [ -n "$fixture" ]; then
    cp -R "$TESTS_DIR/fixtures/$fixture/repo/." "$WORK/"
  fi
  (cd "$WORK" \
    && git init -q \
    && git add -A \
    && git -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init) >/dev/null 2>&1
  export WORK
}

# dtx ...: run diataxis inside $WORK with the sandbox PATH and controlled
# credentials. Set STUB_OAUTH / STUB_APIKEY to simulate env credentials.
dtx() {
  (cd "$WORK" \
    && PATH="$SANDBOX_BIN" \
       HOME="$BATS_TEST_TMPDIR" \
       NO_COLOR=1 \
       CLAUDE_CODE_OAUTH_TOKEN="${STUB_OAUTH:-}" \
       ANTHROPIC_API_KEY="${STUB_APIKEY:-}" \
       "$DIATAXIS_BIN" "$@")
}

# write_plan JSON: write .diataxis/plan.json directly, bypassing the plan call.
write_plan() {
  mkdir -p "$WORK/.diataxis"
  printf '%s\n' "$1" | jq '{version: 1, generated_at: "2026-01-01T00:00:00Z", pages: .pages}' \
    >"$WORK/.diataxis/plan.json"
}

# argv_block: print the argv lines captured from a --dry-run generate/plan.
# The dry-run format is: "claude", one line per argument, blank line.
assert_argv_contains() {
  local needle="$1"
  case "$output" in
    *"$needle"*) return 0 ;;
  esac
  echo "expected argv to contain: $needle" >&2
  echo "actual output: $output" >&2
  return 1
}

assert_argv_missing() {
  local needle="$1"
  case "$output" in
    *"$needle"*)
      echo "expected argv NOT to contain: $needle" >&2
      echo "actual output: $output" >&2
      return 1
      ;;
  esac
  return 0
}
