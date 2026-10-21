package biz

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"gopkg.in/yaml.v3"
)

// Rules for a folder a person also edits:
//   - human text is never overwritten: once a note is not exactly what TLS
//     last wrote (or TLS never wrote it), only its frontmatter is updated;
//   - nothing is deleted: a file that has to leave its place moves to Archivo/;
//   - registers (Registros/*.csv) are shared with people: rows are updated in
//     place by id, other rows and columns are kept as they are.

var errNoFrontmatter = errors.New("sin frontmatter")

// splitNote returns the frontmatter text and the body exactly as stored.
func splitNote(data []byte) (front string, body string, ok bool) {
	text := string(data)
	if !strings.HasPrefix(text, "---\n") {
		return "", text, false
	}
	end := strings.Index(text[4:], "\n---\n")
	if end < 0 {
		if strings.HasSuffix(text, "\n---") {
			return text[4 : len(text)-4], "", true
		}
		return "", text, false
	}
	return text[4 : 4+end], text[4+end+5:], true
}

// mergeNote updates the given keys in the note's frontmatter, keeping key
// order, comments, every other key and the body byte for byte. A key a person
// wrote with its Spanish alias (nombre, titulo…) keeps the alias.
func mergeNote(old []byte, front map[string]any) ([]byte, error) {
	fm, body, ok := splitNote(old)
	if !ok && strings.HasPrefix(string(old), "---\n") {
		return nil, fmt.Errorf("frontmatter sin cerrar")
	}
	var doc yaml.Node
	if strings.TrimSpace(fm) != "" {
		if err := yaml.Unmarshal([]byte(fm), &doc); err != nil {
			return nil, fmt.Errorf("YAML no válido: %v", err)
		}
	}
	if len(doc.Content) == 0 {
		doc = yaml.Node{Kind: yaml.DocumentNode, Content: []*yaml.Node{{Kind: yaml.MappingNode, Tag: "!!map"}}}
	}
	mapping := doc.Content[0]
	if mapping.Kind != yaml.MappingNode {
		return nil, fmt.Errorf("el frontmatter no es un mapa")
	}
	find := func(key string) int {
		for i := 0; i+1 < len(mapping.Content); i += 2 {
			if mapping.Content[i].Value == key {
				return i
			}
		}
		return -1
	}
	keys := make([]string, 0, len(front))
	for k := range front {
		keys = append(keys, k)
	}
	sortKeys(keys)
	for _, k := range keys {
		i := find(k)
		if i < 0 {
			for alias, col := range fieldAliases {
				if col == k {
					if j := find(alias); j >= 0 {
						i = j
						break
					}
				}
			}
		}
		var val yaml.Node
		if err := val.Encode(front[k]); err != nil {
			return nil, err
		}
		if i >= 0 {
			mapping.Content[i+1] = &val
			continue
		}
		mapping.Content = append(mapping.Content, &yaml.Node{Kind: yaml.ScalarNode, Value: k}, &val)
	}
	var buf bytes.Buffer
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(&doc); err != nil {
		return nil, err
	}
	_ = enc.Close()
	out := "---\n" + buf.String() + "---\n"
	if !ok && body != "" {
		out += "\n" // a note that had no frontmatter keeps its text under it
	}
	return []byte(out + body), nil
}

// sortKeys puts the identity keys first so new notes read well.
func sortKeys(keys []string) {
	rank := map[string]int{"tls_type": 0, "tls_schema": 1, "id": 2}
	less := func(a, b string) bool {
		ra, oka := rank[a]
		rb, okb := rank[b]
		switch {
		case oka && okb:
			return ra < rb
		case oka:
			return true
		case okb:
			return false
		}
		return a < b
	}
	for i := 1; i < len(keys); i++ {
		for j := i; j > 0 && less(keys[j], keys[j-1]); j-- {
			keys[j], keys[j-1] = keys[j-1], keys[j]
		}
	}
}

