package biz

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// --- Pure helpers ------------------------------------------------------------

func TestLayoutDefaultsKeepTheDemoPaths(t *testing.T) {
	l, err := LoadLayout(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	lookup := func(string, string) string { return "x" }
	id := "3f7c0000-0000-0000-0000-000000000000"
	cases := map[string]struct {
		typ string
		m   map[string]any
	}{
		"Ventas/Organizaciones/ferrer-sl--3f7c0000.md":            {"organization", map[string]any{"id": id, "name": "Ferrer SL"}},
		"Finanzas/2026/T4/Ingresos/2026-001.md":                   {"invoice", map[string]any{"id": id, "direction": "issued", "number": "2026-001", "issue_date": "2026-10-01"}},
		"Finanzas/2026/T4/Cobros y pagos/2026-10-02--3f7c0000.md": {"payment", map[string]any{"id": id, "paid_on": "2026-10-02"}},
		"Dirección/Decisiones/2026-10-01--precio--3f7c0000.md":    {"decision", map[string]any{"id": id, "title": "Precio", "created_at": "2026-10-01T10:00:00Z"}},
		"Finanzas/2026/T3/periodo.md":                             {"period", map[string]any{"id": id, "year": float64(2026), "quarter": float64(3)}},
	}
	for want, c := range cases {
		if got := relPath(l, c.typ, c.m, lookup); got != want {
			t.Errorf("%s: got %q want %q", c.typ, got, want)
		}
	}
	if l.packageDir(2026, 3) != "Finanzas/2026/T3/Paquete gestoría" {
		t.Errorf("package dir: %s", l.packageDir(2026, 3))
	}
}

func TestHumanLayoutPaths(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, layoutFile, `{"preset": "humana", "areas": {"marca": "5 · Marca"}}`)
	l, err := LoadLayout(dir)
	if err != nil {
		t.Fatal(err)
	}
	lookup := func(string, string) string { return "Proveedor" }
	id := "3f7c0000-0000-0000-0000-000000000000"
	cases := map[string]struct {
		typ string
		m   map[string]any
	}{
		"2 · Ventas/Empresas/ferrer-sl--3f7c0000.md":                    {"organization", map[string]any{"id": id, "name": "Ferrer SL"}},
		"4 · Finanzas/Fiscal/2026/T4/Ingresos/2026-001.md":              {"invoice", map[string]any{"id": id, "direction": "issued", "number": "2026-001", "issue_date": "2026-10-01"}},
		"4 · Finanzas/Fiscal/2026/T2/Gastos/proveedor/f-9--3f7c0000.md": {"invoice", map[string]any{"id": id, "direction": "received", "number": "F-9", "issue_date": "2026-05-01"}},
		"": {"payment", map[string]any{"id": id, "paid_on": "2026-10-02"}},
		"Archivo/2 · Ventas/Contactos/ana--3f7c0000.md": {"contact", map[string]any{"id": id, "name": "Ana", "archived_at": "2026-10-20T00:00:00Z"}},
		"5 · Marca/Contenidos/post--3f7c0000.md":        {"content", map[string]any{"id": id, "title": "Post"}},
	}
	for want, c := range cases {
		if got := relPath(l, c.typ, c.m, lookup); got != want {
			t.Errorf("%s: got %q want %q", c.typ, got, want)
		}
	}
	if relPath(l, "decision", map[string]any{"id": id, "title": "x"}, lookup) != "" || l.decisionsFile() != "1 · Dirección/Decisiones.md" {
		t.Error("decisions must go to the single Decisiones.md")
	}
	if l.packageDir(2026, 3) != "4 · Finanzas/Fiscal/2026/T3/Modelos/Paquete gestoría" || l.registersDir() != "4 · Finanzas/Registros" {
		t.Errorf("finance paths: %s %s", l.packageDir(2026, 3), l.registersDir())
	}
	if l.inferType("2 · Ventas/Contactos/fran.md") != "contact" || l.inferType("2 · Ventas/Contactos/Contactos.md") != "" || l.inferType("2 · Ventas/Sistemas/x.md") != "" {
		t.Error("type inference by folder")
	}
}

