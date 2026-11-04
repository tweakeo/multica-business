package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"os"
	"path"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
)

// The views of Dirección (MANU-60): the pace of invoicing against its target
// by week, month and quarter, the sales pipeline, the workload of people and
// agents, and the planning of internal projects. They read the same rows as
// «Bases de datos» (the folder is the source) and never write. What is not
// known is said so — a nil value is «sin datos», never a zero.

func (s *Service) vistasRoutes(r chi.Router) {
	r.Get("/ritmo", s.handle(s.getRitmo))
	r.Get("/pipeline", s.handle(s.getPipeline))
	r.Get("/carga", s.handle(s.getCarga))
	r.Get("/planificacion", s.handle(s.getPlanificacion))
}

// --- Amounts -------------------------------------------------------------------

var reAmount = regexp.MustCompile(`-?\d[\d.,]*`)

// parseEuros reads «4.560 €», «1202,70 euros», «-572,40 €» or «2.850». A dot
// followed by exactly three digits is a thousands separator; a comma is the
// decimal mark. Text without a number is no amount.
func parseEuros(s string) *float64 {
	m := reAmount.FindString(strings.ReplaceAll(s, " ", ""))
	if m == "" {
		return nil
	}
	m = strings.TrimRight(m, ".,")
	if strings.Contains(m, ",") {
		m = strings.ReplaceAll(m, ".", "")
		m = strings.ReplaceAll(m, ",", ".")
	} else if i := strings.LastIndex(m, "."); i >= 0 && len(m)-i-1 == 3 {
		m = strings.ReplaceAll(m, ".", "")
	}
	v, err := strconv.ParseFloat(m, 64)
	if err != nil {
		return nil
	}
	return &v
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

// --- Periods -------------------------------------------------------------------

var monthsES = []string{"ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"}

type periodKind string

const (
	perWeek    periodKind = "semana"
	perMonth   periodKind = "mes"
	perQuarter periodKind = "trimestre"
)

func periodStart(k periodKind, t time.Time) time.Time {
	d := dateOnly(t)
	switch k {
	case perWeek:
		wd := (int(d.Weekday()) + 6) % 7 // Monday = 0
		return d.AddDate(0, 0, -wd)
	case perQuarter:
		return time.Date(d.Year(), time.Month((int(d.Month())-1)/3*3+1), 1, 0, 0, 0, 0, time.UTC)
	}
	return time.Date(d.Year(), d.Month(), 1, 0, 0, 0, 0, time.UTC)
}

func periodNext(k periodKind, t time.Time) time.Time {
	switch k {
	case perWeek:
		return t.AddDate(0, 0, 7)
	case perQuarter:
		return t.AddDate(0, 3, 0)
	}
	return t.AddDate(0, 1, 0)
}

func bucketLabel(k periodKind, t time.Time) (key, label string) {
	switch k {
	case perWeek:
		y, w := t.ISOWeek()
		return fmt.Sprintf("%d-S%02d", y, w), fmt.Sprintf("S%d · %d %s", w, t.Day(), monthsES[t.Month()-1])
	case perQuarter:
		q := (int(t.Month())-1)/3 + 1
		return fmt.Sprintf("%d-T%d", t.Year(), q), fmt.Sprintf("T%d %d", q, t.Year())
	}
	return t.Format("2006-01"), fmt.Sprintf("%s %d", monthsES[t.Month()-1], t.Year())
}

// --- Ritmo: invoicing against its target ----------------------------------------

type issuedInvoice struct {
	Date   string   `json:"date"`
	Number string   `json:"number"`
	Party  string   `json:"party"`
	Amount *float64 `json:"amount"`
	Path   string   `json:"path"`
	ID     string   `json:"id"`
}

// issuedInvoices are the invoices The Last issued: the rows of emitidas.csv
// and the PDFs of Fiscal/…/Ingresos that have no row yet. Cancelled ones and
// drafts are left out; a credit note counts with its (negative) amount. The
// date of a PDF whose name has none comes from «Fechas de documentos.csv».
func (r *dbReader) issuedInvoices() (out []issuedInvoice, undated int) {
	dates := map[string]indexedDate{}
	if r.root != "" {
		dates = readDatesIndex(r.root, r.l.Areas["finanzas"])
	}
	for _, row := range r.facturas() {
		if row.get("Tipo") != "Emitida" {
			continue
		}
		st := headerKey(row.Status)
		if st == "registrada" || strings.HasPrefix(st, "anulad") || strings.HasPrefix(st, "borrador") {
			continue // registered: its row in emitidas.csv counts instead
		}
		inv := issuedInvoice{Number: firstNonEmpty(row.get("Número"), row.Title), Party: row.get("Tercero"), Amount: parseEuros(row.get("Importe")), Path: row.Path, ID: row.ID}
		if strings.HasPrefix(st, "rectificativ") && inv.Amount != nil && *inv.Amount > 0 {
			v := -*inv.Amount // the register keeps amounts positive; a credit note subtracts
			inv.Amount = &v
		}
		if strings.HasPrefix(row.Origin, "PDF") {
			date, _, _, _ := invoiceFromName(path.Base(row.Path))
			if date == "" {
				if d, ok := dates[row.Path]; ok && reISODay.MatchString(d.date) {
					date = d.date
				}
			}
			inv.Date = date
		} else {
			inv.Date = row.Date
		}
		if !reISODay.MatchString(inv.Date) {
			undated++
			continue
		}
		out = append(out, inv)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date < out[j].Date })
	return out, undated
}

