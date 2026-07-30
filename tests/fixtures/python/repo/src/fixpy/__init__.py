"""Key management."""

__all__ = ["rotate_key", "KeyError_"]


class KeyError_(Exception):
    """Raised when key rotation fails."""


def rotate_key(key_id):
    """Rotate the signing key identified by key_id."""
    if not key_id:
        raise KeyError_("empty key id")
    return True


def _internal_helper():
    return 42
