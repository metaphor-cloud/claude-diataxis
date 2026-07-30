/// Error raised when key rotation fails.
pub struct KeyError {
    pub code: u32,
}

/// Rotate the signing key identified by `id`.
pub fn rotate_key(id: &str) -> Result<(), KeyError> {
    if id.is_empty() {
        return Err(KeyError { code: 1 });
    }
    Ok(())
}

fn internal_helper() -> u32 {
    42
}
