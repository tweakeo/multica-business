package biz

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode"

	"github.com/jackc/pgx/v5"
	"golang.org/x/text/unicode/norm"
	"gopkg.in/yaml.v3"
)

// Folder keeps the company's portable folder: the durable, human-readable
// representation of committed business records. PostgreSQL holds the
// queryable projection; the journal (biz_journal) bridges both so a write
// confirmed in the database is never lost on the way to disk.
//
// Protocol per change: (1) inside the business transaction, insert an
// "intent" journal row; (2) after commit, render the record and write it
// atomically (temp file + rename); (3) mark the row "committed" with the
// content hash. Pending intents are replayed on startup and on every flush.
type Folder struct {
	svc *Service
	mu  sync.Mutex
}

const folderSchema = 1

// humanMark prefixes the journal hash of a note whose body is a person's:
// TLS only updates its frontmatter.
const humanMark = "human:"

// Root is the company folder. A leading "~/" is the current user's home, so
// a company (and the bundled demo) moves between Macs without rewriting it.
func (f *Folder) Root(ctx context.Context, q Querier, ws string) string {
	var root string
	_ = json.Unmarshal(f.svc.Setting(ctx, q, ws, "company_folder"), &root)
	if strings.HasPrefix(root, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			root = filepath.Join(home, root[2:])
		}
	}
	return root
}

// Journal records the intent to (re)write an entity file.
func (f *Folder) Journal(ctx context.Context, tx pgx.Tx, ws, entityType, id string) {
	if id == "" {
		return
	}
	if _, err := tx.Exec(ctx, `INSERT INTO biz_journal (workspace_id, entity_type, entity_id, rel_path) VALUES ($1,$2,$3,'')`, ws, entityType, id); err != nil {
		f.svc.Log.Warn("biz journal insert failed", "error", err)
	}
}

// PendingCount is shown in the UI as "escrituras pendientes".
func (f *Folder) PendingCount(ctx context.Context, ws string) int {
	var n int
	_ = f.svc.Pool.QueryRow(ctx, `SELECT count(*) FROM biz_journal WHERE workspace_id=$1 AND state='intent'`, ws).Scan(&n)
	return n
}

func (f *Folder) FlushPending(ctx context.Context, ws string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	root, err := f.writeRoot(ctx, ws)
	if err != nil {
		// Another TLS owns the folder: intents stay pending, nothing is written.
		f.svc.Log.Warn("biz folder not written", "error", err)
		return
	}
	if root == "" {
		return
	}
	rows, err := f.svc.Pool.Query(ctx, `SELECT DISTINCT ON (entity_type, entity_id) id, entity_type, entity_id::text FROM biz_journal
		WHERE workspace_id=$1 AND state='intent' ORDER BY entity_type, entity_id, created_at DESC`, ws)
	if err != nil {
		return
	}
	type item struct{ id, typ, eid string }
	var items []item
	for rows.Next() {
		var it item
		_ = rows.Scan(&it.id, &it.typ, &it.eid)
		items = append(items, it)
	}
	rows.Close()
	for _, it := range items {
		rel, hash, err := f.writeEntity(ctx, ws, root, it.typ, it.eid)
		if err != nil {
			_, _ = f.svc.Pool.Exec(ctx, `UPDATE biz_journal SET state='failed', error=$2 WHERE id=$1`, it.id, err.Error())
			continue
		}
		_, _ = f.svc.Pool.Exec(ctx, `UPDATE biz_journal SET state='superseded' WHERE workspace_id=$1 AND entity_type=$2 AND entity_id=$3 AND state IN ('intent','committed') AND id<>$4`,
			ws, it.typ, it.eid, it.id)
		_, _ = f.svc.Pool.Exec(ctx, `UPDATE biz_journal SET state='committed', rel_path=$2, content_hash=$3, committed_at=now(), error='' WHERE id=$1`, it.id, rel, hash)
	}
}

// ExportAll journals every record so the next flush writes the full folder.
func (f *Folder) ExportAll(ctx context.Context, ws string) (int, error) {
	if _, err := f.writeRoot(ctx, ws); err != nil {
		return 0, invalid("%v", err)
	}
	n := 0
	err := f.svc.withTx(ctx, func(tx pgx.Tx) error {
		for typ, table := range entityTables {
			if typ == "approval" {
				continue
			}
			tag, err := tx.Exec(ctx, fmt.Sprintf(`INSERT INTO biz_journal (workspace_id, entity_type, entity_id, rel_path) SELECT workspace_id, $2, id, '' FROM %s WHERE workspace_id=$1`, table), ws, typ)
			if err != nil {
				return err
			}
			n += int(tag.RowsAffected())
		}
		return nil
	})
	if err == nil {
		f.ensureSkeleton(ctx, ws)
		f.FlushPending(ctx, ws)
		err = f.writeCompanyIndex(ctx, ws)
	}
	return n, err
}

