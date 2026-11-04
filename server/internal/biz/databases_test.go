package biz

import (
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestInvoiceFromName(t *testing.T) {
	cases := map[string][4]string{
		"2026-02-06 F260002 José Miguel Mesa 4.560€.pdf":               {"2026-02-06", "F260002", "José Miguel Mesa", "4.560"},
		"2026-09-30 Aseskonta 121,00 euros.pdf":                        {"2026-09-30", "", "Aseskonta", "121,00"},
		"2026-02-05 CN260001 José Miguel Mesa ANULADA.pdf":             {"2026-02-05", "CN260001", "José Miguel Mesa ANULADA", ""},
		"2026-06-30 CN260004 Clara Ibáñez rectificativa -572,40€.pdf": {"2026-06-30", "CN260004", "Clara Ibáñez rectificativa", "-572,40"},
		"FACT_41 Rectificativa.pdf":                                    {"", "", "FACT 41 Rectificativa", ""},
	}
	for name, want := range cases {
		d, n, p, a := invoiceFromName(name)
		if got := [4]string{d, n, p, a}; got != want {
			t.Errorf("%s: got %q, want %q", name, got, want)
		}
	}
}

func TestNoteRefsResolveRelativeLinks(t *testing.T) {
	body := "Empresa: [Muebles](../Empresas/muebles.md)\n[Portal](Portal.md) · [web](https://x.es) · [Materiales](Materiales) · [ancla](#a)\n[NEXO](../../../2%20·%20Ventas/Empresas/nexo-estudio.md)"
	got := noteRefs("3 · Entrega/Proyectos/nexo/Proyecto.md", body)
	want := []string{"3 · Entrega/Proyectos/Empresas/muebles.md", "3 · Entrega/Proyectos/nexo/Portal.md", "3 · Entrega/Proyectos/nexo/Materiales", "2 · Ventas/Empresas/nexo-estudio.md"}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("got %q", got)
	}
}

const agentesTxt = "# Agentes de IA\n\n> 6 · Equipo · En reposo · Lo lleva Mika\n\n## Inventario (21/10/2026)\n\n| Agente | Área | Estado | Puede | Nunca |\n|---|---|---|---|---|\n" +
	"| Mika | Dirección, Finanzas | Activo | Preparar | Enviar sin Manu |\n| Comercial | Ventas | Creado | Borradores | Enviar |\n"

