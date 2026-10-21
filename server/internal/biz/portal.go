package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"gopkg.in/yaml.v3"
)

// The Portal Cliente is read from the folder of each project, as a person
// keeps it (3 · Entrega/Sistemas/Portal Cliente.md):
//
//   - Proyectos/<proyecto>/Proyecto.md   title, client, estado; `demo: true` marks an example
//   - Proyectos/<proyecto>/Portal.md     «## Viaje» table (S1–S9) and «## Tareas del cliente» checklist
//   - Proyectos/<proyecto>/Incidencias.md table of incidents (PT1); the form appends rows
//   - Proyectos/<proyecto>/…             internal kit: a file or folder named «S<n> …»
//   - Portal Cliente/<proyecto>/…        what the client sees; «S<n> …» belongs to that session
//
// Nothing is a record. The only write is a new incident row, after a copy of
// the file in the state directory.

const (
	portalFile    = "Portal.md"
	incidentsFile = "Incidencias.md"
)

// defaultSessions is the journey of Sesiones de implantación; the covers in
// Recursos/Sesiones/portadas («S1 · Diagnóstico.png») rename them.
var defaultSessions = []string{"Diagnóstico", "Estructura de negocio", "Flujos personales", "Decisiones estratégicas", "Datos reales y uso operativo",
	"Primer uso real e incidencias", "Ajustes y simplificación", "Madurez y preparación de cierre", "Validación final"}

var (
	reSessionRef  = regexp.MustCompile(`^S([1-9])(?:\b|[ ·._-])`)
	reSessionCell = regexp.MustCompile(`\bS([1-9])\b`)
	reDue         = regexp.MustCompile(`(?i)^vence\s+(20\d\d-\d\d-\d\d)$`)
	reTaskLine    = regexp.MustCompile(`^\s*[-*]\s+\[([ xX])\]\s+(.*)$`)
)

type portalDoc struct {
	Path       string    `json:"path"`
	Name       string    `json:"name"`
	Ext        string    `json:"ext"`
	Size       int64     `json:"size"`
	ModifiedAt time.Time `json:"modified_at"`
	Session    string    `json:"session"`
	Client     bool      `json:"client"` // in Portal Cliente/: the client sees it
	InCloud    bool      `json:"in_cloud"`
}

type portalSession struct {
	Code    string      `json:"code"`
	Name    string      `json:"name"`
	Status  string      `json:"status"` // as written; "" = not registered
	State   string      `json:"state"`  // pendiente | programada | preparada | hecha | no_incluida
	Date    string      `json:"date"`
	Summary string      `json:"summary"`
	Note    string      `json:"note,omitempty"` // internal
	Cover   string      `json:"cover,omitempty"`
	Kit     []portalDoc `json:"kit"`
	Current bool        `json:"current"`
}

type portalTask struct {
	Text    string `json:"text"`
	Done    bool   `json:"done"`
	Session string `json:"session"`
	Due     string `json:"due"`
	Overdue bool   `json:"overdue"`
}

type portalIncident struct {
	ID          string `json:"id"`
	Date        string `json:"date"`
	Reporter    string `json:"reporter"`
	Email       string `json:"email,omitempty"`
	Type        string `json:"type"`
	Severity    string `json:"severity"`
	Status      string `json:"status"`
	Description string `json:"description"`
	Owner       string `json:"owner,omitempty"`      // internal
	Resolution  string `json:"resolution,omitempty"` // internal
	Open        bool   `json:"open"`
	AgeDays     int    `json:"age_days"`
}

type portalProgress struct {
	SessionsDone  int    `json:"sessions_done"`
	SessionsTotal int    `json:"sessions_total"`
	TasksDone     int    `json:"tasks_done"`
	TasksTotal    int    `json:"tasks_total"`
	IncidentsOpen int    `json:"incidents_open"`
	Percent       int    `json:"percent"`
	Current       string `json:"current"`
}

type portalProject struct {
	Slug          string           `json:"slug"`
	Path          string           `json:"path"`
	Title         string           `json:"title"`
	Client        string           `json:"client"`
	State         string           `json:"state"`
	Demo          bool             `json:"demo"`
	Closed        bool             `json:"closed"`
	HasPortal     bool             `json:"has_portal"`
	PortalPath    string           `json:"portal_path"`
	IncidentsPath string           `json:"incidents_path"`
	ClientFolder  string           `json:"client_folder"`
	Sessions      []portalSession  `json:"sessions"`
	Tasks         []portalTask     `json:"tasks"`
	Incidents     []portalIncident `json:"incidents"`
	Documents     []portalDoc      `json:"documents"` // client documents outside any session
	Progress      portalProgress   `json:"progress"`
	Intro         string           `json:"intro,omitempty"` // free text of Portal.md, internal
}