// ensureSkeleton creates the layout's empty folders (Sistemas/, Recursos/,
// Buzón/, Archivo/…). Creating a folder never touches anything inside it.
func (f *Folder) ensureSkeleton(ctx context.Context, ws string) {
	root, err := f.writeRoot(ctx, ws)
	if err != nil || root == "" {
		return
	}
	l, err := LoadLayout(root)
	if err != nil {
		return
	}
	for _, d := range l.Skeleton {
		_ = os.MkdirAll(filepath.Join(root, filepath.FromSlash(l.expand(d))), 0o755)
	}
}

var nonSlug = regexp.MustCompile(`[^a-z0-9]+`)

func slugify(s string) string {
	t := norm.NFD.String(strings.ToLower(s))
	var b strings.Builder
	for _, r := range t {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		b.WriteRune(r)
	}
	out := strings.Trim(nonSlug.ReplaceAllString(b.String(), "-"), "-")
	if len(out) > 60 {
		out = strings.Trim(out[:60], "-")
	}
	if out == "" {
		out = "sin-titulo"
	}
	return out
}

func short(id string) string {
	if len(id) >= 8 {
		return id[:8]
	}
	return id
}

// relPath decides where a record lives, following the folder's layout. The
// file name carries a short ID so renaming a title never changes identity:
// identity is the `id` field. "" means the record has no file of its own
// (it lives in a register or in the decisions file).
func relPath(l Layout, typ string, m map[string]any, lookup func(string, string) string) string {
	id := str(m["id"])
	name := func(field string) string { return slugify(str(m[field])) + "--" + short(id) + ".md" }
	quarter := func(date string) (string, string) {
		t, err := time.Parse("2006-01-02", date)
		if err != nil {
			return l.expand("{finanzas}/Sin fecha"), "Sin fecha"
		}
		y, q := quarterOf(t)
		return l.quarterDir(y, q), fmt.Sprintf("%d-T%d", y, q)
	}
	in := func(dirType, file string) string {
		if d := l.dir(dirType); d != "" {
			return d + "/" + file
		}
		return ""
	}
	var rel string
	switch typ {
	case "organization", "contact", "role":
		rel = in(typ, name("name"))
	case "opportunity", "objective", "content":
		rel = in(typ, name("title"))
		if typ == "objective" && rel != "" {
			rel = in(typ, slugify(str(m["period"]))+"/"+name("title"))
		}
	case "service":
		rel = in(typ, slugify(str(m["code"]))+".md")
	case "offer":
		rel = in(typ, fmt.Sprintf("%s-v%v.md", slugify(lookup("service", str(m["service_id"]))), m["version"]))
	case "invoice":
		qd, _ := quarter(str(m["issue_date"]))
		switch {
		case str(m["direction"]) == "issued" && m["number"] == nil:
			rel = in("invoice_draft", "borrador--"+short(id)+".md")
		case str(m["direction"]) == "issued":
			rel = qd + "/Ingresos/" + slugify(str(m["number"])) + ".md"
		default:
			rel = qd + "/Gastos/" + slugify(lookup("organization", str(m["organization_id"]))) + "/" + slugify(str(m["number"])) + "--" + short(id) + ".md"
		}
	case "payment":
		if d := l.Dirs["payment"]; d != "" {
			qd, _ := quarter(str(m["paid_on"]))
			rel = l.expand(strings.ReplaceAll(d, "{quarter}", qd)) + "/" + str(m["paid_on"]) + "--" + short(id) + ".md"
		}
	case "account":
		rel = in(typ, slugify(str(m["name"]))+"/cuenta.md")
	case "movement":
		_, label := quarter(str(m["booked_on"]))
		rel = in("account", slugify(lookup("account", str(m["account_id"])))+"/"+label+"/"+str(m["booked_on"])+"--"+short(id)+".md")
	case "period":
		y, _ := strconv.Atoi(fmt.Sprint(m["year"]))
		q, _ := strconv.Atoi(fmt.Sprint(m["quarter"]))
		rel = l.quarterDir(y, q) + "/periodo.md"
	case "kpi":
		rel = in(typ, slugify(str(m["code"]))+".md")
	case "decision":
		if l.Decisiones != "" {
			return ""
		}
		created := str(m["created_at"])
		if len(created) >= 10 {
			created = created[:10]
		}
		rel = in(typ, created+"--"+name("title"))
	case "routine":
		rel = in(typ, str(m["kind"])+"/"+slugify(str(m["period_key"]))+".md")
	case "conversation":
		rel = in(typ, name("channel"))
	case "document":
		rel = in(typ, name("title"))
	default:
		rel = "Otros/" + typ + "--" + id + ".md"
	}
	// A retired record keeps its place, under Archivo/.
	if rel != "" && m["archived_at"] != nil {
		rel = l.Archivo + "/" + rel
	}
	return rel
}

var bodyField = map[string]string{"opportunity": "notes", "organization": "notes", "contact": "notes", "content": "body", "role": "manual", "decision": "context", "period": "notes", "invoice": "notes", "movement": "notes"}