type ritmoBucket struct {
	Key      string          `json:"key"`
	Label    string          `json:"label"`
	Start    string          `json:"start"`
	End      string          `json:"end"` // last day
	Current  bool            `json:"current"`
	Invoiced *float64        `json:"invoiced"` // euros; nil = sin datos
	Invoices int             `json:"invoices"`
	NoAmount int             `json:"no_amount"` // invoices whose amount is unknown
	Partial  bool            `json:"partial"`
	Reason   string          `json:"reason,omitempty"` // why there is no value
	Items    []issuedInvoice `json:"items"`
}

var periodTargetCode = map[periodKind]string{perWeek: "FAC-SEMANA", perMonth: "FAC-MES", perQuarter: "FAC-TRIMESTRE"}

func (s *Service) getRitmo(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	k := periodKind(r.URL.Query().Get("periodo"))
	if k != perWeek && k != perQuarter {
		k = perMonth
	}
	n := map[periodKind]int{perWeek: 12, perMonth: 12, perQuarter: 8}[k]
	if v, err := strconv.Atoi(r.URL.Query().Get("n")); err == nil && v > 0 && v <= 60 {
		n = v
	}
	rd, err := s.newDBReader(ctx, ws, a)
	if err != nil {
		return nil, err
	}
	return s.ritmo(ctx, ws, rd, k, n, time.Now().In(madridLoc())), nil
}

func (s *Service) ritmo(ctx context.Context, ws string, rd *dbReader, k periodKind, n int, now time.Time) map[string]any {
	invoices, undated := rd.issuedInvoices()
	first := ""
	if len(invoices) > 0 {
		first = invoices[0].Date
	}
	cur := periodStart(k, now)
	start := cur
	for i := 1; i < n; i++ {
		start = periodStart(k, start.AddDate(0, 0, -1))
	}
	buckets := []ritmoBucket{}
	for t := start; !t.After(cur); t = periodNext(k, t) {
		end := periodNext(k, t).AddDate(0, 0, -1)
		key, label := bucketLabel(k, t)
		b := ritmoBucket{Key: key, Label: label, Start: t.Format("2006-01-02"), End: end.Format("2006-01-02"), Current: t.Equal(cur), Items: []issuedInvoice{}}
		sum, known := 0.0, 0
		for _, inv := range invoices {
			if inv.Date < b.Start || inv.Date > b.End {
				continue
			}
			b.Invoices++
			b.Items = append(b.Items, inv)
			if inv.Amount == nil {
				b.NoAmount++
				continue
			}
			known++
			sum += *inv.Amount
		}
		switch {
		case first == "":
			b.Reason = "No hay facturas emitidas en la carpeta"
		case b.End < first:
			b.Reason = "Antes de la primera factura registrada"
		case b.Invoices > 0 && known == 0:
			b.Reason = "Facturas sin importe en el nombre ni en el registro"
		default:
			v := round2(sum)
			b.Invoiced = &v
			b.Partial = b.NoAmount > 0
		}
		buckets = append(buckets, b)
	}

	code := periodTargetCode[k]
	var target *float64
	metas, ok := s.kpiTargets(ctx, ws)
	if ok {
		target = metas[code].target
	}
	targetNote := "Sin objetivo de facturación. Para fijarlo, añade la fila «" + code + "» con su meta en «" + rd.l.metasFile() + "»."
	if !ok {
		targetNote = "Sin objetivo de facturación: esta empresa no tiene «Metas.md»."
	}
	if target != nil {
		targetNote = "Meta de «" + code + "» en «" + rd.l.metasFile() + "»."
	}

	objectives := []map[string]any{}
	y, q := quarterOf(now)
	if raw, err := listJSON(ctx, s.Pool, `SELECT o.id, o.area, o.period, o.title, o.kind, o.kpi_code, o.target, o.status
		FROM biz_objective o WHERE o.workspace_id=$1 AND o.archived_at IS NULL AND o.status IN ('active','achieved','missed') AND o.period=$2
		ORDER BY o.area, o.title`, ws, fmt.Sprintf("%d-T%d", y, q)); err == nil {
		_ = json.Unmarshal(raw, &objectives)
	}

	return map[string]any{
		"period":       k,
		"buckets":      buckets,
		"first_record": first,
		"undated":      undated,
		"target":       target,
		"target_code":  code,
		"target_note":  targetNote,
		"objectives":   objectives,
		"source":       "Facturas emitidas: «" + path.Join(rd.l.registersDir(), "emitidas.csv") + "» y los PDF de «" + path.Join(rd.l.Areas["finanzas"], "Fiscal") + "/…/Ingresos». Sin anuladas ni borradores; las rectificativas restan.",
		"configured":   rd.root != "",
	}
}

