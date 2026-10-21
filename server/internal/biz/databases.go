package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"net/url"
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
	"gopkg.in/yaml.v3"
)

// «Bases de datos» gathers in one place every database of the company, each
// read from where it lives: notes of the folder, the tables and checklists a
// person keeps in Markdown, the registers (Registros/*.csv), the documents of
// Fiscal/ and, for what only exists in the app (tasks, members, agents), the
// projection. Every row says where it comes from and links to its original.
//
// Nothing here writes. Records that the app also knows (contacts, companies,
// opportunities, products, decisions) open its sheet, where the edits go
// through Service.Run and the single writer, as everywhere else.

type dbField struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

type dbLink struct {
	DB    string `json:"db"`
	ID    string `json:"id"`
	Title string `json:"title"`
}

type dbRow struct {
	ID       string    `json:"id"`
	Title    string    `json:"title"`
	Subtitle string    `json:"subtitle,omitempty"`
	Area     string    `json:"area"`
	Status   string    `json:"status"`
	Date     string    `json:"date"` // AAAA-MM-DD or AAAA-MM
	Owner    string    `json:"owner"`
	Path     string    `json:"path,omitempty"` // folder-relative original
	Origin   string    `json:"origin"`         // where the row is read from, in words
	Entity   string    `json:"entity,omitempty"`
	EntityID string    `json:"entity_id,omitempty"`
	Private  bool      `json:"private,omitempty"`
	Fields   []dbField `json:"fields"`
	Links    []dbLink  `json:"links"`

	db    string
	refs  []string // folder paths this row points at (Markdown links, its project…)
	match []string // other keys that identify the row (invoice number…)
}

type dbInfo struct {
	Key         string   `json:"key"`
	Name        string   `json:"name"`
	Area        string   `json:"area"`
	Description string   `json:"description"`
	Source      string   `json:"source"`        // where it is read from
	Folder      string   `json:"folder"`        // folder to reveal ("" = only in the app)
	Fill        string   `json:"fill"`          // how an empty database is filled
	Why         string   `json:"why,omitempty"` // added beyond the list asked for, and why
	Columns     []string `json:"columns"`       // field labels shown as columns
	Count       int      `json:"count"`
}

// databaseCatalog is the order of the section: Ventas, Entrega, Finanzas,
// Dirección, Marca, Equipo — the journey of a client, then the company.
func databaseCatalog(l Layout) []dbInfo {
	a := l.Areas
	reg := l.registersDir()
	return []dbInfo{
		{Key: "contactos", Name: "Contactos", Area: "ventas", Description: "Personas con las que trata The Last.", Source: l.dir("contact") + "/*.md", Folder: l.dir("contact"),
			Fill: "Una nota por persona en «" + l.dir("contact") + "» (copia «Plantilla persona.md») o «Nuevo interesado» en Ventas.", Columns: []string{"Empresa"}},
		{Key: "empresas", Name: "Empresas", Area: "ventas", Description: "Clientes, proveedores y organizaciones del CRM.", Source: l.dir("organization") + "/*.md", Folder: l.dir("organization"),
			Fill: "Una nota por empresa en «" + l.dir("organization") + "».", Columns: []string{"Contactos"}},
		{Key: "oportunidades", Name: "Oportunidades", Area: "ventas", Description: "Posibles encargos, de la primera conversación al cobro.", Source: l.dir("opportunity") + "/ (notas y carpetas de propuesta)", Folder: l.dir("opportunity"),
			Fill: "Una nota por oportunidad en «" + l.dir("opportunity") + "» (copia «Plantilla.md»); una carpeta con la propuesta también cuenta.", Columns: []string{"Cliente"}},
		{Key: "productos", Name: "Productos y ofertas", Area: "ventas", Description: "Lo que The Last vende y sus versiones de precio.", Source: l.dir("service") + "/", Folder: l.dir("service"),
			Fill: "Una nota por producto en «" + l.dir("service") + "»; las versiones de precio en «" + l.dir("offer") + "».", Columns: []string{"Precio"}},
		{Key: "proyectos", Name: "Proyectos", Area: "entrega", Description: "Expedientes de entrega de cada encargo.", Source: l.projectsDir() + "/*/Proyecto.md", Folder: l.projectsDir(),
			Fill: "Una carpeta por encargo en «" + l.projectsDir() + "» con su «Proyecto.md» (ver Sistemas › Gestionar encargo).", Columns: []string{"Cliente", "Avance"}},
		{Key: "tareas", Name: "Tareas", Area: "", Description: "Las tareas de la app y las listas de cada expediente, en una sola vista.", Source: "Tareas de la app · " + l.projectsDir() + "/*/Tareas.md · Portal.md (tareas del cliente)", Folder: l.projectsDir(),
			Fill: "Crea la tarea en la app (Tareas) o añade una casilla «- [ ] …» en el «Tareas.md» del expediente.", Columns: []string{"Proyecto", "Vence"}},
		{Key: "reuniones", Name: "Reuniones y sesiones", Area: "entrega", Description: "Sesiones S1–S9 de cada proyecto con Portal.", Source: l.projectsDir() + "/*/Portal.md (tabla «Viaje»)", Folder: l.projectsDir(),
			Fill: "Rellena la tabla «Viaje» del «Portal.md» del expediente (fecha y estado de cada sesión).", Columns: []string{"Proyecto"}},
		{Key: "incidencias", Name: "Incidencias", Area: "entrega", Description: "Lo que el cliente o el equipo reporta durante la entrega.", Source: l.projectsDir() + "/*/Incidencias.md", Folder: l.projectsDir(),
			Fill: "Las añade el formulario del Portal Cliente o una fila en el «Incidencias.md» del expediente.", Columns: []string{"Proyecto", "Severidad"}},
		{Key: "facturas", Name: "Facturas emitidas y recibidas", Area: "finanzas", Description: "Registros únicos de facturas y los PDF de Fiscal.", Source: reg + "/emitidas.csv · recibidas.csv · " + a["finanzas"] + "/Fiscal/*/T*/Ingresos|Gastos", Folder: reg,
			Fill: "Una fila por factura emitida o recibida en «" + reg + "» (ver «Esquema.md») y su PDF en Fiscal/<año>/T<n>/.", Columns: []string{"Tipo", "Tercero", "Importe"}},
		{Key: "pagos", Name: "Pagos y movimientos", Area: "finanzas", Description: "Cobros y pagos confirmados y movimientos bancarios.", Source: reg + "/pagos.csv · " + reg + "/importar/*.csv", Folder: reg,
			Fill: "Pagos confirmados en «pagos.csv»; los extractos del banco en «" + reg + "/importar/».", Columns: []string{"Concepto", "Importe", "Cuenta"}},
		{Key: "trimestres", Name: "Trimestres fiscales", Area: "finanzas", Description: "Cada trimestre de Fiscal con sus ingresos, gastos y modelos.", Source: a["finanzas"] + "/Fiscal/<año>/T<n>/", Folder: path.Join(a["finanzas"], "Fiscal"),
			Fill: "Se crea al guardar en «" + a["finanzas"] + "/Fiscal/<año>/T<n>/» los ingresos, gastos y modelos del trimestre.", Columns: []string{"Ingresos", "Gastos", "Modelos"},
			Why: "Añadida: en Notion era «Fiscal — Trimestres» y el paquete trimestral para la gestoría (§12 del Prompt maestro) se organiza por trimestre."},
		{Key: "documentos", Name: "Documentos", Area: "", Description: "Autónomo (Fiscal, Gestoría, Trámites), Contratos, Buzón y los Recursos de cada área.", Source: a["finanzas"] + "/{Fiscal,Gestoría,Trámites} · */Recursos · " + a["direccion"] + "/Contratos · Buzón", Folder: "",
			Fill: "Guarda el documento en la carpeta de su área («Recursos/», «Contratos/», «Gestoría/»…).", Columns: []string{"Tipo"}},
		{Key: "decisiones", Name: "Decisiones", Area: "direccion", Description: "Registro de lo decidido, con su motivo y alcance.", Source: l.decisionsFile(), Folder: a["direccion"],
			Fill: "Añade una línea «- AAAA-MM-DD · decisión · motivo · alcance» al final de «" + l.decisionsFile() + "».", Columns: []string{"Motivo"}},
		{Key: "sistemas", Name: "Sistemas", Area: "", Description: "Cómo se hace cada cosa: procesos de cada área y quién los lleva.", Source: "*/Sistemas/*.md", Folder: "",
			Fill: "Una nota por sistema en «N · Área/Sistemas/» con la línea «> Área · Estado · Lo lleva …».", Columns: []string{}},
		{Key: "contenido", Name: "Contenido", Area: "marca", Description: "Piezas de marca: ideas, borradores y publicaciones.", Source: path.Join(a["marca"], "Contenido") + "/ y Marca › Contenidos", Folder: a["marca"],
			Fill: "Marca está en reposo. Cuando se active, una nota por pieza en «" + path.Join(a["marca"], "Contenido") + "/» o desde Marca › Contenidos.", Columns: []string{"Canal"}},
		{Key: "equipo", Name: "Equipo y colaboradores", Area: "equipo", Description: "Personas de la app y colaboraciones acordadas por encargo.", Source: "Miembros de la app · " + path.Join(a["equipo"], "Colaboraciones") + "/*.md", Folder: path.Join(a["equipo"], "Colaboraciones"),
			Fill: "Una nota por colaboración en «" + path.Join(a["equipo"], "Colaboraciones") + "/» con alcance, compensación y acceso a datos.", Columns: []string{"Rol"}},
		{Key: "agentes", Name: "Agentes de IA", Area: "equipo", Description: "Inventario de agentes con lo que pueden y no pueden hacer.", Source: path.Join(a["equipo"], "Sistemas", "Agentes de IA.md") + " (inventario) · agentes de la app", Folder: path.Join(a["equipo"], "Sistemas"),
			Fill: "Añade una fila al inventario de «Agentes de IA.md» (Agente · Área · Estado · Puede · Nunca).", Columns: []string{"Puede", "Nunca"}},
	}
}

