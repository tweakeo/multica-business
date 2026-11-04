package biz

import (
	"context"
	"encoding/json"
	"io/fs"
	"mime"
	"net/http"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/multica-ai/multica/server/internal/middleware"
)

// The library is what the company folder holds for people to read, not
// records: the systems of each area (N · Área/Sistemas/*.md) and the
// documents of Finanzas (Fiscal, Gestoría, Trámites, Registros). They are
// read and linked as they are; nothing here is turned into a record, and
// nothing here writes to the folder.

// --- Systems -------------------------------------------------------------------

type systemSection struct {
	Heading string `json:"heading"`
	Body    string `json:"body"`
}

type systemDoc struct {
	Path       string          `json:"path"`
	Title      string          `json:"title"`
	Summary    string          `json:"summary"` // the "> Área · Estado · Lo lleva…" line
	Status     string          `json:"status"`
	Owner      string          `json:"owner"`
	Intro      string          `json:"intro"`
	Sections   []systemSection `json:"sections"`
	ModifiedAt time.Time       `json:"modified_at"`
	Children   []systemDoc     `json:"children"`
}

// parseSystem splits a system note into its H1, the summary quote under it
// and its ## sections. Text is kept exactly as written.
func parseSystem(rel string, data []byte) systemDoc {
	_, body, ok := splitNote(data)
	if !ok {
		body = string(data)
	}
	doc := systemDoc{Path: rel, Title: strings.TrimSuffix(path.Base(rel), ".md"), Sections: []systemSection{}, Children: []systemDoc{}}
	var cur *systemSection
	var intro []string
	flush := func() {
		if cur != nil {
			cur.Body = strings.TrimSpace(cur.Body)
			doc.Sections = append(doc.Sections, *cur)
		}
	}
	for _, ln := range strings.Split(strings.ReplaceAll(body, "\r\n", "\n"), "\n") {
		switch {
		case strings.HasPrefix(ln, "# ") && cur == nil && len(intro) == 0 && doc.Summary == "":
			doc.Title = strings.TrimSpace(ln[2:])
		case strings.HasPrefix(ln, "## "):
			flush()
			cur = &systemSection{Heading: strings.TrimSpace(ln[3:])}
		case cur != nil:
			cur.Body += ln + "\n"
		case strings.HasPrefix(ln, "> ") && doc.Summary == "" && len(intro) == 0:
			doc.Summary = strings.TrimSpace(ln[2:])
		case strings.TrimSpace(ln) == "" && len(intro) == 0:
		default:
			intro = append(intro, ln)
		}
	}
	flush()
	doc.Intro = strings.TrimSpace(strings.Join(intro, "\n"))
	// "4 · Finanzas · Activo · Lo lleva Mika": the area prefix is "N · Área".
	parts := splitDots(doc.Summary)
	if len(parts) > 0 && areaPrefix.MatchString(parts[0]) {
		parts = parts[1:]
	}
	for _, p := range parts {
		low := strings.ToLower(p)
		switch {
		case strings.HasPrefix(low, "lo lleva"):
			doc.Owner = p
		case doc.Status == "":
			doc.Status = p
		}
	}
	return doc
}

var areaPrefix = regexp.MustCompile(`^\d+ · \S`)

// splitDots splits on " · " except inside "N · Área" (4 · Finanzas).
func splitDots(s string) []string {
	if strings.TrimSpace(s) == "" {
		return nil
	}
	const keep = "\x00"
	protected := areaRef.ReplaceAllString(s, "${1}"+keep+"${2}")
	var out []string
	for _, p := range strings.Split(protected, " · ") {
		out = append(out, strings.TrimSpace(strings.ReplaceAll(p, keep, " · ")))
	}
	return out
}

var areaRef = regexp.MustCompile(`((?:^|[\s(«"])\d) · (\p{Lu})`)