func databasesFolder(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	writeFile(t, dir, ".tls/layout.json", `{"preset": "humana"}`)
	writeFile(t, dir, "2 · Ventas/Contactos/Contactos.md", "# Contactos\n\n- [ana](ana.md)\n")
	writeFile(t, dir, "2 · Ventas/Contactos/Plantilla persona.md", "# Plantilla\n")
	writeFile(t, dir, "2 · Ventas/Contactos/ana.md", "---\nid: 11111111-0000-0000-0000-000000000001\ntipo: persona\nnombre: Ana Ruiz\nverificacion: Por revisar\n---\n\n# Ana Ruiz\n\nEmpresa: [Ejemplo SL](../Empresas/ejemplo.md)\n")
	writeFile(t, dir, "2 · Ventas/Empresas/ejemplo.md", "---\nid: 11111111-0000-0000-0000-000000000002\ntipo: empresa\nnombre: Ejemplo SL\n---\n\n# Ejemplo SL\n")
	writeFile(t, dir, "2 · Ventas/Oportunidades/Espacius/2026-06-22/Propuesta.pdf", "x")
	writeFile(t, dir, "3 · Entrega/Proyectos/ejemplo-tls/Proyecto.md", "---\nid: p1\nestado: En curso\n---\n\n# Ejemplo — Implementación\n\nCliente: [Ejemplo SL](../../../2%20·%20Ventas/Empresas/ejemplo.md)\n")
	writeFile(t, dir, "3 · Entrega/Proyectos/ejemplo-tls/Tareas.md", "# Tareas\n\n- [ ] T-1 Preparar el kit · vence 2026-10-30\n- [x] Enviar acceso\n")
	writeFile(t, dir, "3 · Entrega/Proyectos/ejemplo-tls/Portal.md", portalTxt)
	writeFile(t, dir, "3 · Entrega/Proyectos/ejemplo-tls/Incidencias.md", incidenciasTxt)
	writeFile(t, dir, "4 · Finanzas/Registros/emitidas.csv", strings.Join(registerHeaders["emitidas.csv"], ",")+"\nEMI-1,2026-10-01,Ejemplo SL,F260010,EUR,600.00,,consultoria,,emitida,manual\n")
	writeFile(t, dir, "4 · Finanzas/Registros/recibidas.csv", strings.Join(registerHeaders["recibidas.csv"], ",")+"\n")
	writeFile(t, dir, "4 · Finanzas/Registros/pagos.csv", strings.Join(registerHeaders["pagos.csv"], ",")+"\n")
	writeFile(t, dir, "4 · Finanzas/Registros/importar/2026 T4 movimientos.csv", "id,fecha,concepto,importe,tipo,numero_factura\nmv-1,2026-10-05,Cobro F260010,600.00,Ingreso,F260010\n")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T4/Ingresos/2026-10-01 F260010 Ejemplo SL 600€.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T4/Gastos/Notion/2026-10-02 Notion 10 euros.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Gestoría/Dudas pendientes.md", "# Dudas\n")
	writeFile(t, dir, "4 · Finanzas/Trámites/Baja IT 2026/parte.pdf", "%PDF")
	writeFile(t, dir, "1 · Dirección/Decisiones.md", decisionesTxt+"- 2026-10-21 · Facturar desde el autónomo. · Decisión de Manu. · Sin intermediarios.\n"+
		"- 2026-10-21 · Oferta aprobada. · Decisión de Manu. · Bloque 2. <!-- tls:decision {\"id\":\"22222222-0000-0000-0000-000000000001\",\"origen\":\"texto\"} -->\n")
	writeFile(t, dir, "1 · Dirección/Sistemas/Decisiones.md", "# Decisiones\n\n> 1 · Dirección · Activo · Lo lleva Mika\n\n## Para qué\n\nQue lo decidido no se pierda.\n")
	writeFile(t, dir, "6 · Equipo/Sistemas/Agentes de IA.md", agentesTxt)
	writeFile(t, dir, "6 · Equipo/Colaboraciones/Colaboraciones.md", "# Colaboraciones\n\nSin equipo permanente.\n")
	writeFile(t, dir, "5 · Marca/Recursos/Web/index.html", "x")
	return dir
}

func folderDigest(t *testing.T, root string) string {
	t.Helper()
	var b strings.Builder
	_ = filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if d != nil && d.IsDir() && d.Name() == ".tls" {
			return filepath.SkipDir // the writer's own state, not the company's data
		}
		if err == nil && !d.IsDir() {
			data, _ := os.ReadFile(p)
			b.WriteString(p + ":" + hashBytes(data) + "\n")
		}
		return nil
	})
	return b.String()
}

func findRow(rows []dbRow, title string) *dbRow {
	for i := range rows {
		if rows[i].Title == title {
			return &rows[i]
		}
	}
	return nil
}

func hasLink(r *dbRow, db, title string) bool {
	for _, l := range r.Links {
		if l.DB == db && l.Title == title {
			return true
		}
	}
	return false
}