// --- Reading -------------------------------------------------------------------

type dbReader struct {
	ctx     context.Context
	s       *Service
	ws      string
	actor   Actor
	root    string
	l       Layout
	now     time.Time
	appIDs  map[string]string // id → entity type known by the projection
	areaKey map[string]string // headerKey(area name) → code
}

func (s *Service) newDBReader(ctx context.Context, ws string, a Actor) (*dbReader, error) {
	r := &dbReader{ctx: ctx, s: s, ws: ws, actor: a, now: time.Now(), appIDs: map[string]string{}, areaKey: map[string]string{}}
	r.root = s.Folder.Root(ctx, s.Pool, ws)
	r.l = humanLayout()
	if r.root != "" {
		l, err := LoadLayout(r.root)
		if err != nil {
			return nil, invalid("%v", err)
		}
		r.l = l
	}
	for _, x := range Areas {
		r.areaKey[headerKey(x.Name)] = x.Code
		r.areaKey[x.Code] = x.Code
	}
	rows, err := s.Pool.Query(ctx, `SELECT 'contact', id::text FROM biz_contact WHERE workspace_id=$1
		UNION ALL SELECT 'organization', id::text FROM biz_organization WHERE workspace_id=$1
		UNION ALL SELECT 'opportunity', id::text FROM biz_opportunity WHERE workspace_id=$1
		UNION ALL SELECT 'service', id::text FROM biz_service WHERE workspace_id=$1
		UNION ALL SELECT 'offer', id::text FROM biz_offer_version WHERE workspace_id=$1
		UNION ALL SELECT 'decision', id::text FROM biz_decision WHERE workspace_id=$1
		UNION ALL SELECT 'content', id::text FROM biz_content WHERE workspace_id=$1`, ws)
	if err == nil {
		for rows.Next() {
			var typ, id string
			if rows.Scan(&typ, &id) == nil {
				r.appIDs[id] = typ
			}
		}
		rows.Close()
	}
	return r, nil
}

func (r *dbReader) full(rel string) string { return filepath.Join(r.root, filepath.FromSlash(rel)) }

func (r *dbReader) read(rel string) ([]byte, error) {
	if r.root == "" {
		return nil, os.ErrNotExist
	}
	return os.ReadFile(r.full(rel))
}

func (r *dbReader) modDate(rel string) string {
	if st, err := os.Stat(r.full(rel)); err == nil {
		return st.ModTime().Format("2006-01-02")
	}
	return ""
}

// areaOf is the area code of a folder path («2 · Ventas/…» → ventas).
func (r *dbReader) areaOf(rel string) string {
	first := strings.SplitN(rel, "/", 2)[0]
	for code, name := range r.l.Areas {
		if name == first {
			return code
		}
	}
	return ""
}

var reAreaList = regexp.MustCompile(`\s*(?:,|/| y )\s*`)

// areaFromText maps «Dirección, Finanzas» or «Ventas» to the first area named.
func (r *dbReader) areaFromText(s string) string {
	for _, part := range reAreaList.Split(s, -1) {
		if c, ok := r.areaKey[headerKey(part)]; ok {
			return c
		}
	}
	return ""
}

func (r *dbReader) link(row *dbRow, id string) {
	if typ, ok := r.appIDs[id]; ok && id != "" {
		row.Entity, row.EntityID = typ, id
	}
}

// note is one Markdown note: frontmatter, H1 and the links of its body.
type note struct {
	rel   string
	front map[string]any
	body  string
	title string
	refs  []string
}

var reMdLink = regexp.MustCompile(`\]\(([^)\s]+)\)`)

func (r *dbReader) note(rel string) (*note, bool) {
	data, err := r.read(rel)
	if err != nil {
		return nil, false
	}
	n := &note{rel: rel, front: map[string]any{}}
	fm, body, ok := splitNote(data)
	if ok {
		_ = yaml.Unmarshal([]byte(fm), &n.front)
	}
	n.body = body
	n.title = firstHeading(body)
	for _, k := range []string{"nombre", "titulo", "title", "name"} {
		if v := strings.TrimSpace(str(n.front[k])); v != "" {
			n.title = v
			break
		}
	}
	if n.title == "" {
		n.title = strings.TrimSuffix(path.Base(rel), ".md")
	}
	n.refs = noteRefs(rel, body)
	return n, true
}

// noteRefs resolves the relative Markdown links of a note to folder paths.
func noteRefs(rel, body string) []string {
	var out []string
	for _, m := range reMdLink.FindAllStringSubmatch(body, -1) {
		target := m[1]
		if strings.Contains(target, "://") || strings.HasPrefix(target, "#") || strings.HasPrefix(target, "mailto:") {
			continue
		}
		if i := strings.Index(target, "#"); i >= 0 {
			target = target[:i]
		}
		if t, err := url.PathUnescape(target); err == nil {
			target = t
		}
		p := path.Clean(path.Join(path.Dir(rel), target))
		if p != "." && !strings.HasPrefix(p, "../") {
			out = append(out, p)
		}
	}
	return out
}

// field reads the first of the keys from the frontmatter.
func (n *note) field(keys ...string) string {
	for _, k := range keys {
		if v := strings.TrimSpace(fmt.Sprint(n.front[k])); n.front[k] != nil && v != "" {
			return v
		}
	}
	return ""
}

// line returns the text after «Label:» in the body («Cliente: [X](…)» → X).
func (n *note) line(label string) string {
	for _, ln := range strings.Split(n.body, "\n") {
		t := strings.TrimSpace(ln)
		if strings.HasPrefix(t, label+":") {
			v := strings.TrimSpace(strings.TrimPrefix(t, label+":"))
			return reMdLabel.ReplaceAllString(v, "$1")
		}
	}
	return ""
}