func (l Layout) projectsDir() string     { return path.Join(l.Areas["entrega"], "Proyectos") }
func (l Layout) clientPortalDir() string { return path.Join(l.Areas["entrega"], "Portal Cliente") }

func sessionState(s string) string {
	k := headerKey(s)
	switch {
	case k == "":
		return "pendiente"
	case strings.HasPrefix(k, "hech"), strings.HasPrefix(k, "complet"), strings.HasPrefix(k, "realiz"):
		return "hecha"
	case strings.HasPrefix(k, "no incl"), strings.HasPrefix(k, "fuera"), strings.HasPrefix(k, "saltad"):
		return "no_incluida"
	case strings.HasPrefix(k, "kit"), strings.HasPrefix(k, "prepar"):
		return "preparada"
	case strings.HasPrefix(k, "program"), strings.HasPrefix(k, "agend"):
		return "programada"
	}
	return "pendiente"
}

func incidentOpen(status string) bool {
	k := headerKey(status)
	return !(strings.HasPrefix(k, "resuelt") || strings.HasPrefix(k, "cerrad"))
}

// mdCells splits a table row like tableCells, keeping escaped pipes (\|) inside the cell.
func mdCells(line string) []string {
	const esc = "\x00"
	cells := tableCells(strings.ReplaceAll(line, `\|`, esc))
	for i := range cells {
		cells[i] = strings.ReplaceAll(cells[i], esc, `\|`)
	}
	return cells
}

// mdTable is the first Markdown table whose header has the given column.
type mdTable struct {
	lines        []string
	header, last int // line indexes; header < 0 = none
	cols         map[string]int
}

func findTable(text, must string) mdTable {
	t := mdTable{lines: strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n"), header: -1, last: -1}
	for i, ln := range t.lines {
		if t.header >= 0 {
			if mdCells(ln) == nil {
				break
			}
			t.last = i
			continue
		}
		cells := mdCells(ln)
		if cells == nil {
			continue
		}
		cols := map[string]int{}
		for j, c := range cells {
			cols[headerKey(c)] = j
		}
		if _, ok := cols[must]; ok {
			t.header, t.last, t.cols = i, i, cols
		}
	}
	return t
}

// col returns the cell of the first column whose key starts with any prefix.
func (t mdTable) col(cells []string, prefixes ...string) string {
	for _, p := range prefixes {
		for k, j := range t.cols {
			if strings.HasPrefix(k, p) && j < len(cells) {
				return strings.TrimSpace(strings.ReplaceAll(cells[j], `\|`, "|"))
			}
		}
	}
	return ""
}

func (t mdTable) rows() [][]string {
	var out [][]string
	for i := t.header + 1; i <= t.last && t.header >= 0; i++ {
		cells := mdCells(t.lines[i])
		if len(cells) == 0 || strings.Trim(strings.Join(cells, ""), "-: ") == "" {
			continue // separator row
		}
		out = append(out, cells)
	}
	return out
}

// parsePortal reads the journey table, the client checklist and the free text.
func parsePortal(text string, now time.Time) (map[string]portalSession, []portalTask, string) {
	sessions := map[string]portalSession{}
	t := findTable(text, "sesion")
	for _, cells := range t.rows() {
		ref := t.col(cells, "sesion")
		m := reSessionCell.FindStringSubmatch(ref)
		if m == nil {
			continue
		}
		code := "S" + m[1]
		name := strings.TrimSpace(strings.TrimLeft(strings.TrimPrefix(strings.TrimSpace(ref), code), " ·-"))
		status := t.col(cells, "estado")
		sessions[code] = portalSession{Code: code, Name: name, Status: status, State: sessionState(status),
			Date: t.col(cells, "fecha"), Summary: t.col(cells, "resumen", "para el cliente"), Note: t.col(cells, "nota")}
	}
	var tasks []portalTask
	var intro []string
	section := ""
	for i, ln := range strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n") {
		trim := strings.TrimSpace(ln)
		if strings.HasPrefix(trim, "## ") {
			section = headerKey(trim[3:])
			continue
		}
		if strings.HasPrefix(trim, "# ") || (t.header >= 0 && i >= t.header && i <= t.last) {
			continue
		}
		if strings.HasPrefix(section, "tareas") {
			m := reTaskLine.FindStringSubmatch(ln)
			if m == nil {
				continue
			}
			task := portalTask{Done: m[1] != " "}
			var words []string
			for _, part := range splitDots(m[2]) {
				if d := reDue.FindStringSubmatch(part); d != nil {
					task.Due = d[1]
				} else if s := reSessionCell.FindStringSubmatch(part); s != nil && len(part) <= 3 {
					task.Session = "S" + s[1]
				} else {
					words = append(words, part)
				}
			}
			task.Text = strings.Join(words, " · ")
			task.Overdue = !task.Done && task.Due != "" && task.Due < now.Format("2006-01-02")
			tasks = append(tasks, task)
			continue
		}
		if section == "" || strings.HasPrefix(section, "notas") {
			intro = append(intro, ln)
		}
	}
	return sessions, tasks, strings.TrimSpace(strings.Join(intro, "\n"))
}