func exists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// retire moves a file to Archivo/<same path>. It never overwrites: a name
// already taken in Archivo gets « (2)», « (3)»…
func retire(root string, l Layout, rel string) (string, error) {
	dst := path.Join(l.Archivo, filepath.ToSlash(rel))
	ext := path.Ext(dst)
	for n := 2; exists(filepath.Join(root, filepath.FromSlash(dst))); n++ {
		dst = strings.TrimSuffix(path.Join(l.Archivo, filepath.ToSlash(rel)), ext) + fmt.Sprintf(" (%d)", n) + ext
	}
	if err := os.MkdirAll(filepath.Dir(filepath.Join(root, filepath.FromSlash(dst))), 0o755); err != nil {
		return "", err
	}
	return dst, os.Rename(filepath.Join(root, filepath.FromSlash(rel)), filepath.Join(root, filepath.FromSlash(dst)))
}

func isUUID(s string) bool {
	_, err := uuid.Parse(s)
	return err == nil
}

// --- One append-only decisions file ------------------------------------------

const decisionMark = "<!-- tls:decision "

// decisionLine is what a person reads plus the full record in a comment, so
// the file can rebuild the projection. The JSON is HTML-escaped, so a "-->"
// inside a text can never close the comment.
func decisionLine(m map[string]any) (string, error) {
	rec := map[string]any{}
	for k, v := range m {
		if k != "workspace_id" {
			rec[k] = v
		}
	}
	raw, err := json.Marshal(rec)
	if err != nil {
		return "", err
	}
	day := str(m["decided_at"])
	if day == "" {
		day = str(m["created_at"])
	}
	if len(day) >= 10 {
		day = day[:10]
	}
	safe := strings.NewReplacer("<!--", "<!-", "-->", "->")
	flat := func(k string) string { return safe.Replace(strings.Join(strings.Fields(str(m[k])), " ")) }
	visible := fmt.Sprintf("- %s · %s: %s · %s · %s · TLS", day, flat("title"), flat("decision"), flat("why"), flat("purpose"))
	switch str(m["status"]) {
	case "open":
		visible = fmt.Sprintf("- %s · %s (abierta) · %s · TLS", day, flat("title"), flat("context"))
	case "superseded":
		visible += " (sustituida)"
	}
	return visible + " " + decisionMark + string(raw) + " -->", nil
}

func parseDecisionLine(line string) map[string]any {
	i := strings.Index(line, decisionMark)
	j := strings.LastIndex(line, "-->")
	if i < 0 || j < i {
		return nil
	}
	var m map[string]any
	if json.Unmarshal([]byte(strings.TrimSpace(line[i+len(decisionMark):j])), &m) != nil {
		return nil
	}
	return m
}

const decisionsHeader = "# Decisiones\n\nRegistro append-only. Fecha · decisión · motivo · alcance · fuente.\n\n"

// writeDecisionLine replaces the decision's own line or appends a new one.
// Every other line of the file is left untouched.
func writeDecisionLine(root string, l Layout, m map[string]any) (string, string, error) {
	rel := l.decisionsFile()
	target := filepath.Join(root, filepath.FromSlash(rel))
	old, err := os.ReadFile(target)
	if os.IsNotExist(err) {
		old, err = []byte(decisionsHeader), nil
	}
	if err != nil {
		return "", "", err
	}
	line, err := decisionLine(m)
	if err != nil {
		return "", "", err
	}
	id := str(m["id"])
	lines := strings.Split(string(old), "\n")
	found := false
	for i, ln := range lines {
		if rec := parseDecisionLine(ln); rec != nil && str(rec["id"]) == id {
			lines[i], found = line, true
		}
	}
	text := strings.Join(lines, "\n")
	if !found {
		text = strings.TrimRight(text, "\n") + "\n" + line + "\n"
	}
	if err := atomicWrite(target, []byte(text)); err != nil {
		return "", "", err
	}
	return rel + "#" + id, hashBytes([]byte(line)), nil
}

func scanDecisions(rel string, data []byte) []*folderRecord {
	var out []*folderRecord
	for _, ln := range strings.Split(string(data), "\n") {
		m := parseDecisionLine(ln)
		if m == nil || str(m["id"]) == "" {
			continue
		}
		out = append(out, &folderRecord{Path: rel + "#" + str(m["id"]), Type: "decision", ID: str(m["id"]), Front: m, Body: str(m["context"]), Hash: hashBytes([]byte(ln))})
	}
	return out
}

