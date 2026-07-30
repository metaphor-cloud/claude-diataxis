/// Error raised when key rotation fails.
export class KeyError extends Error {
  code = 1;
}

/// Rotate the signing key identified by id.
export function rotateKey(id: string): boolean {
  if (id === "") {
    throw new KeyError("empty key id");
  }
  return true;
}

function internalHelper(): number {
  return 42;
}