func (f *Folder) lookupName(ctx context.Context) func(string, string) string {
	return func(typ, id string) string {
		if id == "" {
			return "sin-" + typ
		}
		col := "name"
		if typ == "service" {
			col = "code"
		}
		var v string
		_ = f.svc.Pool.QueryRow(ctx, fmt.Sprintf(`SELECT %s FROM %s WHERE id=$1`, col, entityTables[typ]), id).Scan(&v)
		if v == "" {
			return "sin-" + typ
		}
		return v
	}
}

// frontOf splits a record into its frontmatter and its body text.
func frontOf(typ string, m map[string]any) (map[string]any, string) {
	body := ""
	if bf, ok := bodyField[typ]; ok {
		body = str(m[bf])
	}
	front := map[string]any{"tls_type": typ, "tls_schema": folderSchema}
	attrs, _ := m["attrs"].(map[string]any)
	for k, v := range m {
		if k == "workspace_id" || k == "attrs" || k == bodyField[typ] {
			continue
		}
		front[k] = v
	}
	for k, v := range attrs { // unknown fields round-trip at top level
		if _, clash := front[k]; !clash {
			front[k] = v
		}
	}
	return front, body
}

func render(typ string, m map[string]any) ([]byte, error) {
	front, body := frontOf(typ, m)
	var buf bytes.Buffer
	buf.WriteString("---\n")
	enc := yaml.NewEncoder(&buf)
	enc.SetIndent(2)
	if err := enc.Encode(front); err != nil {
		return nil, err
	}
	_ = enc.Close()
	buf.WriteString("---\n\n")
	buf.WriteString(strings.TrimSpace(body))
	buf.WriteString("\n")
	return buf.Bytes(), nil
}

