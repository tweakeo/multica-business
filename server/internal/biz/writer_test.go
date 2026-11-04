package biz

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/google/uuid"
)

// Tests never touch the real ~/Library/Application Support/TLS.
func TestMain(m *testing.M) {
	if os.Getenv("TLS_STATE_DIR") == "" {
		dir, err := os.MkdirTemp("", "tls-state-*")
		if err != nil {
			panic(err)
		}
		os.Setenv("TLS_STATE_DIR", dir)
		code := m.Run()
		os.RemoveAll(dir)
		os.Exit(code)
	}
	os.Exit(m.Run())
}

func TestSecondProcessCannotTakeTheFolderLock(t *testing.T) {
	root := t.TempDir()
	p := lockPath(root)
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		t.Fatal(err)
	}
	other, err := os.OpenFile(p, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	defer other.Close()
	if err := tryLock(other); err != nil {
		t.Fatal(err)
	}
	var nw *ErrNotWriter
	if err := holdLock(root); !errors.As(err, &nw) {
		t.Fatalf("lock held elsewhere, got %v", err)
	}
}

func TestOnlyTheOwnerWritesTheFolder(t *testing.T) {
	owner1 := newFixture(t)
	dir := targetCopy(t)
	owner1.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()
	if _, err := owner1.s.Folder.ExportAll(ctx, owner1.ws); err != nil {
		t.Fatal(err)
	}
	claim, err := readWriter(dir)
	if err != nil || claim == nil || claim.WorkspaceID != owner1.ws {
		t.Fatalf("claim: %+v %v", claim, err)
	}

	// A second workspace (the demo, say) pointed at the same folder only reads.
	demo := newFixture(t)
	demo.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	before := snapshotTree(t, dir)
	if _, err := demo.s.Folder.ExportAll(ctx, demo.ws); err == nil {
		t.Fatal("a second workspace exported into an owned folder")
	}
	demo.must(owner, "decision.create", map[string]any{"area": "direccion", "title": "Intrusa", "decision": "x", "why": "y", "purpose": "z"})
	demo.s.Folder.FlushPending(ctx, demo.ws)
	if _, err := demo.s.Folder.Rebuild(ctx, demo.ws, true); err == nil {
		t.Fatal("a second workspace imported an owned folder")
	}
	if _, err := demo.s.Folder.Rebuild(ctx, demo.ws, false); err != nil {
		t.Fatalf("preview must stay available: %v", err)
	}
	if after := snapshotTree(t, dir); len(after) != len(before) {
		t.Fatalf("folder changed: %d → %d files", len(before), len(after))
	} else {
		for k, v := range before {
			if after[k] != v {
				t.Fatalf("%s changed", k)
			}
		}
	}
	if demo.s.Folder.PendingCount(ctx, demo.ws) == 0 {
		t.Fatal("refused writes must stay pending in the journal")
	}
	st, err := demo.s.Folder.Status(ctx, demo.ws)
	if err != nil {
		t.Fatal(err)
	}
	if w := st["escritor"].(map[string]any); w["es_esta"] != false {
		t.Fatalf("status escritor: %v", w)
	}

	// Another installation (another Mac) is refused too.
	claim.Instalacion = uuid.NewString()
	writeFile(t, dir, writerFile, mustJSON(claim))
	if _, err := owner1.s.Folder.ExportAll(ctx, owner1.ws); err == nil {
		t.Fatal("folder owned by another installation was written")
	}
}

func snapshotTree(t *testing.T, root string) map[string]string {
	t.Helper()
	out := map[string]string{}
	_ = filepath.WalkDir(root, func(p string, d os.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		b, _ := os.ReadFile(p)
		rel, _ := filepath.Rel(root, p)
		out[rel] = hashBytes(b)
		return nil
	})
	return out
}