func parseIncidents(text string, now time.Time) []portalIncident {
	t := findTable(text, "id")
	out := []portalIncident{}
	for _, cells := range t.rows() {
		in := portalIncident{ID: t.col(cells, "id"), Date: t.col(cells, "fecha"), Reporter: t.col(cells, "quien", "reporta"), Email: t.col(cells, "email"),
			Type: t.col(cells, "tipo"), Severity: t.col(cells, "severidad"), Status: t.col(cells, "estado"), Description: t.col(cells, "descripcion"),
			Owner: t.col(cells, "responsable"), Resolution: t.col(cells, "resolucion", "notas")}
		if in.ID == "" && in.Description == "" {
			continue
		}
		in.Open = incidentOpen(in.Status)
		if d, err := time.Parse("2006-01-02", in.Date); err == nil {
			in.AgeDays = int(dateOnly(now).Sub(d).Hours() / 24)
		}
		out = append(out, in)
	}
	return out
}

// projectFront reads Proyecto.md: H1, «Cliente: [Nombre](…)», estado, demo.
func projectFront(data []byte) (title, client, state string, demo bool) {
	fm, body, ok := splitNote(data)
	if !ok {
		body = string(data)
	}
	front := map[string]any{}
	if ok {
		_ = yaml.Unmarshal([]byte(fm), &front)
	}
	state = str(front["estado"])
	demo, _ = front["demo"].(bool)
	for _, ln := range strings.Split(body, "\n") {
		trim := strings.TrimSpace(ln)
		switch {
		case title == "" && strings.HasPrefix(trim, "# "):
			title = strings.TrimSpace(trim[2:])
		case client == "" && strings.HasPrefix(trim, "Cliente:"):
			client = strings.TrimSpace(strings.TrimPrefix(trim, "Cliente:"))
			if m := regexp.MustCompile(`^\[([^\]]+)\]`).FindStringSubmatch(client); m != nil {
				client = m[1]
			}
		}
	}
	return
}

func closedState(s string) bool {
	k := headerKey(s)
	return strings.HasPrefix(k, "cerrad") || strings.HasPrefix(k, "archivad") || strings.HasPrefix(k, "cancelad") || strings.HasPrefix(k, "complet")
}

// sessionOf finds S<n> in the path below the project or portal folder.
func sessionOf(rel string) string {
	for _, seg := range strings.Split(rel, "/") {
		if m := reSessionRef.FindStringSubmatch(seg + " "); m != nil {
			return "S" + m[1]
		}
	}
	return ""
}

// walkDocs lists the files under dir (folder-relative), packages as one file.
func walkDocs(root, dir string, skip map[string]bool) []portalDoc {
	var out []portalDoc
	base := filepath.Join(root, filepath.FromSlash(dir))
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
		inner := strings.TrimPrefix(rel, dir+"/")
		if skip[inner] {
			return nil
		}
		cloud := false
		if strings.HasPrefix(name, ".") && strings.HasSuffix(name, ".icloud") {
			name, cloud = strings.TrimSuffix(strings.TrimPrefix(name, "."), ".icloud"), true
		}
		doc := portalDoc{Path: rel, Name: name, Ext: strings.TrimPrefix(strings.ToLower(path.Ext(name)), "."), Session: sessionOf(inner), InCloud: cloud}
		if info, err := d.Info(); err == nil {
			doc.Size, doc.ModifiedAt = info.Size(), info.ModTime()
		}
		if isPkg {
			doc.Size = dirSize(p)
			out = append(out, doc)
			return filepath.SkipDir
		}
		out = append(out, doc)
		return nil
	})
	sort.SliceStable(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out
}

