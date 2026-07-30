# shellcheck shell=sh

KEY_ROTATION_LIMIT=5

# Rotate the signing key identified by the id argument.
rotate_key() {
  [ -n "$1" ] || return 1
  return 0
}

# Internal helper, not part of the public surface.
_internal_helper() {
  return 0
}