func TestMergeNoteKeepsBodyOrderAndAliases(t *testing.T) {
	old := "---\nid: 75840814-0f3a-831e-91b6-01d9fc75742e\ntipo: empresa\nnombre: NEXO Estudio  # a mano\nverificacion: Por revisar\n---\n\n# NEXO Estudio\n\nTexto de Manu.\n\n---\nUna regla horizontal no es frontmatter.\n"
	out, err := mergeNote([]byte(old), map[string]any{"name": "NEXO", "city": "Madrid", "tls_type": "organization"})
	if err != nil {
		t.Fatal(err)
	}
	s := string(out)
	_, body, _ := splitNote([]byte(old))
	if !strings.HasSuffix(s, body) {
		t.Fatalf("body changed:\n%s", s)
	}
	if strings.Contains(s, "\nname:") || !strings.Contains(s, "nombre: NEXO") || !strings.Contains(s, "verificacion: Por revisar") {
		t.Fatalf("alias or human key lost:\n%s", s)
	}
	if strings.Index(s, "id:") > strings.Index(s, "tipo:") || !strings.Contains(s, "city: Madrid") {
		t.Fatalf("key order not kept or new key missing:\n%s", s)
	}
	// A note without frontmatter gets one; its text stays below, unchanged.
	plain := "# The Last\n\nPropósito y límites.\n"
	out, _ = mergeNote([]byte(plain), map[string]any{"tls_type": "company"})
	if !strings.HasPrefix(string(out), "---\ntls_type: company\n---\n") || !strings.HasSuffix(string(out), plain) {
		t.Fatalf("plain note: %q", out)
	}
}

func TestDecisionLineRoundTripsAndCannotCloseTheComment(t *testing.T) {
	m := map[string]any{"id": "11111111-1111-1111-1111-111111111111", "workspace_id": "w", "title": "Precio", "decision": "95 € --> nuevo", "why": "Coste\nreal",
		"purpose": "Margen", "status": "decided", "context": "Varias\nlíneas", "created_at": "2026-10-21T09:00:00Z"}
	line, err := decisionLine(m)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Count(line, "\n") != 0 || strings.Count(line, "-->") != 1 {
		t.Fatalf("line is not one safe line: %q", line)
	}
	back := parseDecisionLine(line)
	if back["decision"] != "95 € --> nuevo" || back["context"] != "Varias\nlíneas" || back["workspace_id"] != nil {
		t.Fatalf("round trip: %v", back)
	}
}

func TestUpsertRowKeepsPeopleRowsAndColumns(t *testing.T) {
	p := filepath.Join(t.TempDir(), "recibidas.csv")
	head := strings.Join(registerHeaders["recibidas.csv"], ",") + ",nota\n"
	human := "REC-20261015-001,2026-10-15,Campsa,A1,EUR,40.00,,The Last,,revisado documental,manual,mía\n"
	_ = os.WriteFile(p, []byte(head+human), 0o644)
	if _, err := upsertRow(p, registerHeaders["recibidas.csv"], "abc", map[string]string{"tercero": "Hosting", "total_documento": "12.10", "documento": ""},
		map[string]string{"estado_revision": "pendiente", "fuente": "TLS"}); err != nil {
		t.Fatal(err)
	}
	// Updating keeps a value a person set and never blanks a known one.
	if _, err := upsertRow(p, registerHeaders["recibidas.csv"], "abc", map[string]string{"total_documento": "12.20"}, map[string]string{"estado_revision": "pendiente"}); err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(p)
	s := string(data)
	if !strings.HasPrefix(s, head+human) {
		t.Fatalf("header or human row changed:\n%s", s)
	}
	if strings.Count(s, "abc,") != 1 || !strings.Contains(s, "abc,,Hosting,,,12.20,,,,pendiente,TLS,") {
		t.Fatalf("app row:\n%s", s)
	}
}

// --- Integration: a copy of the target structure in a temp folder -------------

func writeFile(t *testing.T, root, rel, content string) {
	t.Helper()
	p := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, root, rel string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(rel)))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

const (
	empresaBody   = "# The Last\n\n## Propósito y límites\n\nTexto escrito por Manu que la app no debe pisar.\n"
	decisionesTxt = "# Decisiones\n\nRegistro append-only. Fecha · decisión · motivo · alcance · fuente.\n\n- 2026-10-15 · Corte local para nuevas operaciones. · Mandato de migración. · Notion queda como consulta.\n"
	nexoID        = "75840814-0f3a-831e-91b6-01d9fc75742e"
	nexoNote      = "---\nid: " + nexoID + "\ntipo: empresa\nnombre: NEXO Estudio\nverificacion: Por revisar\n---\n\n# NEXO Estudio\n\nIdentidad histórica consultada el 15/10/2026.\n"
	franNote      = "---\nid: 77340814-0f3a-833f-a737-013e0c1478b8\ntipo: persona\nnombre: Fran Moledo\nverificacion: Por revisar\n---\n\n# Fran Moledo\n\nMedio de contacto: pendiente.\n"
	ethiopiaNote  = "---\nid: 8c740814-0f3a-834c-812f-01441eb10433\nestado: Archivada\nfecha_corte: '2026-10-15'\n---\n\n# Inside Ethiopia Tours\n\nDecisión de Manu: archivada.\n"
	sinIDNote     = "# Persona sin ficha\n\nNotas a mano.\n"
	recibidaHuman = "REC-20261015-001,2026-10-15,Campsa,A1,EUR,40.00,,The Last,,revisado documental,manual\n"
)