// --- Pipeline -----------------------------------------------------------------------

var pipelineStages = []string{"entrada", "cualificacion", "diagnostico", "propuesta", "negociacion", "aceptada", "ganada"}

// stageFromText maps the words a person or Notion used («Prospecto»,
// «Diagnóstico», «Propuesta enviada», «Archivada») to a stage of the
// pipeline and, for closed ones, how they ended.
func stageFromText(s string) (stage, outcome string) {
	k := headerKey(s)
	switch {
	case k == "":
		return "", ""
	case strings.Contains(k, "ganad"), strings.Contains(k, "cobrad"), strings.Contains(k, "firmad"):
		return "ganada", "ganada"
	case strings.Contains(k, "perdid"), strings.Contains(k, "descartad"), strings.Contains(k, "rechazad"):
		return "", "perdida"
	case strings.Contains(k, "archivad"), strings.Contains(k, "pausad"), strings.Contains(k, "aparcad"):
		return "", "archivada"
	case strings.Contains(k, "aceptad"):
		return "aceptada", ""
	case strings.Contains(k, "negoci"):
		return "negociacion", ""
	case strings.Contains(k, "propuesta"):
		return "propuesta", ""
	case strings.Contains(k, "diagnos"):
		return "diagnostico", ""
	case strings.Contains(k, "cualific"):
		return "cualificacion", ""
	case strings.Contains(k, "prospect"), strings.Contains(k, "entrada"), strings.Contains(k, "lead"), strings.Contains(k, "nuev"), strings.Contains(k, "interesad"):
		return "entrada", ""
	}
	return "", ""
}

func stageIndex(s string) int {
	for i, x := range pipelineStages {
		if x == s {
			return i
		}
	}
	return -1
}

type pipelineCard struct {
	ID       string   `json:"id"` // row id in «Bases de datos» › Oportunidades
	Title    string   `json:"title"`
	Client   string   `json:"client"`
	Stage    string   `json:"stage"`   // highest stage reached
	Outcome  string   `json:"outcome"` // "" open | ganada | perdida | archivada
	Status   string   `json:"status"`  // as written in the source
	Amount   *float64 `json:"amount"`  // euros; nil = sin importe
	Owner    string   `json:"owner"`
	Date     string   `json:"date"`
	Path     string   `json:"path"`
	Origin   string   `json:"origin"`
	Entity   string   `json:"entity,omitempty"`
	EntityID string   `json:"entity_id,omitempty"`
}

type pipelineStage struct {
	Key        string   `json:"key"`
	Count      int      `json:"count"`  // open now in this stage
	Amount     *float64 `json:"amount"` // known amounts of those; nil = none known
	NoAmount   int      `json:"no_amount"`
	Reached    int      `json:"reached"`    // opportunities that got at least here
	Conversion *float64 `json:"conversion"` // % reached here / reached the stage before
}

