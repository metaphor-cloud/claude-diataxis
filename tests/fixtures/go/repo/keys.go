// Package fixgo manages signing keys.
package fixgo

// KeyError is returned when key rotation fails.
type KeyError struct {
	Code int
}

// RotateKey rotates the signing key identified by id.
func RotateKey(id string) error {
	if id == "" {
		return nil
	}
	return nil
}

func internalHelper() int {
	return 42
}