// Systems lists the systems of an area as the folder has them. A folder
// next to a system with the same name holds its procedures (children).
func (f *Folder) Systems(ctx context.Context, ws, area string) (map[string]any, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	out := map[string]any{"configured": root != "", "folder": "", "systems": []systemDoc{}}
	if root == "" {
		return out, nil
	}
	l, err := LoadLayout(root)
	if err != nil {
		return nil, invalid("%v", err)
	}
	name := l.Areas[area]
	if name == "" {
		return out, nil
	}
	dir := path.Join(name, "Sistemas")
	out["folder"] = dir
	read := func(rel string) (systemDoc, bool) {
		full := filepath.Join(root, filepath.FromSlash(rel))
		data, err := os.ReadFile(full)
		if err != nil {
			return systemDoc{}, false
		}
		d := parseSystem(rel, data)
		if st, err := os.Stat(full); err == nil {
			d.ModifiedAt = st.ModTime()
		}
		return d, true
	}
	entries, err := os.ReadDir(filepath.Join(root, filepath.FromSlash(dir)))
	if err != nil {
		return out, nil
	}
	docs := []systemDoc{}
	byName := map[string]int{}
	var subdirs []string
	for _, e := range entries {
		n := e.Name()
		if strings.HasPrefix(n, ".") {
			continue
		}
		if e.IsDir() {
			subdirs = append(subdirs, n)
			continue
		}
		if !strings.HasSuffix(n, ".md") {
			continue
		}
		if d, ok := read(path.Join(dir, n)); ok {
			byName[strings.TrimSuffix(n, ".md")] = len(docs)
			docs = append(docs, d)
		}
	}
	for _, sd := range subdirs {
		kids, _ := os.ReadDir(filepath.Join(root, filepath.FromSlash(path.Join(dir, sd))))
		var children []systemDoc
		for _, k := range kids {
			if k.IsDir() || strings.HasPrefix(k.Name(), ".") || !strings.HasSuffix(k.Name(), ".md") {
				continue
			}
			if d, ok := read(path.Join(dir, sd, k.Name())); ok {
				children = append(children, d)
			}
		}
		if len(children) == 0 {
			continue
		}
		sort.Slice(children, func(i, j int) bool { return children[i].Title < children[j].Title })
		if i, ok := byName[sd]; ok {
			docs[i].Children = children
		} else {
			docs = append(docs, children...)
		}
	}
	sort.SliceStable(docs, func(i, j int) bool { return docs[i].Title < docs[j].Title })
	out["systems"] = docs
	return out, nil
}

// --- Documents (Finanzas · Autónomo) --------------------------------------------

type libraryDoc struct {
	Path       string    `json:"path"`
	Name       string    `json:"name"`
	Group      string    `json:"group"` // Fiscal, Gestoría, Trámites, Registros
	Kind       string    `json:"kind"`  // Ingresos, Gastos, Modelos, Baja IT 2026…
	Detail     string    `json:"detail"`
	Year       int       `json:"year,omitempty"`
	Quarter    string    `json:"quarter,omitempty"`
	Date       string    `json:"date"`
	DateSource string    `json:"date_source"` // nombre | documento | metadatos | manual | archivo
	DateNote   string    `json:"date_note,omitempty"`
	Ext        string    `json:"ext"`
	Size       int64     `json:"size"`
	ModifiedAt time.Time `json:"modified_at"`
	Private    bool      `json:"private"`
	InCloud    bool      `json:"in_cloud"` // iCloud placeholder, not downloaded
	// The file sits in "Sin trimestre" and the quarter comes from the
	// document's date; the file is not moved.
	QuarterFromDate bool `json:"quarter_from_date,omitempty"`
}

// datesIndexFile, in Finanzas, holds the real date of the documents whose
// name has none (ruta,fecha,fuente,nota), read from the PDF text or metadata
// by scripts/tls/the-last-fechas.mjs or written by a person (fuente manual).
// The originals are never renamed.
const datesIndexFile = "Fechas de documentos.csv"