func (s *Service) getPipeline(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	rd, err := s.newDBReader(ctx, ws, a)
	if err != nil {
		return nil, err
	}
	return s.pipeline(ctx, ws, rd), nil
}

func (s *Service) pipeline(ctx context.Context, ws string, rd *dbReader) map[string]any {
	type appOpp struct {
		Stage string
		Value int64
		Owner string
		Title string
		Org   string
	}
	app := map[string]appOpp{}
	if rows, err := s.Pool.Query(ctx, `SELECT o.id::text, o.stage, coalesce(o.value_minor, 0), coalesce(ag.name, u.name, ''), o.title, coalesce(org.name, '')
		FROM biz_opportunity o LEFT JOIN biz_organization org ON org.id=o.organization_id
		LEFT JOIN agent ag ON o.owner_type='agent' AND ag.id=o.owner_id LEFT JOIN "user" u ON o.owner_type='member' AND u.id=o.owner_id
		WHERE o.workspace_id=$1 AND o.archived_at IS NULL`, ws); err == nil {
		for rows.Next() {
			var id string
			var x appOpp
			if rows.Scan(&id, &x.Stage, &x.Value, &x.Owner, &x.Title, &x.Org) == nil {
				app[id] = x
			}
		}
		rows.Close()
	}
	cards := []pipelineCard{}
	used := map[string]bool{}
	for _, row := range rd.oportunidades() {
		c := pipelineCard{ID: row.ID, Title: row.Title, Client: row.get("Cliente"), Status: row.Status, Owner: row.Owner, Date: row.Date, Path: row.Path, Origin: row.Origin, Entity: row.Entity, EntityID: row.EntityID}
		c.Stage, c.Outcome = stageFromText(row.Status)
		if src, _ := stageFromText(row.get("Estado en la fuente")); src != "" && (c.Stage == "" || c.Outcome != "") && c.Outcome != "ganada" {
			c.Stage = src // where a closed one got to
		}
		if strings.HasPrefix(row.Origin, "Carpeta de propuesta") {
			c.Stage = "propuesta" // a folder with a proposal reached Propuesta
		}
		if n, ok := rd.note(row.Path); ok && n != nil {
			c.Amount = parseEuros(n.field("importe", "valor", "precio", "value", "amount"))
		}
		if x, ok := app[row.EntityID]; ok && row.EntityID != "" {
			used[row.EntityID] = true
			if c.Amount == nil && x.Value > 0 {
				v := float64(x.Value) / 100
				c.Amount = &v
			}
			if c.Stage == "" && c.Outcome == "" {
				c.Stage, c.Outcome = stageFromText(x.Stage)
			}
			if c.Owner == "" {
				c.Owner = x.Owner
			}
		}
		if c.Stage == "" {
			c.Stage = "entrada"
		}
		cards = append(cards, c)
	}
	// What only the app knows (an opportunity created there and not yet
	// written to the folder) is in the pipeline too.
	for id, x := range app {
		if used[id] {
			continue
		}
		c := pipelineCard{ID: id, Title: x.Title, Client: x.Org, Status: x.Stage, Owner: x.Owner, Origin: "Oportunidad de la app", Entity: "opportunity", EntityID: id}
		c.Stage, c.Outcome = stageFromText(x.Stage)
		if c.Stage == "" {
			c.Stage = "entrada"
		}
		if x.Value > 0 {
			v := float64(x.Value) / 100
			c.Amount = &v
		}
		cards = append(cards, c)
	}
	sort.SliceStable(cards, func(i, j int) bool { return cards[i].Date > cards[j].Date })

	stages := make([]pipelineStage, len(pipelineStages))
	for i, k := range pipelineStages {
		stages[i].Key = k
	}
	won, lost, archived := 0, 0, 0
	var openAmount float64
	openKnown, openNoAmount, open := 0, 0, 0
	for _, c := range cards {
		idx := stageIndex(c.Stage)
		for i := 0; i <= idx; i++ {
			stages[i].Reached++
		}
		switch c.Outcome {
		case "ganada":
			won++
			continue
		case "perdida":
			lost++
			continue
		case "archivada":
			archived++
			continue
		}
		open++
		st := &stages[idx]
		st.Count++
		if c.Amount == nil {
			st.NoAmount++
			openNoAmount++
			continue
		}
		openKnown++
		openAmount += *c.Amount
		v := *c.Amount
		if st.Amount != nil {
			v += *st.Amount
		}
		st.Amount = &v
	}
	for i := 1; i < len(stages); i++ {
		if stages[i-1].Reached > 0 {
			v := math.Round(float64(stages[i].Reached) / float64(stages[i-1].Reached) * 100)
			stages[i].Conversion = &v
		}
	}
	// Archived ones were parked, not lost: the rate is won over won + lost.
	var winRate *float64
	if won+lost > 0 {
		v := math.Round(float64(won) / float64(won+lost) * 100)
		winRate = &v
	}
	var openValue *float64
	if openKnown > 0 {
		v := round2(openAmount)
		openValue = &v
	}
	return map[string]any{
		"stages":         stages,
		"cards":          cards,
		"open":           open,
		"open_amount":    openValue,
		"open_no_amount": openNoAmount,
		"won":            won,
		"lost":           lost,
		"archived":       archived,
		"win_rate":       winRate,
		"source":         "BBDD de Oportunidades: notas y carpetas de propuesta de «" + rd.l.dir("opportunity") + "», más las oportunidades que solo están en la app.",
		"configured":     rd.root != "",
	}
}