// Every database is read from its own place in the folder, the relations
// between rows come from the links a person wrote, and nothing is written.
func TestDatabasesReadTheFolderWithRelations(t *testing.T) {
	f := newFixture(t)
	dir := databasesFolder(t)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	before := folderDigest(t, dir)
	ctx := context.Background()

	rd, err := f.s.newDBReader(ctx, f.ws, owner)
	if err != nil {
		t.Fatal(err)
	}
	all, cat := rd.all()
	if len(cat) != 17 {
		t.Fatalf("catalog has %d databases", len(cat))
	}
	count := map[string]int{}
	for _, d := range cat {
		count[d.Key] = d.Count
		if d.Fill == "" || d.Source == "" {
			t.Errorf("%s: an empty database must say how it is filled", d.Key)
		}
	}
	want := map[string]int{"contactos": 1, "empresas": 1, "oportunidades": 1, "proyectos": 1, "tareas": 5, "reuniones": 9, "incidencias": 2,
		"facturas": 3, "pagos": 1, "trimestres": 1, "decisiones": 3, "sistemas": 2, "contenido": 0, "agentes": 2}
	for k, n := range want {
		if count[k] != n {
			t.Errorf("%s: %d rows, want %d", k, count[k], n)
		}
	}

	ana := findRow(all["contactos"], "Ana Ruiz")
	if ana == nil || ana.Status != "Por revisar" || ana.get("Empresa") != "Ejemplo SL" || !hasLink(ana, "empresas", "Ejemplo SL") {
		t.Fatalf("contact: %+v", ana)
	}
	project := findRow(all["proyectos"], "Ejemplo — Implementación")
	if project == nil || !hasLink(project, "empresas", "Ejemplo SL") || project.get("Avance") == "" {
		t.Fatalf("project: %+v", project)
	}
	task := findRow(all["tareas"], "T-1 Preparar el kit")
	if task == nil || task.Status != "Pendiente" || task.Date != "2026-10-30" || task.get("ID") != "T-1" || !hasLink(task, "proyectos", project.Title) {
		t.Fatalf("task: %+v", task)
	}
	if opp := findRow(all["oportunidades"], "Espacius"); opp == nil || opp.Date != "2026-06-22" || opp.Status != "Propuesta sin ficha" {
		t.Fatalf("proposal folder: %+v", opp)
	}
	mv := findRow(all["pagos"], "Cobro F260010")
	if mv == nil || mv.Status != "Por importar" || !hasLink(mv, "facturas", "F260010") {
		t.Fatalf("movement: %+v", mv)
	}
	pdf := findRow(all["facturas"], "2026-10-01 F260010 Ejemplo SL 600€.pdf")
	if pdf == nil || pdf.Status != "Registrada" || pdf.get("Importe") != "600 €" || !hasLink(pdf, "trimestres", "T4 2026") {
		t.Fatalf("invoice pdf: %+v", pdf)
	}
	if g := findRow(all["facturas"], "2026-10-02 Notion 10 euros.pdf"); g == nil || g.get("Tercero") != "Notion" || g.Status != "Sin registrar" {
		t.Fatalf("expense pdf: %+v", g)
	}
	var unmarked int
	for _, d := range all["decisiones"] {
		if d.Status == "Sin registrar en la app" {
			unmarked++
		}
	}
	if unmarked != 2 {
		t.Fatalf("decisions without mark = %d", unmarked)
	}
	if m := findRow(all["agentes"], "Mika"); m == nil || m.Area != "direccion" || m.get("Nunca") != "Enviar sin Manu" {
		t.Fatalf("agent: %+v", m)
	}
	var private bool
	for _, d := range all["documentos"] {
		private = private || d.Private
	}
	if !private {
		t.Fatal("the IT leave must be marked private")
	}

	// The detail lists what points at a row and the text of its note.
	detail, err := rd.detail(all, "empresas", "11111111-0000-0000-0000-000000000002")
	if err != nil {
		t.Fatal(err)
	}
	inbound := detail["inbound"].([]dbLink)
	if len(inbound) != 2 || !strings.Contains(detail["body"].(string), "# Ejemplo SL") {
		t.Fatalf("detail: %+v", detail)
	}

	// Agents never get private documents.
	agent := Actor{Type: "agent", ID: "a"}
	ra, _ := f.s.newDBReader(ctx, f.ws, agent)
	for _, d := range ra.documentos() {
		if d.Private {
			t.Fatalf("agent got a private document: %s", d.Path)
		}
	}

	if after := folderDigest(t, dir); after != before {
		t.Fatalf("reading the databases changed the folder:\n%s\n---\n%s", before, after)
	}
}