// --- Shared registers (Registros/*.csv) --------------------------------------

// Fixed headers from Registros/Esquema.md: comma, ISO dates, decimal point.
var registerHeaders = map[string][]string{
	"emitidas.csv":  {"id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento", "documento", "ambito", "proyecto_id", "estado_emision", "fuente"},
	"recibidas.csv": {"id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento", "documento", "ambito", "proyecto_id", "estado_revision", "fuente"},
	"pagos.csv":     {"id", "fecha", "direccion", "importe", "moneda", "cuenta", "documento_id", "proyecto_id", "evidencia", "verificacion"},
}

type register struct {
	header []string
	rows   [][]string
}

func (r register) col(name string) int {
	for i, h := range r.header {
		if h == name {
			return i
		}
	}
	return -1
}

func (r register) get(row []string, name string) string {
	if i := r.col(name); i >= 0 && i < len(row) {
		return strings.TrimSpace(row[i])
	}
	return ""
}

func readRegister(p string) (register, error) {
	data, err := os.ReadFile(p)
	if err != nil {
		return register{}, err
	}
	data = bytes.TrimPrefix(data, []byte("\xef\xbb\xbf"))
	r := csv.NewReader(bytes.NewReader(data))
	r.FieldsPerRecord = -1
	all, err := r.ReadAll()
	if err != nil {
		return register{}, fmt.Errorf("%s: %v", filepath.Base(p), err)
	}
	if len(all) == 0 {
		return register{}, nil
	}
	reg := register{header: all[0], rows: all[1:]}
	for i := range reg.rows {
		for len(reg.rows[i]) < len(reg.header) {
			reg.rows[i] = append(reg.rows[i], "")
		}
	}
	return reg, nil
}

func rowHash(row []string) string { return hashBytes([]byte(strings.Join(row, ","))) }

// upsertRow updates the row with this id or appends it. Values the app owns
// overwrite only when known; defaults fill a new row. The header and every
// other row stay as they are; a file that cannot be parsed is not touched.
func upsertRow(p string, header []string, id string, own, defaults map[string]string) (string, error) {
	reg, err := readRegister(p)
	if err != nil && !os.IsNotExist(err) {
		return "", err
	}
	if reg.header == nil {
		reg.header = header
	}
	idc := reg.col("id")
	if idc < 0 {
		return "", fmt.Errorf("%s no tiene columna id", filepath.Base(p))
	}
	at := -1
	for i, row := range reg.rows {
		if strings.TrimSpace(row[idc]) == id {
			at = i
		}
	}
	if at < 0 {
		row := make([]string, len(reg.header))
		row[idc] = id
		for k, v := range defaults {
			if i := reg.col(k); i >= 0 {
				row[i] = v
			}
		}
		reg.rows = append(reg.rows, row)
		at = len(reg.rows) - 1
	}
	for k, v := range own {
		if i := reg.col(k); i >= 0 && v != "" {
			reg.rows[at][i] = v
		}
	}
	var buf bytes.Buffer
	w := csv.NewWriter(&buf)
	_ = w.Write(reg.header)
	_ = w.WriteAll(reg.rows)
	if err := w.Error(); err != nil {
		return "", err
	}
	if err := atomicWrite(p, buf.Bytes()); err != nil {
		return "", err
	}
	return rowHash(reg.rows[at]), nil
}

func decimalPoint(minor int64) string {
	sign := ""
	if minor < 0 {
		sign, minor = "-", -minor
	}
	return fmt.Sprintf("%s%d.%02d", sign, minor/100, minor%100)
}

func minorOf(v any) int64 {
	switch t := v.(type) {
	case float64:
		return int64(t)
	case int64:
		return t
	case int:
		return int64(t)
	}
	return 0
}