// --- Workload ------------------------------------------------------------------------

// Capacidad.md (6 · Equipo) is where a person writes how much each one can
// carry at the same time: «| Quién | Capacidad | Unidad | Nota |». The app
// only reads it; without it the capacity is «sin definir».
func (l Layout) capacityFile() string { return path.Join(l.Areas["equipo"], "Capacidad.md") }

type capacityRow struct {
	value *float64
	unit  string
	note  string
}

func parseCapacity(text string) map[string]capacityRow {
	out := map[string]capacityRow{}
	t := findTable(text, "quien")
	for _, cells := range t.rows() {
		who := strings.Trim(t.col(cells, "quien"), "*` ")
		if who == "" {
			continue
		}
		out[headerKey(who)] = capacityRow{value: metaNumber(t.col(cells, "capacidad")), unit: t.col(cells, "unidad"), note: t.col(cells, "nota")}
	}
	return out
}

type workItem struct {
	Kind    string `json:"kind"` // tarea | sesion | incidencia | proyecto
	Title   string `json:"title"`
	Project string `json:"project,omitempty"`
	Date    string `json:"date,omitempty"`
	Overdue bool   `json:"overdue,omitempty"`
	DB      string `json:"db"`
	ID      string `json:"id"`
}

type workload struct {
	Name         string     `json:"name"`
	Kind         string     `json:"kind"` // persona | agente | sin_asignar
	Detail       string     `json:"detail,omitempty"`
	Capacity     *float64   `json:"capacity"`
	Unit         string     `json:"unit"`
	CapacityNote string     `json:"capacity_note,omitempty"`
	Assigned     *float64   `json:"assigned"` // open items; nil = sin datos
	Visible      bool       `json:"visible"`  // the app sees all its work
	Note         string     `json:"note,omitempty"`
	Counts       []kv       `json:"counts"`
	Items        []workItem `json:"items"`
	Load         *float64   `json:"load"` // % assigned / capacity
}

type kv struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Value int    `json:"value"`
}

func doneStatus(s string) bool {
	k := headerKey(s)
	return strings.HasPrefix(k, "hech") || strings.HasPrefix(k, "done") || strings.HasPrefix(k, "cancel") || strings.HasPrefix(k, "cerrad") ||
		strings.HasPrefix(k, "complet") || strings.HasPrefix(k, "resuelt") || strings.HasPrefix(k, "terminad")
}

func (s *Service) getCarga(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	rd, err := s.newDBReader(ctx, ws, a)
	if err != nil {
		return nil, err
	}
	return s.carga(ctx, ws, rd), nil
}

