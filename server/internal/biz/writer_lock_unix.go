//go:build !windows

package biz

import (
	"os"
	"syscall"
)

func tryLock(fh *os.File) error {
	return syscall.Flock(int(fh.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
}
