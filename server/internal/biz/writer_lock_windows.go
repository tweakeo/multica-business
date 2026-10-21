//go:build windows

package biz

import "os"

// TLS runs on macOS; on Windows the folder marker alone guards the folder.
func tryLock(*os.File) error { return nil }
