package biz

import (
	"context"
	"strings"
	"testing"
)

const tesoreria = "# Tesorería\n\n> 4 · Finanzas · Activo · Lo lleva Mika\n\n## Para qué\n\nConocer la caja real.\n\n## Pasos\n\n1. Anotar el saldo.\n2. Conciliar.\n\n## Origen\n\nNotion.\n"

func TestParseSystemKeepsSectionsAndSummary(t *testing.T) {
	d := parseSystem("4 · Finanzas/Sistemas/Tesorería.md", []byte(tesoreria))
	if d.Title != "Tesorería" || d.Summary != "4 · Finanzas · Activo · Lo lleva Mika" || d.Status != "Activo" || d.Owner != "Lo lleva Mika" {
		t.Fatalf("header: %+v", d)
	}
	if len(d.Sections) != 3 || d.Sections[1].Heading != "Pasos" || d.Sections[1].Body != "1. Anotar el saldo.\n2. Conciliar." {
		t.Fatalf("sections: %+v", d.Sections)
	}
}

func TestSplitDotsKeepsAreaNames(t *testing.T) {
	got := splitDots("La app es el producto. Autónomo se integra en 4 · Finanzas. · Mandato de Manu. · Fuente: MANU-16")
	want := []string{"La app es el producto. Autónomo se integra en 4 · Finanzas.", "Mandato de Manu.", "Fuente: MANU-16"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("got %q", got)
	}
}

func TestHumanDecisionFields(t *testing.T) {
	m := humanDecision("- 2026-10-21 · Diseño de las 6 áreas aprobado: The Last sigue lateral. Marca en reposo. · Aprobación de Manu en MANU-16. · Sistemas escritos en `Sistemas/`.")
	if m == nil || m["decided_at"] != "2026-10-21T12:00:00Z" || m["status"] != "decided" || m["why"] != "Aprobación de Manu en MANU-16." ||
		m["title"] != "Diseño de las 6 áreas aprobado: The Last sigue lateral" || m["purpose"] != "Sistemas escritos en `Sistemas/`." {
		t.Fatalf("%v", m)
	}
	if humanDecision("Registro append-only. Fecha · decisión · motivo") != nil {
		t.Fatal("header line read as a decision")
	}
}

// A person's Decisiones.md is imported without rewriting its text: TLS only
// appends the id mark, rebuilds the projection from the visible text, and a
// correction made in the app keeps the words and adds "(sustituida)".
func TestHumanDecisionsImportKeepsText(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	extra := "- 2026-10-21 · La app es el producto; Autónomo se integra en 4 · Finanzas. · Mandato explícito de Manu. · Fuente: MANU-16."
	rel := "1 · Dirección/Decisiones.md"
	writeFile(t, dir, rel, decisionesTxt+"\n"+extra+"\n")
	before := readFile(t, dir, rel)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()

	prev, err := f.s.Folder.Adopt(ctx, f.ws, false)
	if err != nil {
		t.Fatal(err)
	}
	n := 0
	for _, p := range prev["proposals"].([]map[string]any) {
		if p["type"] == "decision" {
			n++
		}
	}
	if n != 2 {
		t.Fatalf("decision proposals = %d, want 2", n)
	}
	sinID := readFile(t, dir, "2 · Ventas/Contactos/sin-id.md")
	if _, err := f.s.Folder.Adopt(ctx, f.ws, true, "decision"); err != nil {
		t.Fatal(err)
	}
	if readFile(t, dir, "2 · Ventas/Contactos/sin-id.md") != sinID {
		t.Fatal("adopting decisions touched other notes")
	}
	after := readFile(t, dir, rel)
	bl, al := strings.Split(before, "\n"), strings.Split(after, "\n")
	if len(bl) != len(al) {
		t.Fatalf("line count changed:\n%s", after)
	}
	for i := range bl {
		if !strings.HasPrefix(al[i], bl[i]) {
			t.Fatalf("line %d rewritten:\n%q\n%q", i+1, bl[i], al[i])
		}
		if al[i] != bl[i] && !strings.Contains(al[i], `"origen":"texto"`) {
			t.Fatalf("line %d: unexpected change %q", i+1, al[i])
		}
	}
	// Adopting again changes nothing.
	if _, err := f.s.Folder.Adopt(ctx, f.ws, true); err != nil || readFile(t, dir, rel) != after {
		t.Fatalf("second adopt changed the file (%v)", err)
	}

	if _, err := f.s.Folder.Rebuild(ctx, f.ws, true); err != nil {
		t.Fatal(err)
	}
	cmp, _ := f.s.Folder.Rebuild(ctx, f.ws, false)
	if d := decisionsIn(cmp); d != 0 {
		t.Fatalf("rebuild not stable: %v %v", cmp["different"], cmp["missing_in_db"])
	}
	var id, title, why, purpose, day string
	if err := f.s.Pool.QueryRow(ctx, `SELECT id, title, why, purpose, to_char(decided_at AT TIME ZONE 'Europe/Madrid', 'YYYY-MM-DD') FROM biz_decision
		WHERE workspace_id=$1 AND why='Mandato explícito de Manu.'`, f.ws).Scan(&id, &title, &why, &purpose, &day); err != nil {
		t.Fatal(err)
	}
	if title != "La app es el producto; Autónomo se integra en 4 · Finanzas" || purpose != "Fuente: MANU-16." || day != "2026-10-21" {
		t.Fatalf("decision: %q %q %q", title, purpose, day)
	}

	// Correcting it in the app: the person's words stay.
	f.must(owner, "decision.supersede", map[string]any{"id": id, "decision": "Nueva redacción", "why": "Ajuste", "purpose": "Foco"})
	f.s.Folder.FlushPending(ctx, f.ws)
	final := readFile(t, dir, rel)
	if !strings.Contains(final, extra+" (sustituida) "+decisionMark) {
		t.Fatalf("superseded line lost its text:\n%s", final)
	}
	if !strings.Contains(final, "Nueva redacción") {
		t.Fatalf("new decision not appended:\n%s", final)
	}
	cmp, _ = f.s.Folder.Rebuild(ctx, f.ws, false)
	if decisionsIn(cmp) != 0 {
		t.Fatalf("after supersede: %v", cmp["different"])
	}
}