// writeRegisterRow keeps emitidas/recibidas/pagos in step with the record.
// Drafts and unconfirmed payments are not registered (Esquema.md). For a
// payment, the row is its only home: it returns the row path and hash.
func (f *Folder) writeRegisterRow(ctx context.Context, root string, l Layout, typ string, m map[string]any) (string, string, error) {
	regs := l.registersDir()
	attrs, _ := m["attrs"].(map[string]any)
	switch typ {
	case "invoice":
		status := str(m["status"])
		if m["number"] == nil || status == "draft" {
			return "", "", nil
		}
		id := str(attrs["registro_id"])
		if id == "" {
			id = str(m["id"])
		}
		file, own := "recibidas.csv", map[string]string{}
		if str(m["direction"]) == "issued" {
			file = "emitidas.csv"
			own["estado_emision"] = map[string]string{"void": "anulada", "rectified": "rectificada"}[status]
			if own["estado_emision"] == "" {
				own["estado_emision"] = "emitida"
			}
		}
		if org := str(m["organization_id"]); org != "" {
			own["tercero"] = f.lookupName(ctx)("organization", org)
		}
		if doc := str(m["document_id"]); doc != "" {
			var docRel string
			_ = f.svc.Pool.QueryRow(ctx, `SELECT rel_path FROM biz_document WHERE id=$1`, doc).Scan(&docRel)
			if r, err := filepath.Rel(filepath.FromSlash(regs), filepath.FromSlash(docRel)); err == nil && docRel != "" {
				own["documento"] = filepath.ToSlash(r)
			}
		}
		own["fecha_documento"] = str(m["issue_date"])
		own["numero_documento"] = str(m["number"])
		own["moneda"] = str(m["currency"])
		own["total_documento"] = decimalPoint(minorOf(m["total_minor"]))
		own["proyecto_id"] = str(m["project_id"])
		ambito := str(attrs["ambito"])
		if ambito == "" {
			ambito = "The Last"
		}
		_, err := upsertRow(filepath.Join(root, filepath.FromSlash(regs), file), registerHeaders[file], id, own,
			map[string]string{"ambito": ambito, "fuente": "TLS", "estado_revision": "pendiente"})
		return "", "", err
	case "payment":
		if str(m["status"]) != "confirmed" {
			return "", "", nil
		}
		var direction, currency, project, regID, account string
		_ = f.svc.Pool.QueryRow(ctx, `SELECT direction, currency, coalesce(project_id::text,''), coalesce(attrs->>'registro_id','') FROM biz_invoice WHERE id=$1`,
			str(m["invoice_id"])).Scan(&direction, &currency, &project, &regID)
		if mv := str(m["movement_id"]); mv != "" {
			_ = f.svc.Pool.QueryRow(ctx, `SELECT a.name FROM biz_bank_movement m JOIN biz_bank_account a ON a.id=m.account_id WHERE m.id=$1`, mv).Scan(&account)
		}
		if regID == "" {
			regID = str(m["invoice_id"])
		}
		dir := "pago"
		if direction == "issued" {
			dir = "cobro"
		}
		amount := minorOf(m["amount_minor"])
		if amount < 0 {
			amount = -amount
		}
		rel := path.Join(regs, "pagos.csv")
		hash, err := upsertRow(filepath.Join(root, filepath.FromSlash(rel)), registerHeaders["pagos.csv"], str(m["id"]), map[string]string{
			"fecha": str(m["paid_on"]), "direccion": dir, "importe": decimalPoint(amount), "moneda": currency, "cuenta": account,
			"documento_id": regID, "proyecto_id": project, "evidencia": str(m["evidence"]), "verificacion": "confirmado",
		}, nil)
		if err != nil {
			return "", "", err
		}
		return rel + "#" + str(m["id"]), hash, nil
	}
	return "", "", nil
}

// scanPayments reads app payments from pagos.csv when the register is their
// only home. Rows with a person's own id (PAG-…) are reported by
// registerReport, not read as app records.
func scanPayments(rel string, reg register) []*folderRecord {
	var out []*folderRecord
	for _, row := range reg.rows {
		id := reg.get(row, "id")
		if !isUUID(id) {
			continue
		}
		front := map[string]any{"id": id, "invoice_id": reg.get(row, "documento_id"), "paid_on": reg.get(row, "fecha"), "evidence": reg.get(row, "evidencia")}
		if amount, err := parseAmount(reg.get(row, "importe")); err == nil {
			front["amount_minor"] = float64(amount)
		}
		if reg.get(row, "verificacion") == "confirmado" {
			front["status"] = "confirmed"
		}
		out = append(out, &folderRecord{Path: rel + "#" + id, Type: "payment", ID: id, Front: front, Hash: rowHash(row)})
	}
	return out
}