type indexedDate struct{ date, source, note string }

var reISODay = regexp.MustCompile(`^(20\d\d)-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$`)
var reISOMonth = regexp.MustCompile(`^(20\d\d)-(0[1-9]|1[0-2])$`)

// readDatesIndex maps a folder-relative path to its date. A missing or
// unreadable index only means the file dates are used.
func readDatesIndex(root, fin string) map[string]indexedDate {
	out := map[string]indexedDate{}
	reg, err := readRegister(filepath.Join(root, filepath.FromSlash(path.Join(fin, datesIndexFile))))
	if err != nil {
		return out
	}
	col := map[string]int{}
	for i, h := range reg.header {
		col[strings.TrimSpace(h)] = i
	}
	ri, ok1 := col["ruta"]
	fi, ok2 := col["fecha"]
	if !ok1 || !ok2 {
		return out
	}
	get := func(row []string, k string) string {
		if i, ok := col[k]; ok && i < len(row) {
			return strings.TrimSpace(row[i])
		}
		return ""
	}
	for _, row := range reg.rows {
		rel, date := strings.TrimSpace(row[ri]), strings.TrimSpace(row[fi])
		if rel == "" || !(reISODay.MatchString(date) || reISOMonth.MatchString(date)) {
			continue
		}
		src := get(row, "fuente")
		if src == "" || src == "archivo" {
			src = "manual"
		}
		out[rel] = indexedDate{date: date, source: src, note: get(row, "nota")}
	}
	return out
}

// documentGroups are the folders of Finanzas shown as documents.
var documentGroups = []string{"Fiscal", "Gestoría", "Trámites", "Registros"}

// packageExt are macOS bundles: a folder that is one document.
var packageExt = map[string]bool{".numbers": true, ".pages": true, ".key": true, ".app": true, ".rtfd": true, ".bundle": true}

var (
	reYear    = regexp.MustCompile(`^(19|20)\d\d$`)
	reQuarter = regexp.MustCompile(`^T[1-4]$`)
	reDay     = regexp.MustCompile(`(20\d\d)[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])`)
	reMonth   = regexp.MustCompile(`(20\d\d)[-_.](0[1-9]|1[0-2])\b`)
)

// Private reports whether rel is under a private path of the layout.
func (l Layout) Private(rel string) bool {
	rel = filepath.ToSlash(rel)
	for _, p := range l.Privado {
		p = l.expand(p)
		if rel == p || strings.HasPrefix(rel, p+"/") {
			return true
		}
	}
	return false
}

func classify(l Layout, rel string, size int64, mod time.Time, index map[string]indexedDate) libraryDoc {
	fin := l.Areas["finanzas"]
	parts := strings.Split(strings.TrimPrefix(rel, fin+"/"), "/")
	name := parts[len(parts)-1]
	cloud := false
	if strings.HasPrefix(name, ".") && strings.HasSuffix(name, ".icloud") {
		name, cloud = strings.TrimSuffix(strings.TrimPrefix(name, "."), ".icloud"), true
	}
	d := libraryDoc{Path: rel, Name: name, Group: parts[0], Ext: strings.TrimPrefix(strings.ToLower(path.Ext(name)), "."), Size: size, ModifiedAt: mod, InCloud: cloud, Private: l.Private(rel)}
	dirs := parts[1 : len(parts)-1]
	var rest []string
	for _, p := range dirs {
		switch {
		case d.Group == "Fiscal" && d.Year == 0 && reYear.MatchString(p):
			d.Year = atoiSafe(p)
		case d.Group == "Fiscal" && d.Quarter == "" && (reQuarter.MatchString(p) || p == "Sin trimestre"):
			d.Quarter = p
		default:
			rest = append(rest, p)
		}
	}
	if len(rest) > 0 {
		d.Kind = rest[0]
		d.Detail = strings.Join(rest[1:], " / ")
	}
	if d.Kind == "" {
		d.Kind = map[string]string{"Fiscal": "Resumen", "Gestoría": "General", "Trámites": "General", "Registros": "Registros"}[d.Group]
	}
	if m := reDay.FindStringSubmatch(name); m != nil {
		d.Date, d.DateSource = m[1]+"-"+m[2]+"-"+m[3], "nombre"
	} else if m := reMonth.FindStringSubmatch(name); m != nil {
		d.Date, d.DateSource = m[1]+"-"+m[2], "nombre"
	} else if ix, ok := index[rel]; ok {
		d.Date, d.DateSource, d.DateNote = ix.date, ix.source, ix.note
	} else {
		d.Date, d.DateSource = mod.Format("2006-01-02"), "archivo"
	}
	// A Fiscal document in "Sin trimestre" whose real date is known shows the
	// quarter of that date, when it is the year of its folder.
	if d.Quarter == "Sin trimestre" && d.DateSource != "archivo" {
		if m := reISODay.FindStringSubmatch(d.Date); m != nil && (d.Year == 0 || d.Year == atoiSafe(m[1])) {
			d.Year, d.Quarter, d.QuarterFromDate = atoiSafe(m[1]), "T"+string(rune('1'+(atoiSafe(m[2])-1)/3)), true
		}
	}
	return d
}