func (s *Service) carga(ctx context.Context, ws string, rd *dbReader) map[string]any {
	today := rd.now.In(madridLoc()).Format("2006-01-02")
	horizon := rd.now.In(madridLoc()).AddDate(0, 0, 14).Format("2006-01-02")
	caps := map[string]capacityRow{}
	capFound := false
	if data, err := rd.read(rd.l.capacityFile()); err == nil {
		caps, capFound = parseCapacity(string(data)), true
	}
	// Example projects (`demo: true`) do not load anybody.
	demo := map[string]bool{}
	if rd.root != "" {
		for _, p := range listPortals(rd.root, rd.l, rd.now) {
			if p.Demo {
				demo[p.Path] = true
			}
		}
	}
	isDemo := func(row dbRow) bool {
		for _, ref := range row.refs {
			if demo[ref] {
				return true
			}
		}
		return demo[row.Path]
	}

	people := []*workload{}
	byKey := map[string]*workload{}
	addWho := func(w *workload, keys ...string) {
		people = append(people, w)
		for _, k := range keys {
			if k = headerKey(k); k != "" {
				if _, ok := byKey[k]; !ok {
					byKey[k] = w
				}
			}
		}
	}
	for _, row := range rd.equipo() {
		if strings.HasPrefix(row.ID, "member:") {
			first := strings.Fields(row.Title)
			keys := []string{row.Title, row.get("Email")}
			if len(first) > 0 {
				keys = append(keys, first[0])
			}
			addWho(&workload{Name: row.Title, Kind: "persona", Detail: row.get("Rol"), Visible: true}, keys...)
			continue
		}
		if closedState(row.Status) {
			continue
		}
		addWho(&workload{Name: row.Title, Kind: "persona", Detail: firstNonEmpty(row.get("Rol"), "Colaboración"), Visible: true}, row.Title)
	}
	appAgents := map[string]bool{}
	if rows, err := s.Pool.Query(ctx, `SELECT name FROM agent WHERE workspace_id=$1 AND archived_at IS NULL`, ws); err == nil {
		for rows.Next() {
			var n string
			if rows.Scan(&n) == nil {
				appAgents[headerKey(n)] = true
			}
		}
		rows.Close()
	}
	for _, row := range rd.agentes() {
		inApp := appAgents[headerKey(row.Title)]
		w := &workload{Name: row.Title, Kind: "agente", Detail: firstNonEmpty(row.get("Áreas"), row.Status), Visible: inApp}
		if !inApp {
			w.Note = "Trabaja en Multica: sus issues no llegan a esta app."
		}
		addWho(w, row.Title)
	}
	unassigned := &workload{Name: "Sin asignar", Kind: "sin_asignar", Visible: true, Detail: "Trabajo abierto sin responsable"}

	assign := func(owner string, it workItem) {
		w := byKey[headerKey(owner)]
		if w == nil && owner != "" {
			if f := strings.Fields(owner); len(f) > 0 {
				w = byKey[headerKey(f[0])]
			}
		}
		if w == nil && headerKey(owner) == "cliente" {
			return // the client's own tasks are not The Last's load
		}
		if w == nil && owner != "" {
			w = &workload{Name: owner, Kind: "persona", Detail: "Aparece como responsable; no está en Equipo", Visible: true}
			addWho(w, owner)
		}
		if w == nil {
			w = unassigned
		}
		w.Items = append(w.Items, it)
	}
	for _, row := range rd.tareas() {
		if isDemo(row) || doneStatus(row.Status) {
			continue
		}
		due := row.get("Vence")
		assign(row.Owner, workItem{Kind: "tarea", Title: row.Title, Project: row.get("Proyecto"), Date: due, Overdue: due != "" && due < today, DB: "tareas", ID: row.ID})
	}
	for _, row := range rd.reuniones() {
		if isDemo(row) || row.Date == "" || row.Date < today || row.Date > horizon || sessionState(row.Status) == "hecha" || sessionState(row.Status) == "no_incluida" {
			continue
		}
		assign(row.Owner, workItem{Kind: "sesion", Title: row.Title, Project: row.get("Proyecto"), Date: row.Date, DB: "reuniones", ID: row.ID})
	}
	for _, row := range rd.incidencias() {
		if isDemo(row) || !incidentOpen(row.Status) {
			continue
		}
		assign(row.Owner, workItem{Kind: "incidencia", Title: row.Title, Project: row.get("Proyecto"), Date: row.Date, DB: "incidencias", ID: row.ID})
	}
	for _, row := range rd.proyectos() {
		if isDemo(row) || row.get("Demo") != "" || closedState(row.Status) || doneStatus(row.Status) || headerKey(row.Status) == "planned" {
			continue
		}
		if row.Owner == "" && row.Origin == "Expediente de la carpeta" {
			row.Owner = "Manu" // the expedientes are Manu's unless the note says otherwise
		}
		assign(row.Owner, workItem{Kind: "proyecto", Title: row.Title, Date: row.Date, DB: "proyectos", ID: row.ID})
	}

	labels := []kv{{"tarea", "Tareas abiertas", 0}, {"sesion", "Sesiones (14 días)", 0}, {"incidencia", "Incidencias abiertas", 0}, {"proyecto", "Proyectos en curso", 0}}
	finish := func(w *workload) {
		w.Counts = make([]kv, len(labels))
		copy(w.Counts, labels)
		for _, it := range w.Items {
			for i := range w.Counts {
				if w.Counts[i].Key == it.Kind {
					w.Counts[i].Value++
				}
			}
		}
		if w.Items == nil {
			w.Items = []workItem{}
		}
		if c, ok := caps[headerKey(w.Name)]; ok {
			w.Capacity, w.Unit, w.CapacityNote = c.value, c.unit, c.note
		}
		if w.Unit == "" {
			w.Unit = "a la vez"
		}
		if len(w.Items) > 0 || w.Visible {
			v := float64(len(w.Items))
			w.Assigned = &v
		}
		if w.Assigned != nil && w.Capacity != nil && *w.Capacity > 0 {
			v := math.Round(*w.Assigned / *w.Capacity * 100)
			w.Load = &v
		}
	}
	out := []*workload{}
	for _, w := range people {
		finish(w)
		out = append(out, w)
	}
	finish(unassigned)
	if len(unassigned.Items) > 0 {
		out = append(out, unassigned)
	}
	capNote := "Capacidad leída de «" + rd.l.capacityFile() + "»."
	if !capFound {
		capNote = "Capacidad sin definir: crea «" + rd.l.capacityFile() + "» con la tabla «| Quién | Capacidad | Unidad | Nota |» (por ejemplo, «Manu | 5 | tareas a la vez»)."
	}
	return map[string]any{
		"people":        out,
		"capacity_note": capNote,
		"capacity_file": rd.l.capacityFile(),
		"has_capacity":  capFound,
		"source":        "Tareas (app, Tareas.md), sesiones de los próximos 14 días, incidencias abiertas y proyectos en curso de «Bases de datos». Sin el proyecto de ejemplo ni las tareas del cliente.",
		"configured":    rd.root != "",
	}
}