var reMdLabel = regexp.MustCompile(`\[([^\]]+)\]\([^)]*\)`)

// notesIn lists the record notes directly inside dir (no index or template).
func (r *dbReader) notesIn(dir string) []*note {
	entries, _ := os.ReadDir(r.full(dir))
	var out []*note
	for _, e := range entries {
		rel := path.Join(dir, e.Name())
		if e.IsDir() || strings.HasPrefix(e.Name(), ".") || !strings.HasSuffix(e.Name(), ".md") || !r.l.recordNote(rel) {
			continue
		}
		if n, ok := r.note(rel); ok {
			out = append(out, n)
		}
	}
	return out
}

func noteRow(db string, n *note, area, origin string) dbRow {
	id := n.field("id")
	if id == "" {
		id = n.rel
	}
	return dbRow{ID: id, Title: n.title, Area: area, Path: n.rel, Origin: origin, refs: n.refs, db: db}
}

func dateField(n *note, r *dbReader, keys ...string) string {
	if v := n.field(keys...); v != "" {
		return v
	}
	return r.modDate(n.rel)
}

func add(row *dbRow, label, value string) {
	if strings.TrimSpace(value) != "" {
		row.Fields = append(row.Fields, dbField{Label: label, Value: strings.TrimSpace(value)})
	}
}

func (row *dbRow) get(label string) string {
	for _, f := range row.Fields {
		if f.Label == label {
			return f.Value
		}
	}
	return ""
}

// --- Each database ---------------------------------------------------------------

func (r *dbReader) contactos() []dbRow {
	var out []dbRow
	for _, n := range r.notesIn(r.l.dir("contact")) {
		row := noteRow("contactos", n, "ventas", "Nota de la carpeta")
		row.Status = n.field("verificacion", "estado")
		row.Date = dateField(n, r, "fecha", "fecha_corte")
		row.Owner = n.field("responsable")
		add(&row, "Empresa", n.line("Empresa"))
		add(&row, "Medio de contacto", n.line("Medio de contacto"))
		add(&row, "Email", n.field("email"))
		add(&row, "Fuente", n.line("Fuente"))
		r.link(&row, n.field("id"))
		out = append(out, row)
	}
	return out
}

func (r *dbReader) empresas() []dbRow {
	var out []dbRow
	for _, n := range r.notesIn(r.l.dir("organization")) {
		row := noteRow("empresas", n, "ventas", "Nota de la carpeta")
		row.Status = n.field("verificacion", "estado")
		row.Date = dateField(n, r, "fecha", "fecha_corte")
		row.Owner = n.field("responsable")
		add(&row, "Tipo", n.field("tipo"))
		add(&row, "NIF", n.field("nif", "tax_id"))
		add(&row, "Fuente", n.line("Fuente"))
		r.link(&row, n.field("id"))
		out = append(out, row)
	}
	return out
}

var reDayName = regexp.MustCompile(`^(20\d\d-\d\d-\d\d)`)

func (r *dbReader) oportunidades() []dbRow {
	dir := r.l.dir("opportunity")
	var out []dbRow
	for _, n := range r.notesIn(dir) {
		row := noteRow("oportunidades", n, "ventas", "Nota de la carpeta")
		row.Status = n.field("estado", "stage", "etapa")
		row.Date = dateField(n, r, "fecha", "fecha_corte")
		row.Owner = n.field("responsable")
		add(&row, "Cliente", n.line("Cliente"))
		add(&row, "Estado en la fuente", n.line("Estado en la fuente"))
		add(&row, "Decisión", n.line("Decisión de Manu"))
		r.link(&row, n.field("id"))
		out = append(out, row)
	}
	// A folder of proposals without a note is an opportunity too: the client
	// is its name and the date its dated subfolder.
	entries, _ := os.ReadDir(r.full(dir))
	for _, e := range entries {
		if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		rel := path.Join(dir, e.Name())
		row := dbRow{ID: rel, Title: e.Name(), Area: "ventas", Path: rel, Status: "Propuesta sin ficha", Origin: "Carpeta de propuesta (sin nota)", db: "oportunidades"}
		files := 0
		subs, _ := os.ReadDir(r.full(rel))
		for _, s := range subs {
			if m := reDayName.FindStringSubmatch(s.Name()); m != nil && m[1] > row.Date {
				row.Date = m[1]
			}
			if s.IsDir() {
				inner, _ := os.ReadDir(r.full(path.Join(rel, s.Name())))
				for _, f := range inner {
					if !strings.HasPrefix(f.Name(), ".") {
						files++
					}
				}
			} else if !strings.HasPrefix(s.Name(), ".") {
				files++
			}
		}
		if row.Date == "" {
			row.Date = r.modDate(rel)
		}
		add(&row, "Cliente", e.Name())
		add(&row, "Documentos", fmt.Sprint(files))
		out = append(out, row)
	}
	return out
}

func (r *dbReader) productos() []dbRow {
	var out []dbRow
	for _, n := range r.notesIn(r.l.dir("service")) {
		row := noteRow("productos", n, "ventas", "Nota de la carpeta")
		row.Status = n.field("estado", "status")
		row.Date = dateField(n, r, "fecha")
		row.Owner = n.field("responsable")
		add(&row, "Código", n.field("code", "codigo"))
		add(&row, "Precio", n.field("precio", "price"))
		r.link(&row, n.field("id"))
		out = append(out, row)
	}
	for _, n := range r.notesIn(r.l.dir("offer")) {
		row := noteRow("productos", n, "ventas", "Versión de precio")
		row.Status = n.field("estado", "active")
		row.Date = dateField(n, r, "valid_from", "fecha")
		add(&row, "Precio", n.field("price_minor", "precio"))
		add(&row, "Versión", n.field("version"))
		r.link(&row, n.field("id"))
		out = append(out, row)
	}
	return out
}

func (r *dbReader) proyectos() []dbRow {
	var out []dbRow
	if r.root != "" {
		for _, p := range listPortals(r.root, r.l, r.now) {
			row := dbRow{ID: p.Path, Title: p.Title, Area: "entrega", Status: p.State, Path: p.Path, Origin: "Expediente de la carpeta", db: "proyectos"}
			n, _ := r.note(p.Path)
			if n != nil {
				row.Date = dateField(n, r, "fecha_cierre", "fecha_inicio", "fecha", "fecha_corte")
				row.Owner = n.field("responsable")
				row.refs = n.refs
				if id := n.field("id"); id != "" {
					add(&row, "ID", id)
				}
			}
			add(&row, "Cliente", p.Client)
			if p.HasPortal {
				add(&row, "Avance", fmt.Sprintf("%d %% · %d/%d sesiones", p.Progress.Percent, p.Progress.SessionsDone, p.Progress.SessionsTotal))
				add(&row, "Incidencias abiertas", fmt.Sprint(p.Progress.IncidentsOpen))
			}
			if p.Demo {
				add(&row, "Demo", "Ejemplo: no cuenta en los indicadores")
			}
			out = append(out, row)
		}
	}
	rows, err := r.s.Pool.Query(r.ctx, `SELECT p.id::text, p.title, p.status, coalesce(p.due_date::text, ''), coalesce(ag.name, u.name, ''), coalesce(org.name, '')
		FROM project p LEFT JOIN biz_project_link l ON l.project_id=p.id LEFT JOIN biz_organization org ON org.id=l.organization_id
		LEFT JOIN agent ag ON p.lead_type='agent' AND ag.id=p.lead_id LEFT JOIN "user" u ON p.lead_type='member' AND u.id=p.lead_id
		WHERE p.workspace_id=$1 ORDER BY p.created_at DESC`, r.ws)
	if err == nil {
		for rows.Next() {
			var row dbRow
			var client string
			if rows.Scan(&row.ID, &row.Title, &row.Status, &row.Date, &row.Owner, &client) == nil {
				row.Area, row.Origin, row.db = "entrega", "Proyecto de la app", "proyectos"
				add(&row, "Cliente", client)
				out = append(out, row)
			}
		}
		rows.Close()
	}
	return out
}