// sessionCatalog names S1–S9 from the covers, falling back to the defaults.
func sessionCatalog(root string, l Layout) ([]string, map[string]string) {
	names := append([]string(nil), defaultSessions...)
	covers := map[string]string{}
	dir := path.Join(l.Areas["entrega"], "Recursos", "Sesiones", "portadas")
	entries, _ := os.ReadDir(filepath.Join(root, filepath.FromSlash(dir)))
	for _, e := range entries {
		m := reSessionRef.FindStringSubmatch(e.Name())
		if m == nil || e.IsDir() {
			continue
		}
		n, _ := strconv.Atoi(m[1])
		covers["S"+m[1]] = path.Join(dir, e.Name())
		if name := strings.TrimSpace(strings.TrimLeft(strings.TrimSuffix(e.Name(), path.Ext(e.Name()))[2:], " ·-")); name != "" {
			names[n-1] = name
		}
	}
	return names, covers
}

// readPortal builds one project's portal. The client view drops what is
// internal: notes, owners, resolutions, emails and the project's own kit.
func readPortal(root string, l Layout, slug string, client bool, now time.Time) (*portalProject, error) {
	if slug == "" || strings.ContainsAny(slug, `/\`) || strings.HasPrefix(slug, ".") {
		return nil, errf(400, "bad_path", "Proyecto no válido")
	}
	dir := path.Join(l.projectsDir(), slug)
	data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(path.Join(dir, "Proyecto.md"))))
	if err != nil {
		return nil, errf(404, "not_found", "No existe el expediente %s", dir)
	}
	p := &portalProject{Slug: slug, Path: path.Join(dir, "Proyecto.md"), PortalPath: path.Join(dir, portalFile), IncidentsPath: path.Join(dir, incidentsFile),
		ClientFolder: path.Join(l.clientPortalDir(), slug), Tasks: []portalTask{}, Incidents: []portalIncident{}, Documents: []portalDoc{}}
	p.Title, p.Client, p.State, p.Demo = projectFront(data)
	if p.Title == "" {
		p.Title = slug
	}
	p.Closed = closedState(p.State)

	registered := map[string]portalSession{}
	if text, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(p.PortalPath))); err == nil {
		p.HasPortal = true
		registered, p.Tasks, p.Intro = parsePortal(string(text), now)
		if p.Tasks == nil {
			p.Tasks = []portalTask{}
		}
	}
	if text, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(p.IncidentsPath))); err == nil {
		p.Incidents = parseIncidents(string(text), now)
	}

	names, covers := sessionCatalog(root, l)
	kit := map[string][]portalDoc{}
	internal := walkDocs(root, dir, map[string]bool{"Proyecto.md": true, "Tareas.md": true, "Antecedentes.md": true, portalFile: true, incidentsFile: true})
	shared := walkDocs(root, p.ClientFolder, nil)
	for i := range shared {
		shared[i].Client = true
	}
	for _, d := range append(shared, internal...) {
		switch {
		case d.Client && d.Session == "":
			p.Documents = append(p.Documents, d)
		case d.Session != "" && (d.Client || !client):
			kit[d.Session] = append(kit[d.Session], d)
		}
	}
	for i, name := range names {
		code := fmt.Sprintf("S%d", i+1)
		s, ok := registered[code]
		if !ok {
			s = portalSession{Code: code, State: "pendiente"}
		}
		if s.Name == "" {
			s.Name = name
		}
		s.Kit = kit[code]
		if s.Kit == nil {
			s.Kit = []portalDoc{}
		}
		if !client {
			s.Cover = covers[code]
		}
		p.Sessions = append(p.Sessions, s)
	}

	pr := &p.Progress
	for i := range p.Sessions {
		s := &p.Sessions[i]
		if s.State == "no_incluida" {
			continue
		}
		pr.SessionsTotal++
		if s.State == "hecha" {
			pr.SessionsDone++
		} else if pr.Current == "" {
			pr.Current, s.Current = s.Code, true
		}
	}
	for _, t := range p.Tasks {
		pr.TasksTotal++
		if t.Done {
			pr.TasksDone++
		}
	}
	for _, in := range p.Incidents {
		if in.Open {
			pr.IncidentsOpen++
		}
	}
	if pr.SessionsTotal > 0 {
		pr.Percent = pr.SessionsDone * 100 / pr.SessionsTotal
	}

	if client {
		// «Quitar las secciones que el encargo no incluye».
		kept := p.Sessions[:0]
		for _, s := range p.Sessions {
			if s.State != "no_incluida" {
				s.Note = ""
				kept = append(kept, s)
			}
		}
		p.Sessions = kept
		for i := range p.Incidents {
			p.Incidents[i].Email, p.Incidents[i].Owner, p.Incidents[i].Resolution = "", "", ""
		}
		p.Intro = ""
	}
	return p, nil
}

// listPortals is every expediente under Proyectos/, open first.
func listPortals(root string, l Layout, now time.Time) []portalProject {
	entries, _ := os.ReadDir(filepath.Join(root, filepath.FromSlash(l.projectsDir())))
	out := []portalProject{}
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		p, err := readPortal(root, l, e.Name(), false, now)
		if err != nil {
			continue
		}
		p.Sessions, p.Tasks, p.Incidents, p.Documents, p.Intro = nil, nil, nil, nil, ""
		out = append(out, *p)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Closed != out[j].Closed {
			return !out[i].Closed
		}
		if out[i].Demo != out[j].Demo {
			return out[i].Demo
		}
		return out[i].Title < out[j].Title
	})
	return out
}

// staleIncidents counts open incidents older than days in real (not demo)
// expedientes, for ENT-INC. found is false when no expediente has the file.
func staleIncidents(root string, l Layout, days int, now time.Time) (n int, found bool) {
	entries, _ := os.ReadDir(filepath.Join(root, filepath.FromSlash(l.projectsDir())))
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		dir := path.Join(l.projectsDir(), e.Name())
		data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(path.Join(dir, "Proyecto.md"))))
		if err != nil {
			continue
		}
		if _, _, _, demo := projectFront(data); demo {
			continue
		}
		text, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(path.Join(dir, incidentsFile))))
		if err != nil {
			continue
		}
		found = true
		for _, in := range parseIncidents(string(text), now) {
			if in.Open && in.AgeDays > days {
				n++
			}
		}
	}
	return n, found
}

// --- New incident (PT1 · P2) -------------------------------------------------------

var (
	incidentTypes      = []string{"Técnica", "Accesos", "Automatización", "Negocio", "Otro"}
	incidentSeverities = []string{"Leve", "Media", "Grave"}
)

const incidentsHeader = "# Incidencias\n\n" +
	"Incidencias del proyecto (PT1). Las da de alta el formulario del Portal Cliente o una persona; " +
	"Estado, Responsable y Resolución son internos y se editan aquí.\n\n" +
	"| ID | Fecha | Quién reporta | Email | Tipo | Severidad | Estado | Descripción | Responsable | Resolución |\n" +
	"|---|---|---|---|---|---|---|---|---|---|\n"

type incidentInput struct {
	Reporter    string `json:"reporter"`
	Email       string `json:"email"`
	Date        string `json:"date"`
	Type        string `json:"type"`
	Severity    string `json:"severity"`
	Description string `json:"description"`
	Steps       string `json:"steps"`
}

func oneOf(v string, set []string) bool {
	for _, s := range set {
		if v == s {
			return true
		}
	}
	return false
}

func cell(s string) string {
	s = strings.Join(strings.Fields(strings.ReplaceAll(s, "\r", "")), " ")
	return strings.ReplaceAll(s, "|", `\|`)
}

// appendIncident adds one row to the incidents table, creating the file
// when missing. Every other line stays as the person wrote it.
func appendIncident(old string, in incidentInput) (string, string) {
	if strings.TrimSpace(old) == "" {
		old = incidentsHeader
	}
	t := findTable(old, "id")
	if t.header < 0 {
		old = strings.TrimRight(old, "\n") + "\n\n" + incidentsHeader[strings.Index(incidentsHeader, "| ID"):]
		t = findTable(old, "id")
	}
	next := 1
	for _, cells := range t.rows() {
		id := t.col(cells, "id")
		if n, err := strconv.Atoi(strings.TrimPrefix(id, "INC-")); err == nil && n >= next {
			next = n + 1
		}
	}
	id := fmt.Sprintf("INC-%03d", next)
	desc := in.Description
	if strings.TrimSpace(in.Steps) != "" {
		desc += " — Pasos: " + in.Steps
	}
	values := map[string]string{"id": id, "fecha": in.Date, "quien": in.Reporter, "reporta": in.Reporter, "email": in.Email, "tipo": in.Type,
		"severidad": in.Severity, "estado": "Recibida", "descripcion": desc}
	header := mdCells(t.lines[t.header])
	cells := make([]string, len(header))
	for j, h := range header {
		k := headerKey(h)
		for prefix, v := range values {
			if strings.HasPrefix(k, prefix) {
				cells[j] = cell(v)
				break
			}
		}
	}
	row := "| " + strings.Join(cells, " | ") + " |"
	lines := append(t.lines[:t.last+1:t.last+1], append([]string{row}, t.lines[t.last+1:]...)...)
	return strings.Join(lines, "\n"), id
}

func (f *Folder) portalRoot(ctx context.Context, ws string) (string, Layout, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	if root == "" {
		return "", Layout{}, nil
	}
	l, err := LoadLayout(root)
	if err != nil {
		return "", Layout{}, invalid("%v", err)
	}
	return root, l, nil
}

func (s *Service) postIncident(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	if a.Type != "member" {
		return nil, errf(403, "forbidden", "Las incidencias las registra el cliente o una persona del equipo")
	}
	var in incidentInput
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		return nil, invalid("Cuerpo no legible")
	}
	for _, v := range []*string{&in.Reporter, &in.Email, &in.Date, &in.Type, &in.Severity, &in.Description, &in.Steps} {
		*v = strings.TrimSpace(*v)
	}
	switch {
	case in.Reporter == "" || in.Description == "":
		return nil, invalid("Faltan quién reporta o la descripción")
	case !strings.Contains(in.Email, "@"):
		return nil, invalid("Email de contacto no válido")
	case !reISODay.MatchString(in.Date):
		return nil, invalid("Fecha del incidente no válida (AAAA-MM-DD)")
	case !oneOf(in.Type, incidentTypes):
		return nil, invalid("Tipo no válido: %s", strings.Join(incidentTypes, ", "))
	case !oneOf(in.Severity, incidentSeverities):
		return nil, invalid("Severidad no válida: %s", strings.Join(incidentSeverities, ", "))
	}
	root, err := s.Folder.writeRoot(ctx, ws)
	if err != nil {
		return nil, errf(409, "not_writer", "%v", err)
	}
	if root == "" {
		return nil, invalid("La empresa no tiene carpeta configurada")
	}
	l, err := LoadLayout(root)
	if err != nil {
		return nil, invalid("%v", err)
	}
	p, err := readPortal(root, l, chi.URLParam(r, "project"), false, time.Now())
	if err != nil {
		return nil, err
	}
	if p.Closed {
		return nil, invalid("El proyecto está %s: el portal queda en solo lectura", strings.ToLower(p.State))
	}
	target := filepath.Join(root, filepath.FromSlash(p.IncidentsPath))
	old, err := os.ReadFile(target)
	if err != nil && !os.IsNotExist(err) {
		return nil, err
	}
	if len(old) > 0 {
		// A copy before writing, outside the folder.
		bak := filepath.Join(StateDir(), "copias", "portal", time.Now().Format("20060102-150405")+"-"+p.Slug+"-"+incidentsFile)
		if err := os.MkdirAll(filepath.Dir(bak), 0o700); err != nil {
			return nil, err
		}
		if err := os.WriteFile(bak, old, 0o600); err != nil {
			return nil, fmt.Errorf("copia previa: %w", err)
		}
	}
	text, id := appendIncident(string(old), in)
	if !strings.HasSuffix(text, "\n") {
		text += "\n"
	}
	if err := atomicWrite(target, []byte(text)); err != nil {
		return nil, err
	}
	return map[string]any{"id": id, "path": p.IncidentsPath}, nil
}

func (s *Service) portalRoutes(r chi.Router) {
	r.Get("/portal", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
		root, l, err := s.Folder.portalRoot(ctx, ws)
		if err != nil || root == "" {
			return map[string]any{"configured": false, "projects": []portalProject{}}, err
		}
		return map[string]any{"configured": true, "folder": l.projectsDir(), "client_folder": l.clientPortalDir(),
			"projects": listPortals(root, l, time.Now()), "types": incidentTypes, "severities": incidentSeverities}, nil
	}))
	r.Get("/portal/{project}", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
		root, l, err := s.Folder.portalRoot(ctx, ws)
		if err != nil {
			return nil, err
		}
		if root == "" {
			return nil, invalid("La empresa no tiene carpeta configurada")
		}
		return readPortal(root, l, chi.URLParam(r, "project"), r.URL.Query().Get("vista") == "cliente", time.Now())
	}))
	r.Post("/portal/{project}/incidents", s.handle(s.postIncident))
}