// targetCopy builds a small copy of the target structure of The Last.
func targetCopy(t *testing.T) string {
	dir := t.TempDir()
	writeFile(t, dir, layoutFile, `{"preset": "humana"}`)
	writeFile(t, dir, "Empresa.md", empresaBody)
	writeFile(t, dir, "1 · Dirección/Área.md", "# Dirección\n")
	writeFile(t, dir, "1 · Dirección/Decisiones.md", decisionesTxt)
	writeFile(t, dir, "1 · Dirección/Sistemas/Valorar encargo.md", "# Valorar encargo\n\n## Para qué\n")
	writeFile(t, dir, "2 · Ventas/Empresas/nexo-estudio.md", nexoNote)
	writeFile(t, dir, "2 · Ventas/Contactos/Contactos.md", "# Contactos\n\nÍndice.\n")
	writeFile(t, dir, "2 · Ventas/Contactos/Plantilla persona.md", "---\ntipo: persona\n---\n")
	writeFile(t, dir, "2 · Ventas/Contactos/fran-moledo.md", franNote)
	writeFile(t, dir, "2 · Ventas/Contactos/sin-id.md", sinIDNote)
	writeFile(t, dir, "2 · Ventas/Oportunidades/inside-ethiopia-tours.md", ethiopiaNote)
	writeFile(t, dir, "4 · Finanzas/Registros/emitidas.csv", strings.Join(registerHeaders["emitidas.csv"], ",")+"\n")
	writeFile(t, dir, "4 · Finanzas/Registros/recibidas.csv", strings.Join(registerHeaders["recibidas.csv"], ",")+"\n"+recibidaHuman)
	writeFile(t, dir, "4 · Finanzas/Registros/pagos.csv", strings.Join(registerHeaders["pagos.csv"], ",")+"\n")
	writeFile(t, dir, "Archivo/8 - Archivo/Notion/vieja.md", "---\nid: 75840814-0f3a-831e-91b6-01d9fc75742e\ntipo: empresa\n---\nCopia antigua.\n")
	writeFile(t, dir, "Buzón/nota.md", "---\ntipo: persona\nid: 99999999-0000-0000-0000-000000000000\n---\n")
	return dir
}