var reTaskID = regexp.MustCompile(`^(T-?\d+|[A-Z]{2,}-\d+)\b`)

func (r *dbReader) tareas() []dbRow {
	var out []dbRow
	if r.root != "" {
		for _, p := range listPortals(r.root, r.l, r.now) {
			dir := path.Dir(p.Path)
			list := path.Join(dir, "Tareas.md")
			if data, err := r.read(list); err == nil {
				for i, ln := range strings.Split(string(data), "\n") {
					m := reTaskLine.FindStringSubmatch(ln)
					if m == nil {
						continue
					}
					row := dbRow{ID: fmt.Sprintf("%s#%d", list, i+1), Area: "entrega", Path: list, Origin: "Tareas.md del expediente", refs: []string{p.Path}, db: "tareas"}
					row.Status = map[bool]string{true: "Hecha", false: "Pendiente"}[m[1] != " "]
					var words []string
					for _, part := range splitDots(m[2]) {
						switch d := reDue.FindStringSubmatch(part); {
						case d != nil:
							row.Date = d[1]
							add(&row, "Vence", d[1])
						case strings.HasPrefix(strings.ToLower(part), "responsable "), strings.HasPrefix(part, "@"):
							row.Owner = strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(part, "@"), "responsable "))
						default:
							words = append(words, part)
						}
					}
					row.Title = strings.Join(words, " · ")
					if id := reTaskID.FindString(row.Title); id != "" {
						add(&row, "ID", id)
					}
					add(&row, "Proyecto", p.Title)
					out = append(out, row)
				}
			}
			if !p.HasPortal {
				continue
			}
			full, err := readPortal(r.root, r.l, p.Slug, false, r.now)
			if err != nil {
				continue
			}
			for i, t := range full.Tasks {
				row := dbRow{ID: fmt.Sprintf("%s#cliente-%d", full.PortalPath, i+1), Title: t.Text, Area: "entrega", Owner: "Cliente", Date: t.Due, Path: full.PortalPath,
					Origin: "Tarea del cliente (Portal.md)", refs: []string{p.Path}, db: "tareas"}
				row.Status = map[bool]string{true: "Hecha", false: "Pendiente"}[t.Done]
				if t.Overdue {
					row.Status = "Vencida"
				}
				add(&row, "Proyecto", p.Title)
				add(&row, "Sesión", t.Session)
				add(&row, "Vence", t.Due)
				out = append(out, row)
			}
		}
	}
	rows, err := r.s.Pool.Query(r.ctx, `SELECT i.id::text, coalesce(w.issue_prefix || '-' || i.number::text, ''), i.title, coalesce(st.name, i.status), coalesce(i.due_date::text, ''), coalesce(ag.name, u.name, ''),
		coalesce(p.title, ''), coalesce((SELECT string_agg(lb.name, ', ') FROM issue_to_label il JOIN issue_label lb ON lb.id=il.label_id WHERE il.issue_id=i.id), ''),
		coalesce(l.kind, ''), i.updated_at::date::text
		FROM issue i LEFT JOIN workspace w ON w.id=i.workspace_id LEFT JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status
		LEFT JOIN project p ON p.id=i.project_id LEFT JOIN biz_project_link l ON l.project_id=p.id
		LEFT JOIN agent ag ON i.assignee_type='agent' AND ag.id=i.assignee_id LEFT JOIN "user" u ON i.assignee_type='member' AND u.id=i.assignee_id
		WHERE i.workspace_id=$1 ORDER BY i.updated_at DESC LIMIT 2000`, r.ws)
	if err == nil {
		for rows.Next() {
			var row dbRow
			var ident, due, project, labels, kind, updated string
			if rows.Scan(&row.ID, &ident, &row.Title, &row.Status, &due, &row.Owner, &project, &labels, &kind, &updated) != nil {
				continue
			}
			row.Origin, row.db, row.Entity, row.EntityID = "Tarea de la app", "tareas", "issue", row.ID
			row.Date = due
			if row.Date == "" {
				row.Date = updated
			}
			row.Area = r.areaFromText(labels)
			if row.Area == "" && project != "" {
				row.Area = "entrega"
			}
			add(&row, "ID", ident)
			add(&row, "Proyecto", project)
			add(&row, "Vence", due)
			add(&row, "Etiquetas", labels)
			out = append(out, row)
		}
		rows.Close()
	}
	return out
}

func (r *dbReader) reuniones() []dbRow {
	var out []dbRow
	if r.root == "" {
		return out
	}
	for _, p := range listPortals(r.root, r.l, r.now) {
		if !p.HasPortal {
			continue
		}
		full, err := readPortal(r.root, r.l, p.Slug, false, r.now)
		if err != nil {
			continue
		}
		for _, s := range full.Sessions {
			row := dbRow{ID: full.PortalPath + "#" + s.Code, Title: s.Code + " · " + s.Name, Area: "entrega", Date: s.Date, Path: full.PortalPath, Owner: "Manu",
				Origin: "Tabla «Viaje» del Portal.md", refs: []string{p.Path}, db: "reuniones"}
			row.Status = s.Status
			if row.Status == "" {
				row.Status = "Pendiente"
			}
			add(&row, "Proyecto", p.Title)
			add(&row, "Resumen para el cliente", s.Summary)
			add(&row, "Nota interna", s.Note)
			if len(s.Kit) > 0 {
				add(&row, "Kit", fmt.Sprintf("%d documentos", len(s.Kit)))
			}
			out = append(out, row)
		}
	}
	return out
}

func (r *dbReader) incidencias() []dbRow {
	var out []dbRow
	if r.root == "" {
		return out
	}
	for _, p := range listPortals(r.root, r.l, r.now) {
		data, err := r.read(p.IncidentsPath)
		if err != nil {
			continue
		}
		for _, in := range parseIncidents(string(data), r.now) {
			row := dbRow{ID: p.IncidentsPath + "#" + in.ID, Title: in.Description, Subtitle: in.ID, Area: "entrega", Status: in.Status, Date: in.Date, Owner: in.Owner,
				Path: p.IncidentsPath, Origin: "Tabla de Incidencias.md", refs: []string{p.Path}, db: "incidencias"}
			add(&row, "ID", in.ID)
			add(&row, "Proyecto", p.Title)
			add(&row, "Quién reporta", in.Reporter)
			add(&row, "Tipo", in.Type)
			add(&row, "Severidad", in.Severity)
			add(&row, "Resolución", in.Resolution)
			if in.Open {
				add(&row, "Antigüedad", fmt.Sprintf("%d días", in.AgeDays))
			}
			out = append(out, row)
		}
	}
	return out
}

// «2026-02-06 F260002 José Miguel Mesa 4.560€.pdf»: date, number, party, amount.
var reInvoiceName = regexp.MustCompile(`^(20\d\d-\d\d-\d\d)[ _]+([A-Z]{1,4}[-_]?\d{2,}[A-Z0-9-]*)?[ _]*(.*?)(?:[ _]+(-?\d[\d.,]*)\s?(?:€|euros?|EUR))?$`)

func invoiceFromName(name string) (date, number, party, amount string) {
	base := strings.TrimSuffix(name, path.Ext(name))
	if m := reInvoiceName.FindStringSubmatch(base); m != nil {
		return m[1], m[2], strings.TrimSpace(strings.ReplaceAll(m[3], "_", " ")), m[4]
	}
	return "", "", strings.ReplaceAll(base, "_", " "), ""
}