func atomicWrite(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tls-*.tmp")
	if err != nil {
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	tmp.Close()
	return os.Rename(tmp.Name(), path)
}

func hashBytes(b []byte) string {
	s := sha256.Sum256(b)
	return hex.EncodeToString(s[:])
}

func (f *Folder) writeEntity(ctx context.Context, ws, root, typ, id string) (string, string, error) {
	l, err := LoadLayout(root)
	if err != nil {
		return "", "", err
	}
	m, err := rowMap(ctx, f.svc.Pool, typ, id)
	if err != nil {
		return "", "", err
	}
	var regRel, regHash string
	if l.Registros != "" {
		if regRel, regHash, err = f.writeRegisterRow(ctx, root, l, typ, m); err != nil {
			return "", "", err
		}
	}
	if typ == "decision" && l.Decisiones != "" {
		return writeDecisionLine(root, l, m)
	}
	if typ == "kpi" && l.Metas != "" {
		return writeMetaRow(root, l, m)
	}
	rel := relPath(l, typ, m, f.lookupName(ctx))
	if rel == "" {
		return regRel, regHash, nil
	}
	var prev, prevHash string
	_ = f.svc.Pool.QueryRow(ctx, `SELECT rel_path, content_hash FROM biz_journal WHERE workspace_id=$1 AND entity_type=$2 AND entity_id=$3 AND state='committed' AND rel_path<>''
		ORDER BY committed_at DESC LIMIT 1`, ws, typ, id).Scan(&prev, &prevHash)
	abs := func(r string) string { return filepath.Join(root, filepath.FromSlash(r)) }
	// Inside the same folder a file keeps the name a person may have linked
	// to; it only moves when its folder changes (quarter, Archivo…).
	if prev != "" && path.Dir(prev) == path.Dir(rel) && exists(abs(prev)) {
		rel = prev
	}
	// A note that holds another record (or a person's note) never gets
	// overwritten: it moves to Archivo/ first.
	if rel != prev && exists(abs(rel)) {
		if old, err := os.ReadFile(abs(rel)); err == nil {
			if rec, perr := parseRecord(rel, old); perr != nil || rec.ID != id {
				if _, err := retire(root, l, rel); err != nil {
					return "", "", err
				}
			}
		}
	}
	src := rel
	if prev != "" && prev != rel && exists(abs(prev)) {
		src = prev
	}
	data, err := render(typ, m)
	if err != nil {
		return "", "", err
	}
	human := false
	if old, err := os.ReadFile(abs(src)); err == nil && (hashBytes(old) != prevHash || strings.HasPrefix(prevHash, humanMark)) {
		// A person wrote or edited this note: keep its body and update only
		// the frontmatter, without adding empty fields. The note stays the
		// person's from then on (journal hash marked human:).
		front, _ := frontOf(typ, m)
		for k, v := range front {
			if v == nil || v == "" {
				delete(front, k)
			}
		}
		if data, err = mergeNote(old, front); err != nil {
			return "", "", fmt.Errorf("%s: %v", src, err)
		}
		human = true
	}
	if src != rel && exists(abs(src)) {
		// Move, never delete: the record changes folder with its file.
		if err := os.MkdirAll(filepath.Dir(abs(rel)), 0o755); err != nil {
			return "", "", err
		}
		if err := os.Rename(abs(src), abs(rel)); err != nil {
			return "", "", err
		}
	}
	if err := atomicWrite(abs(rel), data); err != nil {
		return "", "", err
	}
	if human {
		return rel, humanMark + hashBytes(data), nil
	}
	return rel, hashBytes(data), nil
}

// writeCompanyIndex keeps Empresa.md. When it exists, only its frontmatter is
// updated: the text below is the company's own and is never rewritten.
func (f *Folder) writeCompanyIndex(ctx context.Context, ws string) error {
	root, err := f.writeRoot(ctx, ws)
	if err != nil || root == "" {
		return err
	}
	var name string
	_ = f.svc.Pool.QueryRow(ctx, `SELECT name FROM workspace WHERE id=$1`, ws).Scan(&name)
	var profile map[string]any
	_ = json.Unmarshal(f.svc.Setting(ctx, f.svc.Pool, ws, "company_profile"), &profile)
	front := map[string]any{"tls_type": "company", "tls_schema": folderSchema, "workspace_id": ws, "name": name, "profile": profile,
		"areas": Areas, "exported_at": time.Now().UTC().Format(time.RFC3339)}
	target := filepath.Join(root, "Empresa.md")
	if old, err := os.ReadFile(target); err == nil {
		data, err := mergeNote(old, front)
		if err != nil {
			return fmt.Errorf("Empresa.md: %v", err)
		}
		return atomicWrite(target, data)
	}
	var buf bytes.Buffer
	buf.WriteString("---\n")
	_ = yaml.NewEncoder(&buf).Encode(front)
	buf.WriteString("---\n\n# " + name + "\n\nCarpeta portable de la empresa. Cada fichera Markdown es un registro; su identidad es el campo `id`, no el nombre del fichero.\n" +
		"Los índices, cachés y servicios viven fuera de esta carpeta (Application Support). Aquí no se guardan secretos.\n")
	return atomicWrite(target, buf.Bytes())
}

// --- Rebuild and external changes ----------------------------------------

type folderRecord struct {
	Path     string
	Type     string
	ID       string
	Front    map[string]any
	Body     string
	Hash     string
	Inferred bool // type taken from the folder or from `tipo:`
}

func parseRecord(path string, data []byte) (*folderRecord, error) {
	fm, body, ok := splitNote(data)
	if !ok {
		if strings.HasPrefix(string(data), "---\n") {
			return nil, fmt.Errorf("frontmatter sin cerrar")
		}
		return nil, errNoFrontmatter
	}
	front := map[string]any{}
	if err := yaml.Unmarshal([]byte(fm), &front); err != nil {
		return nil, fmt.Errorf("YAML no válido: %v", err)
	}
	if front == nil {
		front = map[string]any{}
	}
	typ, _ := front["tls_type"].(string)
	id := str(front["id"])
	return &folderRecord{Path: path, Type: typ, ID: id, Front: front, Body: strings.TrimSpace(body), Hash: hashBytes(data)}, nil
}

// scan reads every record in the folder: explicit notes (tls_type), notes a
// person made in a record folder (type inferred from the folder or `tipo:`),
// the decisions file and app payments in pagos.csv. Notes in a record folder
// that cannot be read yet come back as proposals (see Adopt). Notes outside
// record folders (Área.md, Sistemas/…) are not records and are not errors.
func (f *Folder) scan(root string) ([]*folderRecord, []map[string]string, []map[string]any) {
	var recs []*folderRecord
	errs := []map[string]string{}
	proposals := []map[string]any{}
	l, err := LoadLayout(root)
	if err != nil {
		return nil, []map[string]string{{"path": layoutFile, "error": err.Error()}}, proposals
	}
	decisions := l.decisionsFile()
	payments := ""
	if l.Registros != "" && l.Dirs["payment"] == "" {
		payments = path.Join(l.registersDir(), "pagos.csv")
	}
	_ = filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			if p != root && l.skipDir(d.Name()) {
				return filepath.SkipDir
			}
			return nil
		}
		rel, _ := filepath.Rel(root, p)
		rel = filepath.ToSlash(rel)
		if rel == payments {
			if reg, err := readRegister(p); err != nil {
				errs = append(errs, map[string]string{"path": rel, "error": err.Error()})
			} else {
				recs = append(recs, scanPayments(rel, reg)...)
			}
			return nil
		}
		if !strings.HasSuffix(p, ".md") {
			return nil
		}
		archived := l.archived(rel)
		if archived && !hasTLSType(p) {
			return nil // Archivo holds history; only records TLS retired are read
		}
		data, err := os.ReadFile(p)
		if err != nil {
			errs = append(errs, map[string]string{"path": rel, "error": err.Error()})
			return nil
		}
		if rel == decisions {
			recs = append(recs, scanDecisions(rel, data)...)
			proposals = append(proposals, humanDecisionProposals(rel, data)...)
			return nil
		}
		rec, err := parseRecord(rel, data)
		if err == errNoFrontmatter {
			if typ := l.inferType(rel); typ != "" && !archived {
				proposals = append(proposals, minimalFront(rel, typ, nil))
			}
			return nil
		}
		if err != nil {
			errs = append(errs, map[string]string{"path": rel, "error": err.Error()})
			return nil
		}
		if rec.Type == "" && !archived {
			if !l.recordNote(rel) {
				return nil
			}
			typ := legacyTypes[strings.ToLower(str(rec.Front["tipo"]))]
			if typ == "" {
				typ = l.inferType(rel)
			}
			if typ == "" {
				return nil
			}
			if !isUUID(rec.ID) {
				proposals = append(proposals, minimalFront(rel, typ, rec.Front))
				return nil
			}
			rec.Type, rec.Inferred = typ, true
			proposals = append(proposals, minimalFront(rel, typ, rec.Front))
		}
		for alias, col := range fieldAliases {
			if v, ok := rec.Front[alias]; ok {
				if _, has := rec.Front[col]; !has {
					rec.Front[col] = v
				}
				delete(rec.Front, alias)
			}
		}
		// A note a person wrote (inferred, or adopted with only tls_type,
		// tls_schema and id) names itself by its H1; a service also needs a
		// code, taken from the file name. Nothing is written back.
		if field := map[string]string{"organization": "name", "contact": "name", "opportunity": "title", "service": "name"}[rec.Type]; field != "" && str(rec.Front[field]) == "" {
			rec.Front[field] = firstHeading(rec.Body)
			if str(rec.Front[field]) == "" {
				rec.Front[field] = strings.TrimSuffix(path.Base(rel), ".md")
			}
		}
		if rec.Type == "service" && str(rec.Front["code"]) == "" {
			rec.Front["code"] = slugify(strings.TrimSuffix(path.Base(rel), ".md"))
		}
		if _, ok := entityTables[rec.Type]; ok && rec.ID != "" {
			recs = append(recs, rec)
		}
		return nil
	})
	return recs, errs, proposals
}

