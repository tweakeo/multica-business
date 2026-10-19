// Package secretsfile loads KEY=VALUE secrets from the file named by
// MULTICA_SECRETS_FILE into the process environment (TLS embedded mode).
//
// Secrets passed as environment variables at exec time stay readable by any
// same-user process through KERN_PROCARGS2, including sandboxed agents. A
// file the sandbox denies keeps them out of reach: only its path is passed.
package secretsfile

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

const Env = "MULTICA_SECRETS_FILE"

// Load reads the secrets file if configured. Values already set in the
// environment win, so explicit configuration is never overridden.
func Load() error {
	path := os.Getenv(Env)
	if path == "" {
		return nil
	}
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open %s: %w", Env, err)
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if _, set := os.LookupEnv(key); set {
			continue
		}
		if err := os.Setenv(key, strings.TrimSpace(value)); err != nil {
			return err
		}
	}
	return sc.Err()
}
