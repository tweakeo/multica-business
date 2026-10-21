package handler

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/multica-ai/multica/server/internal/auth"
)

// localLinkMaxAge bounds a link however the file was written.
const localLinkMaxAge = 60 * time.Second

// LocalLink signs in from a one-time link made on this machine (TLS: the
// production company runs on 127.0.0.1 only; scripts/tls/the-last.sh abrir).
// It is off unless TLS_LOCAL_LOGIN_FILE is set. The script writes that file
// (0600) with "<sha256 of the token> <unix expiry> <email>"; the link carries
// the token. The file is removed before anything is checked, so a link works
// once, for at most 60 seconds, only from loopback and only for a user that
// already exists.
func (h *Handler) LocalLink(w http.ResponseWriter, r *http.Request) {
	file := os.Getenv("TLS_LOCAL_LOGIN_FILE")
	deny := func() { writeError(w, http.StatusNotFound, "not found") }
	if file == "" || !loopbackRequest(r) {
		deny()
		return
	}
	data, err := os.ReadFile(file)
	if err != nil {
		deny()
		return
	}
	_ = os.Remove(file)
	fields := strings.Fields(string(data))
	token := r.URL.Query().Get("t")
	if len(fields) != 3 || token == "" {
		deny()
		return
	}
	sum := sha256.Sum256([]byte(token))
	if subtle.ConstantTimeCompare([]byte(hex.EncodeToString(sum[:])), []byte(fields[0])) != 1 {
		deny()
		return
	}
	exp, err := strconv.ParseInt(fields[1], 10, 64)
	now := time.Now()
	if err != nil || now.After(time.Unix(exp, 0)) || time.Unix(exp, 0).Sub(now) > localLinkMaxAge {
		deny()
		return
	}
	user, err := h.Queries.GetUserByEmail(r.Context(), strings.ToLower(fields[2]))
	if err != nil {
		deny()
		return
	}
	token, err = h.issueJWT(user)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to generate token")
		return
	}
	if err := auth.SetAuthCookies(w, token); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to set session")
		return
	}
	next := r.URL.Query().Get("next")
	if !strings.HasPrefix(next, "/") || strings.HasPrefix(next, "//") {
		next = "/"
	}
	w.Header().Set("Cache-Control", "no-store")
	http.Redirect(w, r, next, http.StatusSeeOther)
}

// loopbackRequest is true when the connection and every proxy hop it reports
// come from this machine.
func loopbackRequest(r *http.Request) bool {
	isLoop := func(s string) bool {
		s = strings.TrimSpace(s)
		if host, _, err := net.SplitHostPort(s); err == nil {
			s = host
		}
		ip := net.ParseIP(strings.Trim(s, "[]"))
		return ip != nil && ip.IsLoopback()
	}
	if !isLoop(r.RemoteAddr) {
		return false
	}
	for _, h := range []string{"X-Forwarded-For", "X-Real-Ip"} {
		for _, v := range strings.Split(r.Header.Get(h), ",") {
			if strings.TrimSpace(v) != "" && !isLoop(v) {
				return false
			}
		}
	}
	return true
}