// hasTLSType peeks at the start of a note without reading it whole: Archivo
// can hold thousands of old notes.
func hasTLSType(p string) bool {
	fh, err := os.Open(p)
	if err != nil {
		return false
	}
	defer fh.Close()
	buf := make([]byte, 2048)
	n, _ := fh.Read(buf)
	return strings.HasPrefix(string(buf[:n]), "---\n") && strings.Contains(string(buf[:n]), "\ntls_type:")
}

// Status compares the folder with what TLS last wrote: externally edited
// files, files TLS does not know, missing files and duplicate IDs.
func (f *Folder) Status(ctx context.Context, ws string) (map[string]any, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	out := map[string]any{"root": root, "pending_writes": f.PendingCount(ctx, ws)}
	if root == "" {
		out["configured"] = false
		return out, nil
	}
	out["configured"] = true
	l, err := LoadLayout(root)
	if err != nil {
		return nil, invalid("%v", err)
	}
	out["layout"] = l.Preset
	out["escritor"] = f.writerStatus(ctx, ws, root)
	recs, errs, proposals := f.scan(root)
	known := map[string]string{}
	rows, err := f.svc.Pool.Query(ctx, `SELECT DISTINCT ON (entity_id) entity_id::text, rel_path, content_hash FROM biz_journal
		WHERE workspace_id=$1 AND state='committed' ORDER BY entity_id, committed_at DESC`, ws)
	if err != nil {
		return nil, err
	}
	paths := map[string]string{}
	for rows.Next() {
		var id, rel, hash string
		_ = rows.Scan(&id, &rel, &hash)
		known[id] = strings.TrimPrefix(hash, humanMark)
		paths[id] = rel
	}
	rows.Close()
	byID := map[string][]string{}
	modified, unknown := []map[string]string{}, []map[string]string{}
	for _, r := range recs {
		byID[r.ID] = append(byID[r.ID], r.Path)
		h, ok := known[r.ID]
		switch {
		case !ok:
			unknown = append(unknown, map[string]string{"path": r.Path, "id": r.ID, "type": r.Type})
		case h != r.Hash && paths[r.ID] == r.Path:
			modified = append(modified, map[string]string{"path": r.Path, "id": r.ID, "type": r.Type})
		}
	}
	dups := []map[string]any{}
	for id, ps := range byID {
		if len(ps) > 1 {
			sort.Strings(ps)
			dups = append(dups, map[string]any{"id": id, "paths": ps})
		}
	}
	inferred := 0
	for _, r := range recs {
		if r.Inferred {
			inferred++
		}
	}
	regs, regErrs := f.registerReport(ctx, ws, root, l, false)
	out["files"] = len(recs)
	out["inferred"] = inferred
	out["proposals"] = proposals
	out["registros"] = regs
	errs = append(errs, regErrs...)
	out["modified_externally"] = modified
	out["unknown_files"] = unknown
	out["duplicate_ids"] = dups
	out["parse_errors"] = errs
	return out, nil
}

var tableColumns = map[string]map[string]bool{}

func (f *Folder) columns(ctx context.Context, table string) map[string]bool {
	if c, ok := tableColumns[table]; ok {
		return c
	}
	cols := map[string]bool{}
	rows, err := f.svc.Pool.Query(ctx, `SELECT column_name FROM information_schema.columns WHERE table_name=$1`, table)
	if err == nil {
		for rows.Next() {
			var c string
			_ = rows.Scan(&c)
			cols[c] = true
		}
		rows.Close()
	}
	tableColumns[table] = cols
	return cols
}