func TestHumanFolderReadsHandMadeNotes(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()
	status, err := f.s.Folder.Status(ctx, f.ws)
	if err != nil {
		t.Fatal(err)
	}
	if status["inferred"] != 3 || status["files"] != 3 {
		t.Fatalf("hand-made notes not read: inferred=%v files=%v", status["inferred"], status["files"])
	}
	if errs := status["parse_errors"].([]map[string]string); len(errs) != 0 {
		t.Fatalf("notes outside record folders reported as errors: %v", errs)
	}
	props := status["proposals"].([]map[string]any)
	found := false
	for _, p := range props {
		if p["path"] == "2 · Ventas/Contactos/sin-id.md" {
			found = true
		}
		if strings.Contains(str(p["path"]), "Plantilla") || strings.Contains(str(p["path"]), "Contactos.md") || strings.HasPrefix(str(p["path"]), "Archivo") {
			t.Errorf("not a record: %v", p["path"])
		}
	}
	if !found {
		t.Fatalf("note without id not proposed: %v", props)
	}
	regs := status["registros"].(map[string]any)
	if un := regs["sin_vincular"].([]map[string]string); len(un) != 1 || un[0]["id"] != "REC-20261015-001" {
		t.Fatalf("human register row not listed: %v", regs)
	}

	res, err := f.s.Folder.Rebuild(ctx, f.ws, true)
	if err != nil {
		t.Fatal(err)
	}
	if res["applied"].(int) != 3 {
		t.Fatalf("rebuild applied %v: %v", res["applied"], res["parse_errors"])
	}
	org, err := rowMap(ctx, f.s.Pool, "organization", nexoID)
	if err != nil || org["name"] != "NEXO Estudio" || !strings.Contains(str(org["notes"]), "Identidad histórica") {
		t.Fatalf("organization from hand-made note: %v %v", org, err)
	}
	opp, err := rowMap(ctx, f.s.Pool, "opportunity", "8c740814-0f3a-834c-812f-01441eb10433")
	if err != nil || opp["title"] != "Inside Ethiopia Tours" {
		t.Fatalf("opportunity title from the heading: %v %v", opp, err)
	}

	// The app edits the record: the note keeps its name, body and human keys.
	f.must(owner, "record.update", map[string]any{"entity": "organization", "id": nexoID, "fields": map[string]any{"name": "NEXO", "city": "Madrid", "notes": "Texto de la app"}})
	f.s.Folder.FlushPending(ctx, f.ws)
	note := readFile(t, dir, "2 · Ventas/Empresas/nexo-estudio.md")
	_, body, _ := splitNote([]byte(nexoNote))
	if !strings.HasSuffix(note, body) || !strings.Contains(note, "nombre: NEXO\n") || !strings.Contains(note, "city: Madrid") || !strings.Contains(note, "verificacion: Por revisar") {
		t.Fatalf("human note not merged:\n%s", note)
	}
	if strings.Contains(note, "Texto de la app") || strings.Contains(note, "\nname:") {
		t.Fatalf("body or alias overwritten:\n%s", note)
	}
	if files, _ := filepath.Glob(filepath.Join(dir, "2 · Ventas", "Empresas", "*.md")); len(files) != 1 {
		t.Fatalf("a second file was created for the same record: %v", files)
	}
	if _, err := os.Stat(filepath.Join(dir, "Ventas")); !os.IsNotExist(err) {
		t.Fatal("an unnumbered area folder was created")
	}

	// Adopt adds only the minimal frontmatter; the text stays as it was.
	if _, err := f.s.Folder.Adopt(ctx, f.ws, true); err != nil {
		t.Fatal(err)
	}
	adopted := readFile(t, dir, "2 · Ventas/Contactos/sin-id.md")
	if !strings.HasSuffix(adopted, sinIDNote) || !strings.Contains(adopted, "tls_type: contact") || !strings.Contains(adopted, "\nid: ") {
		t.Fatalf("adopt:\n%s", adopted)
	}
	if fran := readFile(t, dir, "2 · Ventas/Contactos/fran-moledo.md"); !strings.HasSuffix(fran, "# Fran Moledo\n\nMedio de contacto: pendiente.\n") || !strings.Contains(fran, "id: 77340814") {
		t.Fatalf("adopt changed an existing id or body:\n%s", fran)
	}
}