func (r *dbReader) facturas() []dbRow {
	var out []dbRow
	if r.root == "" {
		return out
	}
	reg := r.l.registersDir()
	numbers := map[string]bool{}
	for _, f := range []struct{ file, kind, status string }{{"emitidas.csv", "Emitida", "estado_emision"}, {"recibidas.csv", "Recibida", "estado_revision"}} {
		rel := path.Join(reg, f.file)
		rg, err := readRegister(r.full(rel))
		if err != nil {
			continue
		}
		for _, x := range rg.rows {
			row := dbRow{ID: rg.get(x, "id"), Title: rg.get(x, "numero_documento"), Area: "finanzas", Status: rg.get(x, f.status), Date: rg.get(x, "fecha_documento"),
				Path: rel, Origin: "Registro único (" + f.file + ")", db: "facturas"}
			if row.Title == "" {
				row.Title = row.ID
			}
			add(&row, "Tipo", f.kind)
			add(&row, "Tercero", rg.get(x, "tercero"))
			add(&row, "Importe", strings.TrimSpace(rg.get(x, "total_documento")+" "+rg.get(x, "moneda")))
			add(&row, "Documento", rg.get(x, "documento"))
			add(&row, "Ámbito", rg.get(x, "ambito"))
			add(&row, "Fuente", rg.get(x, "fuente"))
			if doc := rg.get(x, "documento"); doc != "" && !filepath.IsAbs(doc) {
				row.refs = append(row.refs, path.Clean(path.Join(reg, doc)))
			}
			if n := rg.get(x, "numero_documento"); n != "" {
				numbers[n] = true
				row.match = append(row.match, n)
			}
			r.link(&row, rg.get(x, "registro_id"))
			out = append(out, row)
		}
	}
	// The PDFs of Fiscal/<año>/T<n>/{Ingresos,Gastos}: each one is an invoice
	// until it has its row in the register.
	fiscal := path.Join(r.l.Areas["finanzas"], "Fiscal")
	_ = filepath.WalkDir(r.full(fiscal), func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		name := d.Name()
		if d.IsDir() {
			if strings.HasPrefix(name, ".") || packageExt[strings.ToLower(filepath.Ext(name))] {
				return filepath.SkipDir
			}
			return nil
		}
		rel, _ := filepath.Rel(r.root, p)
		rel = filepath.ToSlash(rel)
		parts := strings.Split(strings.TrimPrefix(rel, fiscal+"/"), "/")
		kind := ""
		for i, seg := range parts[:len(parts)-1] {
			if seg == "Ingresos" || seg == "Gastos" {
				kind = seg
				parts = parts[i+1:]
				break
			}
		}
		cloud := strings.HasPrefix(name, ".") && strings.HasSuffix(name, ".icloud")
		if cloud {
			name = strings.TrimSuffix(strings.TrimPrefix(name, "."), ".icloud")
		}
		ext := strings.ToLower(path.Ext(name))
		if kind == "" || (strings.HasPrefix(name, ".") && !cloud) || (ext != ".pdf" && ext != ".jpg" && ext != ".jpeg" && ext != ".png" && ext != ".heic") {
			return nil
		}
		date, number, party, amount := invoiceFromName(name)
		if len(parts) > 1 && kind == "Gastos" {
			party = strings.Join(parts[:len(parts)-1], " / ")
		}
		row := dbRow{ID: rel, Title: name, Area: "finanzas", Date: date, Path: rel, Origin: "PDF en Fiscal (sin fila en el registro)", db: "facturas"}
		if row.Date == "" {
			row.Date = r.modDate(rel)
		}
		row.Status = "Sin registrar"
		if numbers[number] {
			row.Status = "Registrada"
		}
		low := strings.ToLower(name)
		switch {
		case strings.Contains(low, "anulad"):
			row.Status = "Anulada"
		case strings.Contains(low, "borrador"):
			row.Status = "Borrador"
		case strings.Contains(low, "rectificativ"):
			add(&row, "Nota", "Rectificativa")
		}
		add(&row, "Tipo", map[string]string{"Ingresos": "Emitida", "Gastos": "Recibida"}[kind])
		add(&row, "Número", number)
		add(&row, "Tercero", party)
		if amount != "" {
			add(&row, "Importe", amount+" €")
		}
		if q := fiscalQuarter(rel, fiscal); q != "" {
			add(&row, "Trimestre", q)
			row.match = append(row.match, "→Q:"+q)
		}
		if cloud {
			add(&row, "iCloud", "Sin descargar en este Mac")
		}
		if number != "" {
			row.match = append(row.match, number)
		}
		out = append(out, row)
		return nil
	})
	return out
}

// fiscalQuarter is «2026 · T1» from Fiscal/2026/T1/….
func fiscalQuarter(rel, fiscal string) string {
	segs := strings.Split(strings.TrimPrefix(rel, fiscal+"/"), "/")
	if len(segs) >= 2 && reYear.MatchString(segs[0]) && (reQuarter.MatchString(segs[1]) || segs[1] == "Sin trimestre") {
		return segs[0] + " · " + segs[1]
	}
	if len(segs) >= 1 && reYear.MatchString(segs[0]) {
		return segs[0]
	}
	return ""
}

func (r *dbReader) pagos() []dbRow {
	var out []dbRow
	if r.root == "" {
		return out
	}
	reg := r.l.registersDir()
	if rg, err := readRegister(r.full(path.Join(reg, "pagos.csv"))); err == nil {
		for _, x := range rg.rows {
			row := dbRow{ID: rg.get(x, "id"), Title: rg.get(x, "direccion") + " " + rg.get(x, "importe"), Area: "finanzas", Status: rg.get(x, "verificacion"), Date: rg.get(x, "fecha"),
				Path: path.Join(reg, "pagos.csv"), Origin: "Registro único (pagos.csv)", db: "pagos"}
			add(&row, "Concepto", rg.get(x, "direccion"))
			add(&row, "Importe", strings.TrimSpace(rg.get(x, "importe")+" "+rg.get(x, "moneda")))
			add(&row, "Cuenta", rg.get(x, "cuenta"))
			add(&row, "Factura", rg.get(x, "documento_id"))
			add(&row, "Evidencia", rg.get(x, "evidencia"))
			row.match = append(row.match, "→"+rg.get(x, "documento_id"))
			out = append(out, row)
		}
	}
	dir := path.Join(reg, "importar")
	entries, _ := os.ReadDir(r.full(dir))
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(strings.ToLower(e.Name()), ".csv") {
			continue
		}
		rel := path.Join(dir, e.Name())
		rg, err := readRegister(r.full(rel))
		if err != nil {
			continue
		}
		for i, x := range rg.rows {
			id := rg.get(x, "id")
			if id == "" {
				id = fmt.Sprintf("%s#%d", rel, i+2)
			}
			row := dbRow{ID: id, Title: rg.get(x, "concepto"), Area: "finanzas", Status: "Por importar", Date: rg.get(x, "fecha"), Path: rel,
				Origin: "Extracto en Registros/importar (" + e.Name() + ")", db: "pagos"}
			add(&row, "Concepto", rg.get(x, "concepto"))
			add(&row, "Importe", rg.get(x, "importe")+" €")
			add(&row, "Tipo", rg.get(x, "tipo"))
			add(&row, "Categoría", rg.get(x, "categoria"))
			add(&row, "Cuenta", rg.get(x, "cuenta_nombre"))
			add(&row, "Factura", firstNonEmpty(rg.get(x, "numero_factura"), rg.get(x, "factura_numero")))
			add(&row, "Fecha de la factura", rg.get(x, "fecha_factura"))
			add(&row, "Proyecto", rg.get(x, "proyecto_nombre"))
			if n := row.get("Factura"); n != "" {
				row.match = append(row.match, "→"+n)
			}
			out = append(out, row)
		}
	}
	return out
}

func firstNonEmpty(xs ...string) string {
	for _, x := range xs {
		if strings.TrimSpace(x) != "" {
			return x
		}
	}
	return ""
}

