#!/bin/sh
# Vendors the diataxis harness into a target repository and writes a starter
# config. Usage:
#
#   From a checkout of the harness:
#     path/to/claude-diataxis/install.sh [target-repo-dir]
#
#   Via curl (set the repo URL if not using the default):
#     curl -fsSL <raw url>/install.sh | DIATAXIS_REPO_URL=<git url> sh
#
# Vendoring (committing diataxis/ into your repo) is the primary distribution
# path. git subtree and git submodule work too; see README.md.
set -eu

TARGET=${1:-.}
DEST="$TARGET/diataxis"

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[ -d "$TARGET" ] || die "target directory not found: $TARGET"
command -v git >/dev/null 2>&1 || die "git is required"

# Where is the harness coming from?
self_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd) || self_dir=''

if [ -n "$self_dir" ] && [ -x "$self_dir/bin/diataxis" ]; then
  src="$self_dir"
else
  [ -n "${DIATAXIS_REPO_URL:-}" ] \
    || die "not running from a harness checkout and DIATAXIS_REPO_URL is not set"
  src=$(mktemp -d "${TMPDIR:-/tmp}/diataxis-install.XXXXXX")
  trap 'rm -rf "$src"' EXIT
  git clone --depth 1 "$DIATAXIS_REPO_URL" "$src" >/dev/null 2>&1 \
    || die "could not clone $DIATAXIS_REPO_URL"
fi

if [ -e "$DEST" ]; then
  die "$DEST already exists; remove it or update via git subtree/submodule instead"
fi

mkdir -p "$DEST"
for d in bin lib prompts schemas share; do
  cp -R "$src/$d" "$DEST/$d"
done
cp "$src/install.sh" "$DEST/install.sh" 2>/dev/null || true
chmod +x "$DEST/bin/diataxis"
# The starter config points verify.sandbox_command at this wrapper, and the
# harness execs it directly, so it has to stay executable through vendoring.
chmod +x "$DEST/share/sandbox/verify-sandbox.sh"

if [ ! -f "$TARGET/diataxis.config.json" ]; then
  cp "$src/share/diataxis.config.example.json" "$TARGET/diataxis.config.json"
  printf 'wrote %s/diataxis.config.json (starter config)\n' "$TARGET"
else
  printf 'kept existing %s/diataxis.config.json\n' "$TARGET"
fi

printf 'vendored diataxis into %s\n' "$DEST"
printf 'next steps:\n'
printf '  1. commit the diataxis/ directory\n'
printf '  2. run: %s/bin/diataxis doctor\n' "$DEST"
printf '  3. run: %s/bin/diataxis init && %s/bin/diataxis plan\n' "$DEST" "$DEST"