// --- Internal planning -----------------------------------------------------------------

// internalDir is where Dirección keeps its internal projects, one note each:
// estado, inicio, fin, responsable, área, and a «- [ ]» checklist of steps.
func (l Layout) internalDir() string { return path.Join(l.Areas["direccion"], "Proyectos internos") }

type internalProject struct {
	ID       string `json:"id"`
	DB       string `json:"db,omitempty"` // «Bases de datos» key when the row lives there
	Title    string `json:"title"`
	Status   string `json:"status"`
	Closed   bool   `json:"closed"`
	Area     string `json:"area"`
	Owner    string `json:"owner"`
	Start    string `json:"start"`
	End      string `json:"end"`
	Steps    int    `json:"steps"`
	Done     int    `json:"done"`
	Next     string `json:"next,omitempty"`
	Path     string `json:"path,omitempty"`
	Origin   string `json:"origin"`
	EntityID string `json:"entity_id,omitempty"`
}

var reInternal = regexp.MustCompile(`(?i)\bproyecto interno\b`)

func checklist(text string) (steps, done int, next string) {
	for _, ln := range strings.Split(text, "\n") {
		m := reTaskLine.FindStringSubmatch(ln)
		if m == nil {
			continue
		}
		steps++
		if m[1] != " " {
			done++
		} else if next == "" {
			next = strings.TrimSpace(m[2])
		}
	}
	return
}

func (s *Service) getPlanificacion(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	rd, err := s.newDBReader(ctx, ws, a)
	if err != nil {
		return nil, err
	}
	return s.planificacion(ctx, ws, rd), nil
}