func (r *dbReader) trimestres() []dbRow {
	var out []dbRow
	if r.root == "" {
		return out
	}
	fiscal := path.Join(r.l.Areas["finanzas"], "Fiscal")
	years, _ := os.ReadDir(r.full(fiscal))
	for _, y := range years {
		if !y.IsDir() || !reYear.MatchString(y.Name()) {
			continue
		}
		qs, _ := os.ReadDir(r.full(path.Join(fiscal, y.Name())))
		for _, q := range qs {
			if !q.IsDir() || !(reQuarter.MatchString(q.Name()) || q.Name() == "Sin trimestre") {
				continue
			}
			dir := path.Join(fiscal, y.Name(), q.Name())
			row := dbRow{ID: dir, Title: q.Name() + " " + y.Name(), Area: "finanzas", Path: dir, Owner: "Gestoría y Manu", Origin: "Carpeta de Fiscal", db: "trimestres"}
			if q.Name() == "Sin trimestre" {
				row.Title = y.Name() + " · sin trimestre"
			}
			count := func(sub string) int {
				n := 0
				_ = filepath.WalkDir(r.full(path.Join(dir, sub)), func(p string, d fs.DirEntry, err error) error {
					if err == nil && !d.IsDir() && d.Name() != ".DS_Store" && !strings.HasPrefix(d.Name(), "~$") && !strings.HasPrefix(path.Base(p), "00 INDICE") {
						n++
					}
					return nil
				})
				return n
			}
			add(&row, "Ingresos", fmt.Sprint(count("Ingresos")))
			add(&row, "Gastos", fmt.Sprint(count("Gastos")))
			add(&row, "Modelos", fmt.Sprint(count("Modelos")))
			if n, ok := r.note(path.Join(dir, q.Name()+" "+y.Name()+".md")); ok {
				row.Path = n.rel
				row.Status = n.field("estado")
				row.refs = n.refs
			}
			if row.Status == "" {
				row.Status = "Abierto"
				if qn := atoiSafe(strings.TrimPrefix(q.Name(), "T")); q.Name() != "Sin trimestre" && quarterEnded(atoiSafe(y.Name()), qn, r.now) {
					row.Status = "Terminado"
				}
			}
			row.match = append(row.match, "Q:"+y.Name()+" · "+q.Name())
			if q.Name() != "Sin trimestre" {
				qn := atoiSafe(strings.TrimPrefix(q.Name(), "T"))
				row.Date = fmt.Sprintf("%s-%02d", y.Name(), qn*3)
			} else {
				row.Date = y.Name() + "-12"
			}
			out = append(out, row)
		}
	}
	var periods []struct {
		Year    int    `json:"year"`
		Quarter int    `json:"quarter"`
		Status  string `json:"status"`
	}
	if raw, err := listJSON(r.ctx, r.s.Pool, `SELECT year, quarter, status FROM biz_period WHERE workspace_id=$1`, r.ws); err == nil {
		_ = json.Unmarshal(raw, &periods)
	}
	for _, p := range periods {
		for i := range out {
			if out[i].Title == fmt.Sprintf("T%d %d", p.Quarter, p.Year) {
				out[i].Status = periodStatusLabel(p.Status)
			}
		}
	}
	return out
}

func quarterEnded(year, q int, now time.Time) bool {
	end := time.Date(year, time.Month(q*3)+1, 1, 0, 0, 0, 0, time.UTC)
	return !now.Before(end)
}

var periodStatusLabels = map[string]string{"open": "Abierto", "collecting": "Recogiendo", "review": "En revisión", "ready": "Listo para gestoría",
	"sent": "Enviado", "filed": "Presentado", "closed": "Cerrado"}

func periodStatusLabel(s string) string {
	if l, ok := periodStatusLabels[s]; ok {
		return l
	}
	return s
}

func (r *dbReader) documentos() []dbRow {
	var out []dbRow
	if r.root == "" {
		return out
	}
	docs, _ := r.s.Folder.Documents(r.ctx, r.ws, r.actor)
	if list, ok := docs["documents"].([]libraryDoc); ok {
		for _, d := range list {
			if d.Group == "Registros" || (d.Group == "Fiscal" && (d.Kind == "Ingresos" || d.Kind == "Gastos")) {
				continue // registers and invoices have their own databases
			}
			row := dbRow{ID: d.Path, Title: d.Name, Area: "finanzas", Date: d.Date, Path: d.Path, Status: d.Group, Origin: "Autónomo · " + d.Group, Private: d.Private, db: "documentos"}
			add(&row, "Tipo", firstNonEmpty(d.Kind, d.Group))
			add(&row, "Detalle", d.Detail)
			if d.Year > 0 {
				add(&row, "Periodo", strings.TrimSpace(fmt.Sprint(d.Year)+" "+d.Quarter))
			}
			add(&row, "Fecha según", d.DateSource)
			if d.Private {
				add(&row, "Privado", "Solo personas; los agentes no lo reciben")
			}
			out = append(out, row)
		}
	}
	// Recursos/ of every area, Contratos/ and the inbox: one row per entry at
	// the top of each folder (a folder of material is one document).
	var dirs [][2]string
	for _, code := range []string{"direccion", "ventas", "entrega", "finanzas", "marca", "equipo"} {
		dirs = append(dirs, [2]string{code, path.Join(r.l.Areas[code], "Recursos")})
	}
	dirs = append(dirs, [2]string{"direccion", path.Join(r.l.Areas["direccion"], "Contratos")})
	if r.l.Buzon != "" {
		dirs = append(dirs, [2]string{"", r.l.Buzon})
	}
	for _, d := range dirs {
		entries, _ := os.ReadDir(r.full(d[1]))
		for _, e := range entries {
			name := e.Name()
			if strings.HasPrefix(name, ".") || strings.HasPrefix(name, "~$") {
				continue
			}
			rel := path.Join(d[1], name)
			if r.actor.Type == "agent" && r.l.Private(rel) {
				continue
			}
			kind := strings.TrimPrefix(strings.ToUpper(path.Ext(name)), ".")
			if e.IsDir() && !packageExt[strings.ToLower(path.Ext(name))] {
				kind = "Carpeta"
			}
			group := path.Base(d[1])
			row := dbRow{ID: rel, Title: name, Area: d[0], Date: r.modDate(rel), Path: rel, Status: group, Origin: group + " de " + firstNonEmpty(r.l.Areas[d[0]], "la empresa"), db: "documentos"}
			add(&row, "Tipo", kind)
			out = append(out, row)
		}
	}
	return out
}

func (r *dbReader) decisiones() []dbRow {
	var out []dbRow
	rel := r.l.decisionsFile()
	if rel == "" {
		return out
	}
	data, err := r.read(rel)
	if err != nil {
		return out
	}
	for i, ln := range strings.Split(string(data), "\n") {
		m := humanDecision(visiblePart(ln))
		if m == nil {
			continue
		}
		row := dbRow{ID: fmt.Sprintf("%s#%d", rel, i+1), Title: str(m["title"]), Area: "direccion", Date: str(m["decided_at"])[:10], Path: rel, Owner: "Manu",
			Origin: "Línea de Decisiones.md", refs: noteRefs(rel, ln), db: "decisiones"}
		row.Status = "Sin registrar en la app"
		if mark := parseDecisionLine(ln); mark != nil {
			row.ID = str(mark["id"])
			row.Status = "Registrada"
			r.link(&row, row.ID)
		}
		if m["status"] == "superseded" {
			row.Status = "Sustituida"
		}
		add(&row, "Decisión", str(m["decision"]))
		add(&row, "Motivo", str(m["why"]))
		add(&row, "Alcance", str(m["purpose"]))
		out = append(out, row)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Date > out[j].Date })
	return out
}