// decisionsIn counts decisions the rebuild still sees as different or missing.
func decisionsIn(cmp map[string]any) int {
	n := 0
	for _, k := range []string{"different", "missing_in_db"} {
		for _, d := range cmp[k].([]map[string]any) {
			if d["type"] == "decision" {
				n++
			}
		}
	}
	return n
}

func TestSystemsAndDocumentsReadTheFolder(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	writeFile(t, dir, "4 · Finanzas/Sistemas/Tesorería.md", tesoreria)
	writeFile(t, dir, "4 · Finanzas/Sistemas/Control económico.md", "# Control económico\n\n## Para qué\n\nX.\n")
	writeFile(t, dir, "4 · Finanzas/Sistemas/Control económico/Incorporar gasto.md", "# Incorporar gasto\n\n## Entrada\n\nOriginal.\n")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T3/Gastos/Apple/2026-07-14 factura.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2025/Cuentas.numbers/Index.zip", "zip")
	writeFile(t, dir, "4 · Finanzas/Gestoría/2025 Urba gestores/acta.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Trámites/Baja IT 2026/parte.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Trámites/Baja IT 2026/.DS_Store", "")
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()

	sys, err := f.s.Folder.Systems(ctx, f.ws, "finanzas")
	if err != nil {
		t.Fatal(err)
	}
	docs := sys["systems"].([]systemDoc)
	if len(docs) != 2 || docs[0].Title != "Control económico" || len(docs[0].Children) != 1 || docs[1].Sections[0].Body != "Conocer la caja real." {
		t.Fatalf("systems: %+v", docs)
	}

	list := func(a Actor) map[string]libraryDoc {
		out, err := f.s.Folder.Documents(ctx, f.ws, a)
		if err != nil {
			t.Fatal(err)
		}
		m := map[string]libraryDoc{}
		for _, d := range out["documents"].([]libraryDoc) {
			m[d.Name] = d
		}
		return m
	}
	m := list(owner)
	inv := m["2026-07-14 factura.pdf"]
	if inv.Group != "Fiscal" || inv.Year != 2026 || inv.Quarter != "T3" || inv.Kind != "Gastos" || inv.Detail != "Apple" || inv.Date != "2026-07-14" || inv.DateSource != "nombre" {
		t.Fatalf("invoice: %+v", inv)
	}
	if d, ok := m["Cuentas.numbers"]; !ok || d.Size != 3 {
		t.Fatalf("package not read as one document: %+v", m)
	}
	if _, ok := m["Index.zip"]; ok {
		t.Fatal("walked into a package")
	}
	baja, ok := m["parte.pdf"]
	if !ok || !baja.Private || baja.Kind != "Baja IT 2026" || baja.Group != "Trámites" {
		t.Fatalf("IT leave must be a document for people: %+v", baja)
	}
	if _, ok := m[".DS_Store"]; ok {
		t.Fatal(".DS_Store listed")
	}
	if g := m["acta.pdf"]; g.Group != "Gestoría" || g.Kind != "2025 Urba gestores" {
		t.Fatalf("gestoría: %+v", g)
	}

	// The dates index gives the real date of a document whose name has none;
	// one in "Sin trimestre" shows the quarter of that date, without moving it.
	writeFile(t, dir, "4 · Finanzas/Fiscal/2025/Sin trimestre/Gastos/Combustible/Campsa.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2025/Sin trimestre/Ingresos/F-41.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fechas de documentos.csv", "ruta,fecha,fuente,nota\n"+
		"4 · Finanzas/Fiscal/2025/Sin trimestre/Gastos/Combustible/Campsa.pdf,2025-11-03,documento,leída del escaneo (OCR)\n"+
		"4 · Finanzas/Gestoría/2025 Urba gestores/acta.pdf,2025-07-31,manual,\n"+
		"4 · Finanzas/Fiscal/2026/T3/Gastos/Apple/2026-07-14 factura.pdf,2020-01-01,documento,\n")
	m = list(owner)
	if c := m["Campsa.pdf"]; c.Date != "2025-11-03" || c.DateSource != "documento" || c.DateNote != "leída del escaneo (OCR)" || c.Year != 2025 || c.Quarter != "T4" || !c.QuarterFromDate || c.Kind != "Gastos" {
		t.Fatalf("indexed date: %+v", c)
	}
	if c := m["F-41.pdf"]; c.DateSource != "archivo" || c.Quarter != "Sin trimestre" || c.QuarterFromDate {
		t.Fatalf("without a readable date it stays in Sin trimestre: %+v", c)
	}
	if g := m["acta.pdf"]; g.Date != "2025-07-31" || g.DateSource != "manual" {
		t.Fatalf("manual date: %+v", g)
	}
	if inv := m["2026-07-14 factura.pdf"]; inv.Date != "2026-07-14" || inv.DateSource != "nombre" {
		t.Fatalf("the name wins over the index: %+v", inv)
	}
	if _, ok := m["Fechas de documentos.csv"]; ok {
		t.Fatal("the index is not a document")
	}

	agent := f.agent("finanzas")
	if _, ok := list(agent)["parte.pdf"]; ok {
		t.Fatal("agents must never get private documents")
	}
	if _, _, err := f.s.Folder.resolveInFolder(ctx, f.ws, agent, "4 · Finanzas/Trámites/Baja IT 2026/parte.pdf"); err == nil {
		t.Fatal("agent opened a private document")
	}
	if _, _, err := f.s.Folder.resolveInFolder(ctx, f.ws, owner, "4 · Finanzas/Trámites/Baja IT 2026/parte.pdf"); err != nil {
		t.Fatalf("owner cannot open the original: %v", err)
	}
	for _, bad := range []string{"../etc/passwd", ".tls/layout.json", "4 · Finanzas/../../x"} {
		if _, _, err := f.s.Folder.resolveInFolder(ctx, f.ws, owner, bad); err == nil {
			t.Fatalf("%s accepted", bad)
		}
	}
}

