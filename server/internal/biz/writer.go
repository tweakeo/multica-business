package biz

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// Single writer. A company folder (for The Last, a synced iCloud folder) is
// written by exactly one TLS: one installation, one workspace, one process.
//
//   - <carpeta>/.tls/escritor.json names the owner (installation + workspace).
//     It travels with the folder, so another Mac or the demo workspace that
//     points at the same folder reads it and refuses to write.
//   - <estado>/locks/<hash>.lock is held with flock for the life of the
//     process, so two servers on this Mac never write the same folder.
//
// Everything that is not the company's own content (database, journal,
// locks, installation id) lives in the state directory, outside the folder:
// TLS_STATE_DIR, or ~/Library/Application Support/TLS.

const writerFile = ".tls/escritor.json"

type writerClaim struct {
	Instalacion string `json:"instalacion"`
	Equipo      string `json:"equipo"`
	WorkspaceID string `json:"workspace_id"`
	Empresa     string `json:"empresa"`
	Desde       string `json:"desde"`
}

// StateDir holds what must never live in the company folder.
func StateDir() string {
	if d := strings.TrimSpace(os.Getenv("TLS_STATE_DIR")); d != "" {
		return d
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return filepath.Join(os.TempDir(), "TLS")
	}
	return filepath.Join(home, "Library", "Application Support", "TLS")
}

var (
	installOnce sync.Once
	installID   string
	installErr  error
)

// installationID is created once per state directory: a copy of the folder
// on another Mac never shares it.
func installationID() (string, error) {
	installOnce.Do(func() {
		p := filepath.Join(StateDir(), "instalacion.json")
		var v struct {
			ID string `json:"id"`
		}
		if b, err := os.ReadFile(p); err == nil && json.Unmarshal(b, &v) == nil && v.ID != "" {
			installID = v.ID
			return
		}
		if err := os.MkdirAll(StateDir(), 0o700); err != nil {
			installErr = err
			return
		}
		v.ID = uuid.NewString()
		b, _ := json.MarshalIndent(v, "", "  ")
		if installErr = atomicWrite(p, append(b, '\n')); installErr == nil {
			installID = v.ID
		}
	})
	return installID, installErr
}

// ErrNotWriter means another TLS owns the folder; writes stay pending in the
// journal and nothing in the folder changes.
type ErrNotWriter struct{ Msg string }

func (e *ErrNotWriter) Error() string { return e.Msg }

var (
	heldMu sync.Mutex
	held   = map[string]*os.File{} // root → open lock file (flock held)
)

func lockPath(root string) string {
	s := sha256.Sum256([]byte(filepath.Clean(root)))
	return filepath.Join(StateDir(), "locks", hex.EncodeToString(s[:8])+".lock")
}

// writeRoot returns the folder root only if this TLS may write it, claiming
// a folder that has no owner yet.
func (f *Folder) writeRoot(ctx context.Context, ws string) (string, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	if root == "" {
		return "", nil
	}
	if err := f.claim(ctx, ws, root); err != nil {
		return "", err
	}
	return root, nil
}

func (f *Folder) claim(ctx context.Context, ws, root string) error {
	if err := holdLock(root); err != nil {
		return err
	}
	inst, err := installationID()
	if err != nil {
		return fmt.Errorf("estado de TLS: %v", err)
	}
	cur, err := readWriter(root)
	if err != nil {
		return &ErrNotWriter{Msg: fmt.Sprintf("%s ilegible: %v; no se escribe hasta corregirlo", writerFile, err)}
	}
	if cur != nil {
		if cur.Instalacion == inst && cur.WorkspaceID == ws {
			return nil
		}
		return &ErrNotWriter{Msg: fmt.Sprintf("La carpeta la escribe otra TLS (%s, empresa %q, desde %s). Esta solo la lee.", cur.Equipo, cur.Empresa, cur.Desde)}
	}
	var name string
	_ = f.svc.Pool.QueryRow(ctx, `SELECT name FROM workspace WHERE id=$1`, ws).Scan(&name)
	host, _ := os.Hostname()
	c := writerClaim{Instalacion: inst, Equipo: host, WorkspaceID: ws, Empresa: name, Desde: time.Now().UTC().Format(time.RFC3339)}
	b, _ := json.MarshalIndent(c, "", "  ")
	return atomicWrite(filepath.Join(root, filepath.FromSlash(writerFile)), append(b, '\n'))
}

func readWriter(root string) (*writerClaim, error) {
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(writerFile)))
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var c writerClaim
	if err := json.Unmarshal(b, &c); err != nil {
		return nil, err
	}
	if c.Instalacion == "" || c.WorkspaceID == "" {
		return nil, fmt.Errorf("faltan instalacion o workspace_id")
	}
	return &c, nil
}

func holdLock(root string) error {
	key := filepath.Clean(root)
	heldMu.Lock()
	defer heldMu.Unlock()
	if _, ok := held[key]; ok {
		return nil
	}
	p := lockPath(key)
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return fmt.Errorf("estado de TLS: %v", err)
	}
	fh, err := os.OpenFile(p, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fmt.Errorf("estado de TLS: %v", err)
	}
	if err := tryLock(fh); err != nil {
		fh.Close()
		return &ErrNotWriter{Msg: "Otro proceso de TLS en este Mac ya escribe en esta carpeta. Esta instancia solo la lee."}
	}
	_ = fh.Truncate(0)
	_, _ = fmt.Fprintf(fh, "%d %s\n", os.Getpid(), key)
	held[key] = fh
	return nil
}

// writerStatus is shown in /folder/status.
func (f *Folder) writerStatus(ctx context.Context, ws, root string) map[string]any {
	out := map[string]any{"estado": StateDir()}
	cur, err := readWriter(root)
	switch {
	case err != nil:
		out["error"] = err.Error()
	case cur == nil:
		out["propietario"] = nil
	default:
		inst, _ := installationID()
		out["propietario"] = cur
		out["es_esta"] = cur.Instalacion == inst && cur.WorkspaceID == ws
	}
	return out
}
