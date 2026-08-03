#!/bin/sh
# verify-sandbox.sh STEP_SCRIPT: run one tutorial step script under whatever
# confinement the host provides, and fail closed when it provides none.
#
# Point verify.sandbox_command at this file to stop tutorial verification from
# executing model-authored shell on the host with your full authority:
#
#   "sandbox_command": "share/sandbox/verify-sandbox.sh"
#
# The harness appends the step script's path as the final argument and runs the
# command with the ephemeral verification directory as the working directory
# (bin/diataxis, tutorial_verify). That working directory is the only path the
# step is allowed to write to.
#
# Guarantees, on both supported mechanisms:
#   - no network access
#   - no writes outside the verification directory
#   - TMPDIR redirected inside the verification directory, so mktemp works
#
# Exit status is the step script's own, so the harness reports a failing
# tutorial normally. The one exception is EX_CONFIG (78), used when no
# confinement mechanism is available. There is deliberately no unconfined
# fallback: a sandbox that quietly stops sandboxing is worse than one that
# refuses to run.

set -eu

EX_CONFIG=78

script=${1:-}
if [ -z "$script" ]; then
  printf 'verify-sandbox: no step script given\n' >&2
  exit "$EX_CONFIG"
fi
if [ ! -f "$script" ]; then
  printf 'verify-sandbox: step script not found: %s\n' "$script" >&2
  exit "$EX_CONFIG"
fi

# Resolve to physical paths. Both mechanisms match on the real path, and on
# macOS the temporary directory reached through /var is a symlink to /private/var.
abspath() {
  case "$1" in
    /*) _d=$(dirname "$1"); _b=$(basename "$1") ;;
    *) _d=$(dirname "$PWD/$1"); _b=$(basename "$1") ;;
  esac
  printf '%s/%s\n' "$(cd "$_d" && pwd -P)" "$_b"
}

script=$(abspath "$script")
verify_dir=$(pwd -P)
home_dir=$(cd "${HOME:-/}" && pwd -P)

# Keep mktemp and anything else temp-hungry inside the writable area.
tmp_dir="$verify_dir/.sandbox-tmp"
mkdir -p "$tmp_dir"

# The harness's own run directory holds every other page's step scripts and
# intermediate JSON, and it lives inside the same per-user temp dir that has to
# stay writable for mktemp. It is denied explicitly so a step cannot reach
# sideways into another page's work. Falling back to the verification directory
# when DIATAXIS_TMPDIR is unset (the wrapper run standalone) makes the deny rule
# a no-op rather than an accidental denial of the one writable path.
harness_tmp=${DIATAXIS_TMPDIR:-}
if [ -n "$harness_tmp" ] && [ -d "$harness_tmp" ]; then
  harness_tmp=$(cd "$harness_tmp" && pwd -P)
else
  harness_tmp=$verify_dir
fi

if command -v sandbox-exec >/dev/null 2>&1; then
  profile=$(dirname "$(abspath "$0")")/macos-verify.sb
  if [ ! -f "$profile" ]; then
    printf 'verify-sandbox: profile missing next to the wrapper: %s\n' "$profile" >&2
    exit "$EX_CONFIG"
  fi
  # macOS mktemp -t resolves this through confstr() and ignores TMPDIR, so the
  # profile has to name it explicitly. See the carve-out note in the profile.
  # getconf reports it through the /var symlink with a trailing slash; sandbox
  # profiles match physical paths, so resolve it or the rule silently misses.
  darwin_tmp=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || printf '/var/tmp')
  darwin_tmp=$(cd "$darwin_tmp" 2>/dev/null && pwd -P) || darwin_tmp=$tmp_dir
  exec env TMPDIR="$tmp_dir" \
    sandbox-exec \
      -D VERIFY_DIR="$verify_dir" \
      -D HOME_DIR="$home_dir" \
      -D DARWIN_TMP="$darwin_tmp" \
      -D HARNESS_TMP="$harness_tmp" \
      -f "$profile" \
      /bin/sh -e "$script"
fi

if command -v bwrap >/dev/null 2>&1; then
  # --ro-bind / / gives the step every tool it might legitimately run while
  # making the whole filesystem read-only; the verification directory is then
  # bound back in writable. --unshare-net is the network denial.
  exec env TMPDIR="$tmp_dir" \
    bwrap \
      --unshare-net \
      --unshare-pid \
      --unshare-ipc \
      --unshare-uts \
      --die-with-parent \
      --ro-bind / / \
      --dev /dev \
      --proc /proc \
      --bind "$verify_dir" "$verify_dir" \
      --chdir "$verify_dir" \
      --setenv TMPDIR "$tmp_dir" \
      /bin/sh -e "$script"
fi

printf 'verify-sandbox: no confinement mechanism available (looked for sandbox-exec, bwrap); refusing to run %s unconfined\n' \
  "$script" >&2
exit "$EX_CONFIG"