// Without a target configured by the company a KPI shows its value with no
// verdict: there are no factory targets.
func TestKPIsWithoutFactoryTargets(t *testing.T) {
	f := newFixture(t)
	ctx := context.Background()
	if err := f.s.EnsureBootstrap(ctx, f.ws); err != nil {
		t.Fatal(err)
	}
	kpis, err := f.s.ComputeKPIs(ctx, f.ws, "")
	if err != nil {
		t.Fatal(err)
	}
	for _, k := range kpis {
		if k.Target != nil || k.Status == "warning" || k.Status == "alert" {
			t.Fatalf("%s: target %v status %s", k.Code, k.Target, k.Status)
		}
	}
	f.must(owner, "kpi.update", map[string]any{"code": "DIR-DEC", "target": 3, "alert": 8})
	f.must(owner, "kpi.update", map[string]any{"code": "DIR-DEC", "clear": true})
	var target *float64
	_ = f.s.Pool.QueryRow(ctx, `SELECT target::float8 FROM biz_kpi WHERE workspace_id=$1 AND code='DIR-DEC'`, f.ws).Scan(&target)
	if target != nil {
		t.Fatalf("clear left target %v", *target)
	}
}

// A note a person wrote in Productos/ is adopted with only tls_type,
// tls_schema and id; the rebuild names the service by its H1 and takes the
// code from the file name, so the row satisfies the table without rewriting
// the note.
func TestAdoptedServiceNoteRebuilds(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	rel := "2 · Ventas/Productos/Oferta.md"
	body := "# Oferta\n\nEncargos puntuales que se acuerdan uno a uno.\n"
	writeFile(t, dir, rel, body)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()

	if _, err := f.s.Folder.Adopt(ctx, f.ws, true, "service"); err != nil {
		t.Fatal(err)
	}
	after := readFile(t, dir, rel)
	if !strings.HasSuffix(after, "---\n\n"+body) || !strings.Contains(after, "tls_type: service") {
		t.Fatalf("adopted note:\n%s", after)
	}
	res, err := f.s.Folder.Rebuild(ctx, f.ws, true)
	if err != nil {
		t.Fatal(err)
	}
	if errs := res["parse_errors"].([]map[string]string); len(errs) != 0 {
		t.Fatalf("rebuild errors: %v", errs)
	}
	var code, name string
	if err := f.s.Pool.QueryRow(ctx, `SELECT code, name FROM biz_service WHERE workspace_id=$1 AND name='Oferta'`, f.ws).Scan(&code, &name); err != nil {
		t.Fatal(err)
	}
	if code != "oferta" {
		t.Fatalf("code %q", code)
	}
	cmp, _ := f.s.Folder.Rebuild(ctx, f.ws, false)
	for _, k := range []string{"different", "missing_in_db"} {
		for _, d := range cmp[k].([]map[string]any) {
			if d["path"] == rel {
				t.Fatalf("not stable (%s): %v", k, d)
			}
		}
	}
	if readFile(t, dir, rel) != after {
		t.Fatal("rebuild wrote to the note")
	}
}