func TestHumanFolderWritesWithoutOverwritingOrDeleting(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()
	f.service("RENTA", 9000)
	lead := f.must(owner, "lead.create", map[string]any{"contact": map[string]any{"name": "Lucía"}, "organization": map[string]any{"name": "Ferrer SL"}, "channel": "referido", "service_code": "RENTA"})
	d := f.must(owner, "decision.create", map[string]any{"area": "direccion", "title": "Política", "decision": "Cobrar antes", "why": "Caja", "purpose": "Foco"})
	if _, err := f.s.Folder.ExportAll(ctx, f.ws); err != nil {
		t.Fatal(err)
	}
	// Empresa.md: frontmatter added, the company's own text untouched.
	empresa := readFile(t, dir, "Empresa.md")
	if !strings.HasPrefix(empresa, "---\ntls_type: company\n") || !strings.HasSuffix(empresa, empresaBody) {
		t.Fatalf("Empresa.md:\n%s", empresa)
	}
	for _, d := range []string{"Buzón", "Archivo", "1 · Dirección/Sistemas", "1 · Dirección/Contratos", "5 · Marca/Recursos", "4 · Finanzas/Trámites"} {
		if st, err := os.Stat(filepath.Join(dir, filepath.FromSlash(d))); err != nil || !st.IsDir() {
			t.Errorf("skeleton folder %s missing", d)
		}
	}
	for _, g := range []string{"2 · Ventas/Empresas/ferrer-sl--*.md", "2 · Ventas/Contactos/lucia--*.md", "2 · Ventas/Oportunidades/*--*.md", "2 · Ventas/Productos/renta.md"} {
		if m, _ := filepath.Glob(filepath.Join(dir, filepath.FromSlash(g))); len(m) != 1 {
			t.Errorf("%s: %v", g, m)
		}
	}
	for _, old := range []string{"Ventas", "Dirección", "Entrega", "Finanzas"} {
		if _, err := os.Stat(filepath.Join(dir, old)); !os.IsNotExist(err) {
			t.Errorf("unnumbered folder %s created", old)
		}
	}
	// Decisions: one line per decision in Decisiones.md, human lines kept.
	f.must(owner, "decision.supersede", map[string]any{"id": d["id"], "decision": "Cobrar al 50 %", "why": "Caja real", "purpose": "Foco"})
	f.s.Folder.FlushPending(ctx, f.ws)
	dec := readFile(t, dir, "1 · Dirección/Decisiones.md")
	if !strings.HasPrefix(dec, decisionesTxt) || strings.Count(dec, decisionMark) != 2 || !strings.Contains(dec, "(sustituida)") {
		t.Fatalf("Decisiones.md:\n%s", dec)
	}
	if _, err := os.Stat(filepath.Join(dir, "1 · Dirección", "Decisiones")); !os.IsNotExist(err) {
		t.Fatal("one file per decision created")
	}

	// Retiring a record moves its file to Archivo/; nothing is deleted.
	orgID := str(lead["organization_id"])
	if orgID == "" {
		_ = f.s.Pool.QueryRow(ctx, `SELECT organization_id::text FROM biz_opportunity WHERE id=$1`, lead["id"]).Scan(&orgID)
	}
	orgFiles, _ := filepath.Glob(filepath.Join(dir, "2 · Ventas", "Empresas", "ferrer-sl--*.md"))
	writeFile(t, dir, "2 · Ventas/Empresas/"+filepath.Base(orgFiles[0]), strings.Replace(readFile(t, dir, "2 · Ventas/Empresas/"+filepath.Base(orgFiles[0])), "\n---\n\n", "\n---\n\nNota escrita a mano.\n", 1))
	_, _ = f.s.Pool.Exec(ctx, `UPDATE biz_organization SET archived_at=now() WHERE id=$1`, orgID)
	_, _ = f.s.Pool.Exec(ctx, `INSERT INTO biz_journal (workspace_id, entity_type, entity_id, rel_path) VALUES ($1,'organization',$2,'')`, f.ws, orgID)
	f.s.Folder.FlushPending(ctx, f.ws)
	if _, err := os.Stat(orgFiles[0]); !os.IsNotExist(err) {
		t.Fatal("retired file still in its folder")
	}
	archived := readFile(t, dir, "Archivo/2 · Ventas/Empresas/"+filepath.Base(orgFiles[0]))
	if !strings.Contains(archived, "Nota escrita a mano.") || !strings.Contains(archived, "archived_at:") {
		t.Fatalf("archived note:\n%s", archived)
	}
	// Rebuild reads the retired record from Archivo and the decisions file.
	_, _ = f.s.Pool.Exec(ctx, `DELETE FROM biz_decision WHERE workspace_id=$1`, f.ws)
	_, _ = f.s.Pool.Exec(ctx, `DELETE FROM biz_organization WHERE id=$1`, orgID)
	res, err := f.s.Folder.Rebuild(ctx, f.ws, true)
	if err != nil {
		t.Fatal(err)
	}
	var n int
	_ = f.s.Pool.QueryRow(ctx, `SELECT count(*) FROM biz_decision WHERE workspace_id=$1`, f.ws).Scan(&n)
	if n != 2 {
		t.Fatalf("decisions rebuilt from Decisiones.md: %d (%v)", n, res["parse_errors"])
	}
	if _, err := rowMap(ctx, f.s.Pool, "organization", orgID); err != nil {
		t.Fatalf("retired organization not rebuilt from Archivo: %v", err)
	}
	if dups := res["duplicate_ids"].([]map[string]any); len(dups) != 0 {
		t.Fatalf("duplicate ids: %v", dups)
	}
}