func (s *Service) planificacion(ctx context.Context, ws string, rd *dbReader) map[string]any {
	out := []internalProject{}
	for _, n := range rd.notesIn(rd.l.internalDir()) {
		p := internalProject{ID: n.rel, Title: n.title, Status: n.field("estado", "status"), Owner: n.field("responsable"), Path: n.rel, Origin: "Nota de Proyectos internos",
			Start: n.field("inicio", "fecha_inicio", "start"), End: n.field("fin", "fecha_fin", "fecha_objetivo", "vence", "end")}
		p.Area = firstNonEmpty(rd.areaFromText(n.field("area", "área")), "direccion")
		p.Steps, p.Done, p.Next = checklist(n.body)
		out = append(out, p)
	}
	if rd.root != "" {
		for _, pr := range listPortals(rd.root, rd.l, rd.now) {
			if pr.Demo {
				continue
			}
			n, ok := rd.note(pr.Path)
			if !ok || n == nil {
				continue
			}
			kind := headerKey(n.field("tipo", "kind"))
			flag, _ := n.front["interno"].(bool)
			if !(flag || kind == "interno" || kind == "internal" || reInternal.MatchString(n.body)) {
				continue
			}
			p := internalProject{ID: pr.Path, DB: "proyectos", Title: pr.Title, Status: pr.State, Owner: n.field("responsable"), Path: pr.Path, Area: "entrega", Origin: "Expediente marcado como interno",
				Start: n.field("fecha_inicio", "inicio"), End: n.field("fecha_cierre", "fin", "fecha_fin")}
			if data, err := rd.read(path.Join(path.Dir(pr.Path), "Tareas.md")); err == nil {
				p.Steps, p.Done, p.Next = checklist(string(data))
			}
			out = append(out, p)
		}
	}
	if rows, err := s.Pool.Query(ctx, `SELECT p.id::text, p.title, p.status, coalesce(p.start_date::text, p.created_at::date::text), coalesce(p.due_date::text, ''), coalesce(ag.name, u.name, ''),
		(SELECT count(*) FROM issue i WHERE i.project_id=p.id), (SELECT count(*) FROM issue i WHERE i.project_id=p.id AND i.status IN ('done','cancelled')),
		coalesce(o.area, 'direccion')
		FROM project p JOIN biz_project_link l ON l.project_id=p.id LEFT JOIN biz_objective o ON o.id=l.objective_id
		LEFT JOIN agent ag ON p.lead_type='agent' AND ag.id=p.lead_id LEFT JOIN "user" u ON p.lead_type='member' AND u.id=p.lead_id
		WHERE p.workspace_id=$1 AND l.kind IN ('strategic','compliance') ORDER BY p.created_at`, ws); err == nil {
		for rows.Next() {
			var p internalProject
			if rows.Scan(&p.ID, &p.Title, &p.Status, &p.Start, &p.End, &p.Owner, &p.Steps, &p.Done, &p.Area) == nil {
				p.Origin, p.EntityID, p.DB = "Proyecto de la app (estratégico o de cumplimiento)", p.ID, "proyectos"
				out = append(out, p)
			}
		}
		rows.Close()
	}
	for i := range out {
		p := &out[i]
		p.Closed = closedState(p.Status) || doneStatus(p.Status) || headerKey(p.Status) == "completed"
		p.Start, p.End = dayOf(p.Start), dayOf(p.End)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Closed != out[j].Closed {
			return !out[i].Closed
		}
		return firstNonEmpty(out[i].End, "9999") < firstNonEmpty(out[j].End, "9999")
	})
	return map[string]any{
		"projects":   out,
		"folder":     rd.l.internalDir(),
		"fill":       "Una nota por proyecto interno en «" + rd.l.internalDir() + "/» con «estado», «inicio», «fin» y «responsable» en el frontmatter y sus pasos como «- [ ] …». Un expediente de Entrega cuenta como interno con «tipo: interno» o si dice «Proyecto interno».",
		"configured": rd.root != "",
		"folder_exists": func() bool {
			if rd.root == "" {
				return false
			}
			st, err := os.Stat(rd.full(rd.l.internalDir()))
			return err == nil && st.IsDir()
		}(),
	}
}

// dayOf keeps AAAA-MM-DD (or AAAA-MM) of a date written by a person.
func dayOf(s string) string {
	s = strings.Trim(strings.TrimSpace(s), "'\"")
	if len(s) >= 10 && reISODay.MatchString(s[:10]) {
		return s[:10]
	}
	if len(s) >= 7 && reISOMonth.MatchString(s[:7]) {
		return s[:7]
	}
	return ""
}
