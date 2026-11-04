package handler

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func writeLocalLink(t *testing.T, file, token string, expires time.Time, email string) {
	t.Helper()
	sum := sha256.Sum256([]byte(token))
	if err := os.WriteFile(file, []byte(fmt.Sprintf("%s %d %s\n", hex.EncodeToString(sum[:]), expires.Unix(), email)), 0o600); err != nil {
		t.Fatal(err)
	}
}

func localLinkRequest(token, remote, forwarded string) *httptest.ResponseRecorder {
	req := httptest.NewRequest("GET", "/auth/local-link?t="+token+"&next=/the-last/empresa", nil)
	req.RemoteAddr = remote
	if forwarded != "" {
		req.Header.Set("X-Forwarded-For", forwarded)
	}
	w := httptest.NewRecorder()
	testHandler.LocalLink(w, req)
	return w
}

// The local link signs in once, within its minute, only from this machine and
// only when the instance enabled it.
func TestLocalLinkIsOneTimeLoopbackOnly(t *testing.T) {
	if testHandler == nil {
		t.Skip("database not available")
	}
	file := filepath.Join(t.TempDir(), "enlace")
	now := time.Now()

	t.Setenv("TLS_LOCAL_LOGIN_FILE", "")
	writeLocalLink(t, file, "tok", now.Add(time.Minute), handlerTestEmail)
	if w := localLinkRequest("tok", "127.0.0.1:5000", ""); w.Code != http.StatusNotFound {
		t.Fatalf("disabled: got %d", w.Code)
	}

	t.Setenv("TLS_LOCAL_LOGIN_FILE", file)
	cases := []struct {
		name, token, remote, forwarded string
		expires                        time.Time
	}{
		{"from the network", "tok", "192.168.1.20:5000", "", now.Add(time.Minute)},
		{"forwarded from the network", "tok", "127.0.0.1:5000", "192.168.1.20", now.Add(time.Minute)},
		{"wrong token", "otro", "127.0.0.1:5000", "", now.Add(time.Minute)},
		{"expired", "tok", "127.0.0.1:5000", "", now.Add(-time.Second)},
		{"longer than a minute", "tok", "127.0.0.1:5000", "", now.Add(10 * time.Minute)},
	}
	for _, c := range cases {
		writeLocalLink(t, file, "tok", c.expires, handlerTestEmail)
		if w := localLinkRequest(c.token, c.remote, c.forwarded); w.Code != http.StatusNotFound {
			t.Errorf("%s: got %d", c.name, w.Code)
		}
	}

	writeLocalLink(t, file, "tok", now.Add(time.Minute), handlerTestEmail)
	w := localLinkRequest("tok", "[::1]:5000", "127.0.0.1")
	if w.Code != http.StatusSeeOther || w.Header().Get("Location") != "/the-last/empresa" || len(w.Result().Cookies()) == 0 {
		t.Fatalf("valid link: %d %q", w.Code, w.Header().Get("Location"))
	}
	if _, err := os.Stat(file); !os.IsNotExist(err) {
		t.Fatal("the link file was not consumed")
	}
	if w := localLinkRequest("tok", "127.0.0.1:5000", ""); w.Code != http.StatusNotFound {
		t.Fatalf("reused link: got %d", w.Code)
	}
}