func atoiSafe(s string) int {
	n := 0
	for _, r := range s {
		n = n*10 + int(r-'0')
	}
	return n
}

// Documents lists Fiscal/, Gestoría/, Trámites/ and Registros/ of Finanzas.
// Agents never get private paths (the IT leave): that rule is the agents',
// the app shows them to the people of the company.
func (f *Folder) Documents(ctx context.Context, ws string, a Actor) (map[string]any, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	out := map[string]any{"configured": root != "", "folder": "", "groups": documentGroups, "documents": []libraryDoc{}}
	if root == "" {
		return out, nil
	}
	l, err := LoadLayout(root)
	if err != nil {
		return nil, invalid("%v", err)
	}
	fin := l.Areas["finanzas"]
	out["folder"] = fin
	out["dates_index"] = path.Join(fin, datesIndexFile)
	index := readDatesIndex(root, fin)
	docs := []libraryDoc{}
	for _, g := range documentGroups {
		base := filepath.Join(root, filepath.FromSlash(path.Join(fin, g)))
		_ = filepath.WalkDir(base, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			name := d.Name()
			isPkg := d.IsDir() && packageExt[strings.ToLower(filepath.Ext(name))]
			if d.IsDir() && !isPkg {
				if p != base && strings.HasPrefix(name, ".") {
					return filepath.SkipDir
				}
				return nil
			}
			if name == ".DS_Store" || (strings.HasPrefix(name, ".") && !strings.HasSuffix(name, ".icloud")) || strings.HasPrefix(name, "~$") {
				return nil
			}
			rel, _ := filepath.Rel(root, p)
			rel = filepath.ToSlash(rel)
			var size int64
			var mod time.Time
			if info, err := d.Info(); err == nil {
				size, mod = info.Size(), info.ModTime()
			}
			if isPkg {
				size = dirSize(p)
			}
			doc := classify(l, rel, size, mod, index)
			if !(doc.Private && a.Type == "agent") {
				docs = append(docs, doc)
			}
			if isPkg {
				return filepath.SkipDir
			}
			return nil
		})
	}
	sort.SliceStable(docs, func(i, j int) bool {
		if docs[i].Date != docs[j].Date {
			return docs[i].Date > docs[j].Date
		}
		return docs[i].Path < docs[j].Path
	})
	out["documents"] = docs
	return out, nil
}

func dirSize(p string) int64 {
	var n int64
	_ = filepath.WalkDir(p, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if info, err := d.Info(); err == nil {
				n += info.Size()
			}
		}
		return nil
	})
	return n
}

// --- Opening the original --------------------------------------------------------