func normalizeValue(v any) any {
	switch t := v.(type) {
	case time.Time:
		if t.Hour() == 0 && t.Minute() == 0 && t.Second() == 0 && t.Nanosecond() == 0 {
			return t.Format("2006-01-02")
		}
		return t.UTC().Format(time.RFC3339Nano)
	case int:
		return float64(t)
	case int64:
		return float64(t)
	case uint64:
		return float64(t)
	case []any:
		out := make([]any, len(t))
		for i := range t {
			out[i] = normalizeValue(t[i])
		}
		return out
	case map[string]any:
		out := map[string]any{}
		for k, x := range t {
			out[k] = normalizeValue(x)
		}
		return out
	}
	return v
}

func canon(v any) string {
	b, _ := json.Marshal(normalizeValue(v))
	s := string(b)
	// Timestamps: compare instants regardless of formatting.
	if len(s) > 20 && s[0] == '"' {
		if t, err := time.Parse(time.RFC3339Nano, strings.Trim(s, `"`)); err == nil {
			return t.UTC().Format(time.RFC3339Nano)
		}
	}
	return s
}

// Rebuild compares the folder against the projection field by field and,
// with apply=true, upserts the folder content. Unknown fields go to attrs
// where the table has one; human text in the body is preserved.
func (f *Folder) Rebuild(ctx context.Context, ws string, apply bool) (map[string]any, error) {
	root := f.Root(ctx, f.svc.Pool, ws)
	if root == "" {
		return nil, invalid("La empresa no tiene carpeta configurada")
	}
	if apply {
		if err := f.claim(ctx, ws, root); err != nil {
			return nil, invalid("%v", err)
		}
	}
	l, err := LoadLayout(root)
	if err != nil {
		return nil, invalid("%v", err)
	}
	recs, errs, proposals := f.scan(root)
	seen := map[string]string{}
	var present []*folderRecord // records whose row exists after this run
	var conflicts []map[string]any
	var missing, different []map[string]any
	equal, applied := 0, 0
	for _, r := range recs {
		if prev, dup := seen[r.ID]; dup {
			conflicts = append(conflicts, map[string]any{"id": r.ID, "paths": []string{prev, r.Path}})
			continue
		}
		seen[r.ID] = r.Path
		table := entityTables[r.Type]
		cols := f.columns(ctx, table)
		want := map[string]any{}
		extra := map[string]any{}
		for k, v := range r.Front {
			if k == "tls_type" || k == "tls_schema" || k == "workspace_id" {
				continue
			}
			if cols[k] {
				want[k] = normalizeValue(v)
			} else {
				extra[k] = normalizeValue(v)
			}
		}
		if bf, ok := bodyField[r.Type]; ok && cols[bf] {
			want[bf] = r.Body
		}
		if cols["attrs"] && len(extra) > 0 {
			want["attrs"] = extra
		}
		want["workspace_id"] = ws
		if r.Type == "payment" && !isUUID(str(want["invoice_id"])) {
			// pagos.csv links by the register id of the invoice.
			var inv string
			_ = f.svc.Pool.QueryRow(ctx, `SELECT id::text FROM biz_invoice WHERE workspace_id=$1 AND attrs->>'registro_id'=$2`, ws, str(want["invoice_id"])).Scan(&inv)
			if inv == "" {
				errs = append(errs, map[string]string{"path": r.Path, "error": "factura del pago no encontrada: " + str(want["invoice_id"])})
				continue
			}
			want["invoice_id"] = inv
		}
		current, err := rowMap(ctx, f.svc.Pool, r.Type, r.ID)
		if err != nil {
			missing = append(missing, map[string]any{"path": r.Path, "id": r.ID, "type": r.Type})
		} else {
			var diffs []map[string]any
			for k, v := range want {
				if k == "workspace_id" {
					continue
				}
				if canon(current[k]) != canon(v) {
					diffs = append(diffs, map[string]any{"field": k, "db": current[k], "folder": v})
				}
			}
			if len(diffs) == 0 {
				equal++
				present = append(present, r)
				continue
			}
			different = append(different, map[string]any{"path": r.Path, "id": r.ID, "type": r.Type, "fields": diffs})
		}
		if apply {
			if err := f.upsert(ctx, table, want); err != nil {
				errs = append(errs, map[string]string{"path": r.Path, "error": err.Error()})
				continue
			}
			applied++
			present = append(present, r)
		}
	}
	regs, regErrs := f.registerReport(ctx, ws, root, l, apply)
	errs = append(errs, regErrs...)
	different = append(different, regs["diferencias"].([]map[string]any)...)
	applied += regs["aplicados"].(int)
	if apply {
		// Remember where each record lives so later writes update that file
		// (a person's note keeps its name and body) instead of creating another.
		for _, r := range present {
			_, _ = f.svc.Pool.Exec(ctx, `INSERT INTO biz_journal (workspace_id, entity_type, entity_id, rel_path, content_hash, state, committed_at)
				SELECT $1,$2,$3,$4,$6,'committed',now() WHERE NOT EXISTS (SELECT 1 FROM biz_journal WHERE workspace_id=$1 AND entity_type=$2 AND entity_id=$3
				AND state='committed' AND rel_path=$4 AND content_hash IN ($5, $6))`, ws, r.Type, r.ID, r.Path, r.Hash, humanMark+r.Hash)
		}
	}
	if apply && applied > 0 {
		_, _ = f.svc.Pool.Exec(ctx, `INSERT INTO biz_audit (workspace_id, actor_type, action, result, details) VALUES ($1,'system','folder.rebuild','ok',$2)`,
			ws, fmt.Sprintf(`{"applied": %d}`, applied))
	}
	if conflicts == nil {
		conflicts = []map[string]any{}
	}
	if missing == nil {
		missing = []map[string]any{}
	}
	if different == nil {
		different = []map[string]any{}
	}
	return map[string]any{"files": len(recs), "equal": equal, "missing_in_db": missing, "different": different, "duplicate_ids": conflicts,
		"parse_errors": errs, "applied": applied, "proposals": proposals, "registros": regs, "layout": l.Preset,
		"mode": map[bool]string{true: "apply", false: "preview"}[apply]}, nil
}