// registerReport reads emitidas/recibidas/pagos as the source: rows linked to
// an invoice (by id or attrs.registro_id) are compared on the fields the
// register holds and, with apply, the register wins. Rows a person added that
// TLS does not know are listed; they are not imported, because the register
// does not carry base, IVA or retención and an unknown is never made zero.
func (f *Folder) registerReport(ctx context.Context, ws, root string, l Layout, apply bool) (map[string]any, []map[string]string) {
	regs := l.registersDir()
	out := map[string]any{"carpeta": regs, "vinculados": 0, "sin_vincular": []map[string]string{}, "diferencias": []map[string]any{}, "aplicados": 0}
	var errs []map[string]string
	if regs == "" {
		return out, nil
	}
	type inv struct {
		id, number, date, currency string
		total                      int64
	}
	byKey := map[string]inv{}
	rows, err := f.svc.Pool.Query(ctx, `SELECT id::text, coalesce(attrs->>'registro_id',''), coalesce(number,''), coalesce(issue_date::text,''), total_minor, currency
		FROM biz_invoice WHERE workspace_id=$1`, ws)
	if err != nil {
		return out, []map[string]string{{"path": regs, "error": err.Error()}}
	}
	for rows.Next() {
		var i inv
		var regID string
		_ = rows.Scan(&i.id, &regID, &i.number, &i.date, &i.total, &i.currency)
		byKey[i.id] = i
		if regID != "" {
			byKey[regID] = i
		}
	}
	rows.Close()
	var paymentIDs = map[string]bool{}
	prow, err := f.svc.Pool.Query(ctx, `SELECT id::text FROM biz_payment WHERE workspace_id=$1`, ws)
	if err == nil {
		for prow.Next() {
			var id string
			_ = prow.Scan(&id)
			paymentIDs[id] = true
		}
		prow.Close()
	}
	linked, applied := 0, 0
	unlinked := []map[string]string{}
	diffs := []map[string]any{}
	for _, file := range []string{"emitidas.csv", "recibidas.csv", "pagos.csv"} {
		rel := path.Join(regs, file)
		reg, err := readRegister(filepath.Join(root, filepath.FromSlash(rel)))
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			errs = append(errs, map[string]string{"path": rel, "error": err.Error()})
			continue
		}
		for _, row := range reg.rows {
			id := reg.get(row, "id")
			if id == "" {
				continue
			}
			if file == "pagos.csv" {
				if paymentIDs[id] || (isUUID(id) && l.Dirs["payment"] == "") {
					linked++ // app payments: compared field by field as records
					continue
				}
				unlinked = append(unlinked, map[string]string{"path": rel, "id": id, "fecha": reg.get(row, "fecha"), "importe": reg.get(row, "importe")})
				continue
			}
			i, ok := byKey[id]
			if !ok {
				unlinked = append(unlinked, map[string]string{"path": rel, "id": id, "fecha": reg.get(row, "fecha_documento"), "tercero": reg.get(row, "tercero"), "total": reg.get(row, "total_documento")})
				continue
			}
			linked++
			want := map[string]any{}
			var fields []map[string]any
			cmp := func(col, field, db string, folder any) {
				if reg.get(row, col) == "" || canon(db) == canon(folder) {
					return
				}
				want[field] = folder
				fields = append(fields, map[string]any{"field": field, "db": db, "folder": folder})
			}
			cmp("fecha_documento", "issue_date", i.date, reg.get(row, "fecha_documento"))
			cmp("numero_documento", "number", i.number, reg.get(row, "numero_documento"))
			cmp("moneda", "currency", i.currency, reg.get(row, "moneda"))
			if t := reg.get(row, "total_documento"); t != "" {
				if v, err := parseAmount(t); err != nil {
					errs = append(errs, map[string]string{"path": rel + "#" + id, "error": err.Error()})
				} else if v != i.total {
					want["total_minor"] = v
					fields = append(fields, map[string]any{"field": "total_minor", "db": i.total, "folder": v})
				}
			}
			if len(fields) == 0 {
				continue
			}
			diffs = append(diffs, map[string]any{"path": rel + "#" + id, "id": i.id, "type": "invoice", "fields": fields})
			if apply {
				if err := f.update(ctx, "biz_invoice", ws, i.id, want); err != nil {
					errs = append(errs, map[string]string{"path": rel + "#" + id, "error": err.Error()})
					continue
				}
				applied++
			}
		}
	}
	out["vinculados"], out["sin_vincular"], out["diferencias"], out["aplicados"] = linked, unlinked, diffs, applied
	return out, errs
}