func (r *dbReader) sistemas() []dbRow {
	var out []dbRow
	for _, code := range []string{"direccion", "ventas", "entrega", "finanzas", "marca", "equipo"} {
		res, err := r.s.Folder.Systems(r.ctx, r.ws, code)
		if err != nil {
			continue
		}
		list, _ := res["systems"].([]systemDoc)
		var walk func(d systemDoc, parent string)
		walk = func(d systemDoc, parent string) {
			row := dbRow{ID: d.Path, Title: d.Title, Area: code, Status: d.Status, Owner: strings.TrimSpace(strings.TrimPrefix(d.Owner, "Lo lleva")), Path: d.Path,
				Origin: "Nota de Sistemas", refs: noteRefs(d.Path, d.Intro), db: "sistemas"}
			if !d.ModifiedAt.IsZero() {
				row.Date = d.ModifiedAt.Format("2006-01-02")
			}
			for _, s := range d.Sections {
				row.refs = append(row.refs, noteRefs(d.Path, s.Body)...)
				if h := headerKey(s.Heading); h == "para que" || h == "cuando se usa" || h == "rutina" || h == "que deja hecho" {
					add(&row, s.Heading, firstParagraph(s.Body))
				}
			}
			if parent != "" {
				add(&row, "Procedimiento de", parent)
				row.refs = append(row.refs, parent)
			}
			if len(d.Children) > 0 {
				add(&row, "Procedimientos", fmt.Sprint(len(d.Children)))
			}
			out = append(out, row)
			for _, c := range d.Children {
				walk(c, d.Path)
			}
		}
		for _, d := range list {
			walk(d, "")
		}
	}
	return out
}

func firstParagraph(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.Index(s, "\n\n"); i > 0 {
		s = s[:i]
	}
	if r := []rune(s); len(r) > 240 {
		s = string(r[:240]) + "…"
	}
	return s
}

func (r *dbReader) contenido() []dbRow {
	var out []dbRow
	for _, dir := range []string{path.Join(r.l.Areas["marca"], "Contenido"), r.l.dir("content")} {
		for _, n := range r.notesIn(dir) {
			row := noteRow("contenido", n, "marca", "Nota de la carpeta")
			row.Status = n.field("estado", "status")
			row.Date = dateField(n, r, "fecha", "scheduled_at", "published_at")
			row.Owner = n.field("responsable", "owner")
			add(&row, "Canal", n.field("canal", "channel"))
			add(&row, "Pilar", n.field("pilar", "pillar"))
			r.link(&row, n.field("id"))
			out = append(out, row)
		}
	}
	seen := map[string]bool{}
	for _, row := range out {
		seen[row.ID] = true
	}
	var items []map[string]any
	if raw, err := listJSON(r.ctx, r.s.Pool, `SELECT id::text, title, status, channel, pillar, coalesce(scheduled_at, created_at)::date::text AS day FROM biz_content WHERE workspace_id=$1 AND archived_at IS NULL`, r.ws); err == nil {
		_ = json.Unmarshal(raw, &items)
	}
	for _, c := range items {
		if seen[str(c["id"])] {
			continue
		}
		row := dbRow{ID: str(c["id"]), Title: str(c["title"]), Area: "marca", Status: str(c["status"]), Date: str(c["day"]), Origin: "Contenido de la app", Entity: "content", EntityID: str(c["id"]), db: "contenido"}
		add(&row, "Canal", str(c["channel"]))
		add(&row, "Pilar", str(c["pillar"]))
		out = append(out, row)
	}
	return out
}

func (r *dbReader) equipo() []dbRow {
	var out []dbRow
	var members []map[string]any
	if raw, err := listJSON(r.ctx, r.s.Pool, `SELECT u.id::text, u.name, u.email, m.role, m.created_at::date::text AS since,
		(SELECT string_agg(br.name, ', ') FROM biz_role br WHERE br.workspace_id=m.workspace_id AND br.occupant_type='member' AND br.occupant_id=m.user_id) AS roles
		FROM member m JOIN "user" u ON u.id=m.user_id WHERE m.workspace_id=$1 ORDER BY m.created_at`, r.ws); err == nil {
		_ = json.Unmarshal(raw, &members)
	}
	for _, m := range members {
		row := dbRow{ID: "member:" + str(m["id"]), Title: str(m["name"]), Area: "equipo", Status: "Miembro de la app", Date: str(m["since"]), Origin: "Miembro de la app", db: "equipo"}
		add(&row, "Rol", firstNonEmpty(str(m["roles"]), map[string]string{"owner": "Titular", "admin": "Administración", "member": "Miembro"}[str(m["role"])]))
		add(&row, "Email", str(m["email"]))
		out = append(out, row)
	}
	for _, n := range r.notesIn(path.Join(r.l.Areas["equipo"], "Colaboraciones")) {
		row := noteRow("equipo", n, "equipo", "Nota de Colaboraciones")
		row.Status = n.field("estado")
		row.Date = dateField(n, r, "fecha", "inicio")
		row.Owner = n.field("responsable")
		add(&row, "Rol", firstNonEmpty(n.field("rol"), "Colaboración"))
		add(&row, "Alcance", n.line("Alcance"))
		add(&row, "Compensación", n.line("Compensación"))
		out = append(out, row)
	}
	return out
}

func (r *dbReader) agentes() []dbRow {
	var out []dbRow
	rel := path.Join(r.l.Areas["equipo"], "Sistemas", "Agentes de IA.md")
	type appAgent struct {
		ID, Name, Description, Runtime, Status string
	}
	app := map[string]appAgent{}
	if rows, err := r.s.Pool.Query(r.ctx, `SELECT a.id::text, a.name, coalesce(a.description, ''), coalesce(rt.provider, ''), coalesce(rt.status, '')
		FROM agent a LEFT JOIN agent_runtime rt ON rt.id=a.runtime_id WHERE a.workspace_id=$1 AND a.archived_at IS NULL`, r.ws); err == nil {
		for rows.Next() {
			var a appAgent
			if rows.Scan(&a.ID, &a.Name, &a.Description, &a.Runtime, &a.Status) == nil {
				app[headerKey(a.Name)] = a
			}
		}
		rows.Close()
	}
	used := map[string]bool{}
	data, err := r.read(rel)
	if err == nil {
		t := findTable(string(data), "agente")
		date := r.modDate(rel)
		if m := regexp.MustCompile(`## Inventario \((\d{1,2})/(\d{1,2})/(20\d\d)`).FindStringSubmatch(string(data)); m != nil {
			date = fmt.Sprintf("%s-%02d-%02d", m[3], atoiSafe(m[2]), atoiSafe(m[1]))
		}
		for _, cells := range t.rows() {
			name := t.col(cells, "agente")
			if name == "" {
				continue
			}
			areas := t.col(cells, "area")
			row := dbRow{ID: rel + "#" + name, Title: name, Area: r.areaFromText(areas), Status: t.col(cells, "estado"), Date: date, Owner: "Manu",
				Path: rel, Origin: "Inventario de Agentes de IA.md", db: "agentes"}
			add(&row, "Áreas", areas)
			add(&row, "Puede", t.col(cells, "puede"))
			add(&row, "Nunca", t.col(cells, "nunca"))
			if a, ok := app[headerKey(name)]; ok {
				used[headerKey(name)] = true
				add(&row, "En la app", firstNonEmpty(strings.TrimSpace(a.Runtime+" "+a.Status), "Sí"))
			} else {
				add(&row, "En la app", "No (vive en Multica)")
			}
			out = append(out, row)
		}
	}
	for k, a := range app {
		if used[k] {
			continue
		}
		row := dbRow{ID: "agent:" + a.ID, Title: a.Name, Status: "En la app, fuera del inventario", Origin: "Agente de la app", db: "agentes"}
		add(&row, "Puede", a.Description)
		add(&row, "En la app", strings.TrimSpace(a.Runtime+" "+a.Status))
		out = append(out, row)
	}
	return out
}

// --- All together ------------------------------------------------------------------