func (f *Folder) upsert(ctx context.Context, table string, row map[string]any) error {
	keys := make([]string, 0, len(row))
	for k := range row {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	sets := []string{}
	for _, k := range keys {
		if k != "id" {
			sets = append(sets, fmt.Sprintf("%s=EXCLUDED.%s", k, k))
		}
	}
	cols := strings.Join(keys, ",")
	// jsonb_populate_record casts every value to its column type.
	_, err := f.svc.Pool.Exec(ctx, fmt.Sprintf(`INSERT INTO %s (%s) SELECT %s FROM jsonb_populate_record(NULL::%s, $1::jsonb) ON CONFLICT (id) DO UPDATE SET %s`,
		table, cols, cols, table, strings.Join(sets, ",")), mustJSON(row))
	return err
}

func mustJSON(v any) string {
	b, _ := json.Marshal(v)
	return string(b)
}

// --- Documents and the quarterly package ---------------------------------

// attachDocument registers an original (PDF, image…) by relative path and
// fingerprint. The file itself stays in the company folder.
func (s *Service) attachDocument(ctx context.Context, tx pgx.Tx, ws, entityType, entityID, kind, title, rel string) error {
	root := s.Folder.Root(ctx, tx, ws)
	hash, size := "", int64(0)
	if root != "" {
		if data, err := os.ReadFile(filepath.Join(root, rel)); err == nil {
			hash, size = hashBytes(data), int64(len(data))
		}
	}
	var id string
	if err := tx.QueryRow(ctx, `INSERT INTO biz_document (workspace_id, entity_type, entity_id, kind, title, rel_path, sha256, size_bytes)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id`, ws, entityType, entityID, kind, title, rel, hash, size).Scan(&id); err != nil {
		return err
	}
	if entityType == "invoice" {
		_, _ = tx.Exec(ctx, `UPDATE biz_invoice SET document_id=$2 WHERE id=$1`, entityID, id)
	}
	return nil
}

func (f *Folder) WritePeriodPackage(ctx context.Context, ws string, year, quarter int) error {
	root, err := f.writeRoot(ctx, ws)
	if err != nil || root == "" {
		return err
	}
	l, err := LoadLayout(root)
	if err != nil {
		return err
	}
	start, end := quarterRange(year, quarter)
	dir := filepath.Join(root, filepath.FromSlash(l.packageDir(year, quarter)))
	derived := ""
	if l.Registros != "" {
		derived = "\n> Los registros únicos están en `" + l.registersDir() + "/`. Estos CSV son una copia calculada para la gestoría: no se editan.\n"
	}
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	writeCSV := func(name string, header []string, sql string, args ...any) (int, error) {
		rows, err := f.svc.Pool.Query(ctx, sql, args...)
		if err != nil {
			return 0, err
		}
		defer rows.Close()
		var buf bytes.Buffer
		w := csv.NewWriter(&buf)
		w.Comma = ';'
		_ = w.Write(header)
		n := 0
		for rows.Next() {
			vals, err := rows.Values()
			if err != nil {
				return 0, err
			}
			rec := make([]string, len(vals))
			for i, v := range vals {
				switch t := v.(type) {
				case nil:
					rec[i] = ""
				case time.Time:
					rec[i] = t.Format("2006-01-02")
				default:
					rec[i] = fmt.Sprint(t)
				}
			}
			_ = w.Write(rec)
			n++
		}
		w.Flush()
		return n, atomicWrite(filepath.Join(dir, name), buf.Bytes())
	}
	money := func(col string) string {
		return fmt.Sprintf(`replace(to_char(%s/100.0, 'FM9999999990.00'), '.', ',')`, col)
	}
	nIssued, err := writeCSV("libro-ingresos.csv", []string{"numero", "fecha", "cliente", "nif", "base", "iva", "retencion", "total", "estado", "id"},
		`SELECT i.number, i.issue_date, o.name, o.tax_id, `+money("i.base_minor")+`, `+money("i.tax_minor")+`, `+money("i.withholding_minor")+`, `+money("i.total_minor")+`, i.status, i.id
		FROM biz_invoice i LEFT JOIN biz_organization o ON o.id=i.organization_id WHERE i.workspace_id=$1 AND i.direction='issued' AND i.status NOT IN ('draft','void')
		AND i.issue_date >= $2 AND i.issue_date < $3 ORDER BY i.issue_date, i.number`, ws, start, end)
	if err != nil {
		return err
	}
	nReceived, err := writeCSV("libro-gastos.csv", []string{"numero", "fecha", "proveedor", "nif", "categoria", "naturaleza", "base", "iva", "retencion", "total", "justificante", "id"},
		`SELECT i.number, i.issue_date, o.name, o.tax_id, i.category, i.nature, `+money("i.base_minor")+`, `+money("i.tax_minor")+`, `+money("i.withholding_minor")+`, `+money("i.total_minor")+`,
		coalesce(d.rel_path, 'FALTA'), i.id FROM biz_invoice i LEFT JOIN biz_organization o ON o.id=i.organization_id LEFT JOIN biz_document d ON d.id=i.document_id
		WHERE i.workspace_id=$1 AND i.direction='received' AND i.status<>'void' AND i.issue_date >= $2 AND i.issue_date < $3 ORDER BY i.issue_date`, ws, start, end)
	if err != nil {
		return err
	}
	nMov, err := writeCSV("movimientos.csv", []string{"fecha", "concepto", "importe", "naturaleza", "categoria", "conciliacion", "factura", "id"},
		`SELECT m.booked_on, m.description, `+money("m.amount_minor")+`, m.nature, m.category, m.status, coalesce(i.number,''), m.id FROM biz_bank_movement m
		LEFT JOIN biz_invoice i ON i.id=m.invoice_id WHERE m.workspace_id=$1 AND m.booked_on >= $2 AND m.booked_on < $3 ORDER BY m.booked_on`, ws, start, end)
	if err != nil {
		return err
	}
	nDiff, err := writeCSV("diferencias.csv", []string{"tipo", "fecha", "descripcion", "importe", "id"},
		`SELECT 'movimiento sin conciliar', booked_on, description, `+money("amount_minor")+`, id FROM biz_bank_movement WHERE workspace_id=$1 AND booked_on >= $2 AND booked_on < $3
			AND status IN ('unreconciled','proposed') AND nature IN ('operating_income','operating_expense')
		UNION ALL SELECT 'gasto sin justificante', i.issue_date, coalesce(i.number,''), `+money("i.total_minor")+`, i.id FROM biz_invoice i WHERE i.workspace_id=$1 AND i.direction='received'
			AND i.issue_date >= $2 AND i.issue_date < $3 AND i.document_id IS NULL
		ORDER BY 2`, ws, start, end)
	if err != nil {
		return err
	}
	var summary json.RawMessage
	var status string
	_ = f.svc.Pool.QueryRow(ctx, `SELECT summary, status FROM biz_period WHERE workspace_id=$1 AND year=$2 AND quarter=$3`, ws, year, quarter).Scan(&summary, &status)
	var sm struct {
		Issued   map[string]int64 `json:"issued"`
		Received map[string]int64 `json:"received"`
	}
	_ = json.Unmarshal(summary, &sm)
	idx := fmt.Sprintf(`# Paquete para la gestoría · %d T%d

Estado del periodo: **%s**. Generado: %s.

> Documentación preparada para revisión del asesor. No es una declaración oficial ni calcula importes a ingresar. Lo que falta está en `+"`diferencias.csv`"+`.

| Fichero | Contenido | Registros |
|---|---|---|
| libro-ingresos.csv | Facturas emitidas del trimestre | %d |
| libro-gastos.csv | Facturas recibidas, con ruta del justificante o FALTA | %d |
| movimientos.csv | Movimientos bancarios con su conciliación | %d |
| diferencias.csv | Excepciones a resolver o validar | %d |

## Totales

| | Base | IVA | Retención | Total |
|---|---|---|---|---|
| Ingresos | %s | %s | %s | %s |
| Gastos | %s | %s | %s | %s |

Cada fila lleva el `+"`id`"+` del registro: se puede rastrear hasta la operación en TLS y en la carpeta de la empresa.
%s`, year, quarter, periodLabel(status), time.Now().In(madridNow().Location()).Format("02/01/2006 15:04"), nIssued, nReceived, nMov, nDiff,
		eur(sm.Issued["base_minor"]), eur(sm.Issued["tax_minor"]), eur(sm.Issued["withholding_minor"]), eur(sm.Issued["total_minor"]),
		eur(sm.Received["base_minor"]), eur(sm.Received["tax_minor"]), eur(sm.Received["withholding_minor"]), eur(sm.Received["total_minor"]), derived)
	return atomicWrite(filepath.Join(dir, "indice.md"), []byte(idx))
}