// resolveInFolder turns a folder-relative path into an absolute one that is
// guaranteed to stay inside the company folder (no "..", no symlink out, no
// hidden .tls state).
func (f *Folder) resolveInFolder(ctx context.Context, ws string, a Actor, rel string) (string, Layout, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	if root == "" {
		return "", Layout{}, invalid("La empresa no tiene carpeta configurada")
	}
	l, err := LoadLayout(root)
	if err != nil {
		return "", Layout{}, invalid("%v", err)
	}
	rel = filepath.ToSlash(filepath.Clean("/" + rel))[1:]
	if rel == "" || strings.HasPrefix(rel, ".tls") || strings.Contains("/"+rel+"/", "/../") {
		return "", l, errf(400, "bad_path", "Ruta no válida")
	}
	if a.Type == "agent" && l.Private(rel) {
		return "", l, errf(403, "private", "Documento privado: no disponible para agentes")
	}
	full := filepath.Join(root, filepath.FromSlash(rel))
	realRoot, err1 := filepath.EvalSymlinks(root)
	realFull, err2 := filepath.EvalSymlinks(full)
	if err1 != nil || err2 != nil {
		return "", l, errf(404, "not_found", "No existe en la carpeta")
	}
	if r, err := filepath.Rel(realRoot, realFull); err != nil || r == ".." || strings.HasPrefix(r, "../") {
		return "", l, errf(400, "bad_path", "Ruta fuera de la carpeta")
	}
	return full, l, nil
}

// serveFile streams the original file (inline) so the app can open it.
func (s *Service) serveFile(w http.ResponseWriter, r *http.Request) {
	ws := middleware.WorkspaceIDFromContext(r.Context())
	if ws == "" {
		writeErr(w, errf(http.StatusBadRequest, "workspace_required", "Falta el espacio de trabajo"))
		return
	}
	full, _, err := s.Folder.resolveInFolder(r.Context(), ws, actorFrom(r), r.URL.Query().Get("path"))
	if err != nil {
		writeErr(w, err)
		return
	}
	st, err := os.Stat(full)
	if err != nil {
		writeErr(w, errf(404, "not_found", "No existe en la carpeta"))
		return
	}
	if st.IsDir() {
		writeErr(w, errf(415, "is_folder", "Es un paquete o carpeta: ábrelo en Finder"))
		return
	}
	ct := mime.TypeByExtension(strings.ToLower(filepath.Ext(full)))
	switch strings.ToLower(filepath.Ext(full)) {
	case ".md", ".csv", ".txt":
		ct = "text/plain; charset=utf-8"
	}
	if ct != "" {
		w.Header().Set("Content-Type", ct)
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	http.ServeFile(w, r, full)
}

// postReveal shows the original in Finder. Only for people, and only when the
// server runs on the Mac that holds the folder.
func (s *Service) postReveal(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	if a.Type != "member" {
		return nil, errf(403, "forbidden", "Solo una persona abre la carpeta")
	}
	if runtime.GOOS != "darwin" {
		return nil, errf(501, "unsupported", "Solo disponible en macOS")
	}
	var in struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		return nil, invalid("Cuerpo no legible")
	}
	full, _, err := s.Folder.resolveInFolder(ctx, ws, a, in.Path)
	if err != nil {
		return nil, err
	}
	if err := exec.CommandContext(ctx, "/usr/bin/open", "-R", full).Run(); err != nil {
		return nil, errf(500, "open_failed", "No se pudo abrir Finder: %v", err)
	}
	return map[string]any{"ok": true}, nil
}

func (s *Service) libraryRoutes(r chi.Router) {
	r.Get("/systems", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
		return s.Folder.Systems(ctx, ws, r.URL.Query().Get("area"))
	}))
	r.Get("/documents", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
		return s.Folder.Documents(ctx, ws, a)
	}))
	r.Get("/folder/file", s.serveFile)
	r.Post("/folder/reveal", s.handle(s.postReveal))
}