func (r *dbReader) rows(key string) []dbRow {
	switch key {
	case "contactos":
		return r.contactos()
	case "empresas":
		return r.empresas()
	case "oportunidades":
		return r.oportunidades()
	case "productos":
		return r.productos()
	case "proyectos":
		return r.proyectos()
	case "tareas":
		return r.tareas()
	case "reuniones":
		return r.reuniones()
	case "incidencias":
		return r.incidencias()
	case "facturas":
		return r.facturas()
	case "pagos":
		return r.pagos()
	case "trimestres":
		return r.trimestres()
	case "documentos":
		return r.documentos()
	case "decisiones":
		return r.decisiones()
	case "sistemas":
		return r.sistemas()
	case "contenido":
		return r.contenido()
	case "equipo":
		return r.equipo()
	case "agentes":
		return r.agentes()
	}
	return nil
}

var dbNames = func() map[string]string {
	out := map[string]string{}
	for _, d := range databaseCatalog(humanLayout()) {
		out[d.Key] = d.Name
	}
	return out
}()

// all reads every database and resolves the relations between rows: a row
// points at another when one of its folder links is the other's original,
// or when a movement names the number of an invoice.
func (r *dbReader) all() (map[string][]dbRow, []dbInfo) {
	cat := databaseCatalog(r.l)
	out := map[string][]dbRow{}
	byPath := map[string]*dbRow{}
	byMatch := map[string]*dbRow{}
	for _, d := range cat {
		rows := r.rows(d.Key)
		if rows == nil {
			rows = []dbRow{}
		}
		for i := range rows {
			rows[i].db = d.Key
			if rows[i].Fields == nil {
				rows[i].Fields = []dbField{}
			}
		}
		sort.SliceStable(rows, func(i, j int) bool {
			if rows[i].Date != rows[j].Date {
				return rows[i].Date > rows[j].Date
			}
			return rows[i].Title < rows[j].Title
		})
		out[d.Key] = rows
	}
	// A row is a link target when its original is its own: a note, an
	// expediente or a folder. A file that holds many rows (a register, a
	// table, Decisiones.md) says nothing about one of them.
	paths := map[string]int{}
	for _, rows := range out {
		for _, row := range rows {
			if row.Path != "" {
				paths[row.Path]++
			}
		}
	}
	for _, d := range cat {
		rows := out[d.Key]
		for i := range rows {
			row := &rows[i]
			if row.Path != "" && paths[row.Path] == 1 {
				byPath[row.Path] = row
			}
			for _, m := range row.match {
				if !strings.HasPrefix(m, "→") {
					byMatch[m] = row
				}
			}
		}
	}
	for _, d := range cat {
		rows := out[d.Key]
		for i := range rows {
			row := &rows[i]
			seen := map[string]bool{}
			addLink := func(t *dbRow) {
				if t == nil || t == row || seen[t.db+t.ID] {
					return
				}
				seen[t.db+t.ID] = true
				row.Links = append(row.Links, dbLink{DB: t.db, ID: t.ID, Title: t.Title})
			}
			for _, ref := range row.refs {
				t := byPath[ref]
				if t == nil {
					t = byPath[path.Join(ref, "Proyecto.md")]
				}
				addLink(t)
			}
			for _, m := range row.match {
				if strings.HasPrefix(m, "→") {
					addLink(byMatch[strings.TrimPrefix(m, "→")])
				}
			}
			if row.Links == nil {
				row.Links = []dbLink{}
			}
		}
	}
	for i := range cat {
		cat[i].Count = len(out[cat[i].Key])
	}
	return out, cat
}

func (s *Service) getDatabases(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	rd, err := s.newDBReader(ctx, ws, a)
	if err != nil {
		return nil, err
	}
	_, cat := rd.all()
	return map[string]any{"configured": rd.root != "", "databases": cat}, nil
}

func (s *Service) getDatabase(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	key := chi.URLParam(r, "db")
	if _, ok := dbNames[key]; !ok {
		return nil, errf(404, "not_found", "Base de datos desconocida")
	}
	rd, err := s.newDBReader(ctx, ws, a)
	if err != nil {
		return nil, err
	}
	all, cat := rd.all()
	var info dbInfo
	for _, d := range cat {
		if d.Key == key {
			info = d
		}
	}
	out := map[string]any{"configured": rd.root != "", "database": info, "rows": all[key]}
	if id := r.URL.Query().Get("id"); id != "" {
		detail, err := rd.detail(all, key, id)
		if err != nil {
			return nil, err
		}
		return detail, nil
	}
	return out, nil
}

// detail is one row with what points at it and the text of its note.
func (r *dbReader) detail(all map[string][]dbRow, key, id string) (map[string]any, error) {
	var row *dbRow
	for i := range all[key] {
		if all[key][i].ID == id {
			row = &all[key][i]
		}
	}
	if row == nil {
		return nil, errf(404, "not_found", "No está en la base de datos")
	}
	inbound := []dbLink{}
	for db, rows := range all {
		for _, x := range rows {
			for _, l := range x.Links {
				if l.DB == key && l.ID == id {
					inbound = append(inbound, dbLink{DB: db, ID: x.ID, Title: x.Title})
				}
			}
		}
	}
	sort.SliceStable(inbound, func(i, j int) bool { return inbound[i].DB+inbound[i].Title < inbound[j].DB+inbound[j].Title })
	body := ""
	if row.Path != "" && path.Ext(row.Path) == ".md" && !(r.actor.Type == "agent" && r.l.Private(row.Path)) {
		if data, err := r.read(row.Path); err == nil {
			_, b, _ := splitNote(data)
			if len(b) > 40_000 {
				b = b[:40_000] + "\n\n…"
			}
			body = strings.TrimSpace(b)
		}
	}
	return map[string]any{"row": row, "inbound": inbound, "body": body}, nil
}

// --- Opening in Obsidian -----------------------------------------------------------

// obsidianVaults are the vault folders Obsidian knows on this Mac.
func obsidianVaults() []string {
	home, _ := os.UserHomeDir()
	data, err := os.ReadFile(filepath.Join(home, "Library", "Application Support", "obsidian", "obsidian.json"))
	if err != nil {
		return nil
	}
	var cfg struct {
		Vaults map[string]struct {
			Path string `json:"path"`
		} `json:"vaults"`
	}
	if json.Unmarshal(data, &cfg) != nil {
		return nil
	}
	var out []string
	for _, v := range cfg.Vaults {
		if v.Path != "" {
			out = append(out, v.Path)
		}
	}
	return out
}

func inVault(full string, vaults []string) bool {
	for _, v := range vaults {
		if rel, err := filepath.Rel(v, full); err == nil && rel != ".." && !strings.HasPrefix(rel, "../") {
			return true
		}
	}
	return false
}

// postObsidian opens the original in Obsidian when the company folder is
// inside one of its vaults; otherwise it opens it with the Mac's default app
// and says so. Only for people, on the Mac that holds the folder.
func (s *Service) postObsidian(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
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
	if inVault(full, obsidianVaults()) {
		target := "obsidian://open?path=" + url.QueryEscape(full)
		if err := exec.CommandContext(ctx, "/usr/bin/open", target).Run(); err != nil {
			return nil, errf(500, "open_failed", "No se pudo abrir Obsidian: %v", err)
		}
		return map[string]any{"ok": true, "opened_with": "obsidian"}, nil
	}
	if err := exec.CommandContext(ctx, "/usr/bin/open", full).Run(); err != nil {
		return nil, errf(500, "open_failed", "No se pudo abrir: %v", err)
	}
	return map[string]any{"ok": true, "opened_with": "default"}, nil
}

func (s *Service) databaseRoutes(r chi.Router) {
	r.Get("/databases", s.handle(s.getDatabases))
	r.Get("/databases/{db}", s.handle(s.getDatabase))
	r.Post("/folder/obsidian", s.handle(s.postObsidian))
}