func TestHumanFolderRegistersAreTheSource(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()
	f.service("TRIM", 15000)
	opp := f.must(owner, "lead.create", map[string]any{"contact": map[string]any{"name": "Ana"}, "organization": map[string]any{"name": "Taller SL"}, "channel": "web", "service_code": "TRIM"})
	id := opp["id"].(string)
	f.must(owner, "opportunity.move", map[string]any{"id": id, "stage": "cualificacion"})
	f.must(owner, "opportunity.proposal", map[string]any{"id": id})
	f.must(owner, "opportunity.accept", map[string]any{"id": id, "evidence": "Correo"})
	f.s.ProcessEvents(ctx)
	var invoiceID string
	var total int64
	if err := f.s.Pool.QueryRow(ctx, `SELECT id, total_minor FROM biz_invoice WHERE opportunity_id=$1`, id).Scan(&invoiceID, &total); err != nil {
		t.Fatal(err)
	}
	f.s.Folder.FlushPending(ctx, f.ws)
	if s := readFile(t, dir, "4 · Finanzas/Registros/emitidas.csv"); strings.Contains(s, invoiceID) {
		t.Fatal("a draft was registered as issued")
	}
	f.must(owner, "invoice.issue", map[string]any{"id": invoiceID})
	f.must(owner, "payment.confirm", map[string]any{"invoice_id": invoiceID, "amount_minor": total, "evidence": "Transferencia ref. 123"})
	f.s.ProcessEvents(ctx)
	f.s.Folder.FlushPending(ctx, f.ws)

	emitidas := readFile(t, dir, "4 · Finanzas/Registros/emitidas.csv")
	if strings.Count(emitidas, invoiceID) != 1 || !strings.Contains(emitidas, ",Taller SL,") || !strings.Contains(emitidas, ",181.50,") {
		t.Fatalf("emitidas.csv:\n%s", emitidas)
	}
	pagos := readFile(t, dir, "4 · Finanzas/Registros/pagos.csv")
	if !strings.Contains(pagos, ",cobro,181.50,EUR,,"+invoiceID+",") || !strings.Contains(pagos, "Transferencia ref. 123,confirmado") {
		t.Fatalf("pagos.csv:\n%s", pagos)
	}
	if !strings.HasSuffix(readFile(t, dir, "4 · Finanzas/Registros/recibidas.csv"), recibidaHuman) {
		t.Fatal("a person's row in recibidas.csv changed")
	}
	if m, _ := filepath.Glob(filepath.Join(dir, "4 · Finanzas", "Fiscal", "*", "T*", "Ingresos", "*.md")); len(m) != 1 {
		t.Fatalf("issued invoice note: %v", m)
	}
	if m, _ := filepath.Glob(filepath.Join(dir, "4 · Finanzas", "Fiscal", "*", "T*", "Cobros y pagos")); len(m) != 0 {
		t.Fatalf("payments duplicated as notes: %v", m)
	}
	// Writing again does not duplicate rows.
	_, _ = f.s.Folder.ExportAll(ctx, f.ws)
	if strings.Count(readFile(t, dir, "4 · Finanzas/Registros/pagos.csv"), "\n") != 2 || strings.Count(readFile(t, dir, "4 · Finanzas/Registros/emitidas.csv"), "\n") != 2 {
		t.Fatal("rows duplicated on re-export")
	}

	// A person corrects the total in the register: the register wins.
	reg := readFile(t, dir, "4 · Finanzas/Registros/emitidas.csv")
	writeFile(t, dir, "4 · Finanzas/Registros/emitidas.csv", strings.Replace(reg, ",181.50,", ",181.60,", 1))
	preview, _ := f.s.Folder.Rebuild(ctx, f.ws, false)
	found := false
	for _, d := range preview["different"].([]map[string]any) {
		if strings.HasSuffix(str(d["path"]), "emitidas.csv#"+invoiceID) {
			found = true
		}
	}
	if !found {
		t.Fatalf("register edit not detected: %v", preview["different"])
	}
	if _, err := f.s.Folder.Rebuild(ctx, f.ws, true); err != nil {
		t.Fatal(err)
	}
	var after int64
	_ = f.s.Pool.QueryRow(ctx, `SELECT total_minor FROM biz_invoice WHERE id=$1`, invoiceID).Scan(&after)
	if after != 18160 {
		t.Fatalf("register did not win: %d", after)
	}
	// Payments live only in pagos.csv and rebuild from it.
	var paymentID string
	_ = f.s.Pool.QueryRow(ctx, `SELECT id::text FROM biz_payment WHERE invoice_id=$1`, invoiceID).Scan(&paymentID)
	_, _ = f.s.Pool.Exec(ctx, `DELETE FROM biz_payment WHERE id=$1`, paymentID)
	if _, err := f.s.Folder.Rebuild(ctx, f.ws, true); err != nil {
		t.Fatal(err)
	}
	p, err := rowMap(ctx, f.s.Pool, "payment", paymentID)
	if err != nil || minorOf(p["amount_minor"]) != 18150 || p["status"] != "confirmed" {
		t.Fatalf("payment not rebuilt from pagos.csv: %v %v", p, err)
	}
}