// update patches some columns of an existing row (no insert: a partial row
// would not satisfy NOT NULL columns).
func (f *Folder) update(ctx context.Context, table, ws, id string, fields map[string]any) error {
	keys := make([]string, 0, len(fields))
	for k := range fields {
		keys = append(keys, k)
	}
	sortKeys(keys)
	cols := strings.Join(keys, ",")
	_, err := f.svc.Pool.Exec(ctx, fmt.Sprintf(`UPDATE %s SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::%s, $1::jsonb)), version=version+1, updated_at=now()
		WHERE id=$2 AND workspace_id=$3`, table, cols, cols, table), mustJSON(fields), id, ws)
	return err
}

// --- Notes without tls_type ---------------------------------------------------

// Adopt lists the notes in record folders that lack tls_type or id and, with
// apply, adds the minimal frontmatter (tls_type, tls_schema, id). The body and
// any other key are kept exactly as they are.
func (f *Folder) Adopt(ctx context.Context, ws string, apply bool) (map[string]any, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	if root == "" {
		return nil, invalid("La empresa no tiene carpeta configurada")
	}
	_, errs, proposals := f.scan(root)
	adopted := 0
	if apply {
		if err := f.claim(ctx, ws, root); err != nil {
			return nil, invalid("%v", err)
		}
		for _, p := range proposals {
			rel := str(p["path"])
			full := filepath.Join(root, filepath.FromSlash(rel))
			old, err := os.ReadFile(full)
			if err != nil {
				errs = append(errs, map[string]string{"path": rel, "error": err.Error()})
				continue
			}
			add, _ := p["add"].(map[string]any)
			if add == nil {
				continue // nothing safe to add (see "motivo")
			}
			if v, ok := add["id"]; ok && v == nil {
				add["id"] = uuid.NewString()
			}
			data, err := mergeNote(old, add)
			if err == nil {
				err = atomicWrite(full, data)
			}
			if err != nil {
				errs = append(errs, map[string]string{"path": rel, "error": err.Error()})
				continue
			}
			adopted++
		}
	}
	if errs == nil {
		errs = []map[string]string{}
	}
	return map[string]any{"proposals": proposals, "adopted": adopted, "parse_errors": errs, "mode": map[bool]string{true: "apply", false: "preview"}[apply]}, nil
}

// minimalFront proposes what a note needs to be read as a record.
func minimalFront(rel, typ string, front map[string]any) map[string]any {
	p := map[string]any{"path": rel, "type": typ}
	switch id := str(front["id"]); {
	case id == "":
		p["add"] = map[string]any{"tls_type": typ, "tls_schema": folderSchema, "id": nil} // id assigned on apply
	case isUUID(id):
		p["add"] = map[string]any{"tls_type": typ, "tls_schema": folderSchema}
	default:
		p["motivo"] = "el id no es un UUID; no se cambia un identificador existente"
	}
	return p
}

// firstHeading is the note's H1, used as name or title when the note has none.
func firstHeading(body string) string {
	for _, ln := range strings.Split(body, "\n") {
		if strings.HasPrefix(ln, "# ") {
			return strings.TrimSpace(ln[2:])
		}
	}
	return ""
}
