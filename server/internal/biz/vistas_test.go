package biz

import (
	"context"
	"testing"
	"time"
)

func TestParseEuros(t *testing.T) {
	cases := map[string]float64{"4.560 €": 4560, "1202,70 euros": 1202.70, "-572,40 €": -572.40, "2,13 €": 2.13, "2.850": 2850, "600.00 EUR": 600, "1.234,5": 1234.5}
	for in, want := range cases {
		if got := parseEuros(in); got == nil || *got != want {
			t.Errorf("%q: got %v, want %v", in, got, want)
		}
	}
	for _, in := range []string{"", "sin importe", "—"} {
		if got := parseEuros(in); got != nil {
			t.Errorf("%q: got %v, want nil", in, *got)
		}
	}
}

func TestPeriodStartAndLabel(t *testing.T) {
	d := time.Date(2026, 10, 21, 15, 0, 0, 0, time.UTC) // Wednesday
	cases := []struct {
		k          periodKind
		start, key string
	}{{perWeek, "2026-10-19", "2026-S43"}, {perMonth, "2026-10-01", "2026-10"}, {perQuarter, "2026-10-01", "2026-T4"}}
	for _, c := range cases {
		s := periodStart(c.k, d)
		key, _ := bucketLabel(c.k, s)
		if s.Format("2006-01-02") != c.start || key != c.key {
			t.Errorf("%s: start %s key %s", c.k, s.Format("2006-01-02"), key)
		}
	}
}

func TestStageFromText(t *testing.T) {
	cases := map[string][2]string{"Prospecto": {"entrada", ""}, "Diagnóstico": {"diagnostico", ""}, "Propuesta enviada": {"propuesta", ""},
		"Archivada": {"", "archivada"}, "Perdida": {"", "perdida"}, "Ganada": {"ganada", "ganada"}, "": {"", ""}}
	for in, want := range cases {
		if s, o := stageFromText(in); s != want[0] || o != want[1] {
			t.Errorf("%q: got %q/%q", in, s, o)
		}
	}
}

// The views of Dirección read the same folder as «Bases de datos»: invoices
// by period (unknown stays unknown), the pipeline from Oportunidades, the
// workload against Capacidad.md and the internal projects. Nothing is written.
func TestVistasReadTheFolder(t *testing.T) {
	f := newFixture(t)
	dir := databasesFolder(t)
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T2/Ingresos/2026-05-28 F260006 Clara 684€.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T2/Ingresos/2026-06-30 CN260004 Clara rectificativa -84,00€.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T2/Ingresos/2026-06-10 BORRADOR sin emitir Clara 2.850€.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T3/Ingresos/FACT_50 Clara.pdf", "%PDF")
	writeFile(t, dir, "4 · Finanzas/Fechas de documentos.csv", "ruta,fecha,fuente,nota\n4 · Finanzas/Fiscal/2026/T3/Ingresos/FACT_50 Clara.pdf,2026-08-03,documento,\n")
	writeFile(t, dir, "2 · Ventas/Oportunidades/ethiopia.md", "---\nid: opp-1\nestado: Archivada\n---\n\n# Ethiopia\n\nCliente: Ethiopia\n\nEstado en la fuente: Diagnóstico.\n")
	writeFile(t, dir, "2 · Ventas/Oportunidades/nueva.md", "---\nid: opp-2\nestado: Cualificación\nimporte: 1.500 €\nresponsable: Comercial\n---\n\n# Nueva\n")
	writeFile(t, dir, "6 · Equipo/Capacidad.md", "# Capacidad\n\n| Quién | Capacidad | Unidad | Nota |\n|---|---|---|---|\n| Comercial | 4 | tareas a la vez | |\n")
	writeFile(t, dir, "1 · Dirección/Proyectos internos/web.md", "---\nestado: En curso\ninicio: 2026-10-01\nfin: 2026-12-15\nresponsable: Manu\n---\n\n# Nueva web\n\n- [x] Textos\n- [ ] Maquetar\n")
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	before := folderDigest(t, dir)
	ctx := context.Background()
	rd, err := f.s.newDBReader(ctx, f.ws, owner)
	if err != nil {
		t.Fatal(err)
	}

	// Ritmo by month: May 684, June −84 (the draft does not count), July 0,
	// August unknown (an invoice without amount), October 600.
	now := time.Date(2026, 10, 21, 12, 0, 0, 0, madridLoc())
	rt := f.s.ritmo(ctx, f.ws, rd, perMonth, 7, now)
	bs := rt["buckets"].([]ritmoBucket)
	got := map[string]*float64{}
	for _, b := range bs {
		got[b.Key] = b.Invoiced
	}
	if len(bs) != 7 || bs[0].Key != "2026-04" || !bs[6].Current {
		t.Fatalf("buckets: %+v", bs)
	}
	if got["2026-04"] != nil || bs[0].Reason == "" {
		t.Errorf("before the first invoice there is no data, got %v", got["2026-04"])
	}
	for k, want := range map[string]float64{"2026-05": 684, "2026-06": -84, "2026-07": 0, "2026-10": 600} {
		if got[k] == nil || *got[k] != want {
			t.Errorf("%s: got %v, want %v", k, got[k], want)
		}
	}
	if got["2026-08"] != nil || bs[4].NoAmount != 1 {
		t.Errorf("an invoice without amount is unknown, not zero: %+v", bs[4])
	}
	if rt["target"].(*float64) != nil {
		t.Error("no FAC-MES row: no target")
	}

	// Pipeline: the archived one reached Diagnóstico; the proposal folder
	// reached Propuesta; the new one is open in Cualificación with 1.500 €.
	pl := f.s.pipeline(ctx, f.ws, rd)
	stages := pl["stages"].([]pipelineStage)
	if pl["win_rate"].(*float64) != nil {
		t.Error("an archived opportunity is not a lost one: no win rate yet")
	}
	if pl["open"].(int) != 2 || pl["archived"].(int) != 1 || pl["open_no_amount"].(int) != 1 {
		t.Fatalf("pipeline: %+v", pl)
	}
	if v := pl["open_amount"].(*float64); v == nil || *v != 1500 {
		t.Fatalf("open amount: %v", v)
	}
	if stages[0].Reached != 3 || stages[2].Reached != 2 || stages[3].Reached != 1 || stages[3].Conversion == nil || *stages[3].Conversion != 50 {
		t.Fatalf("stages: %+v", stages)
	}

	// Carga: Comercial has capacity 4 and the open opportunity is not a task;
	// agents that live in Multica only are «sin datos».
	cg := f.s.carga(ctx, f.ws, rd)
	var comercial, unassigned *workload
	for _, w := range cg["people"].([]*workload) {
		switch w.Name {
		case "Comercial":
			comercial = w
		case "Sin asignar":
			unassigned = w
		}
	}
	if comercial == nil || comercial.Capacity == nil || *comercial.Capacity != 4 || comercial.Assigned != nil || comercial.Visible {
		t.Fatalf("comercial: %+v", comercial)
	}
	if unassigned == nil || unassigned.Assigned == nil || *unassigned.Assigned < 1 {
		t.Fatalf("the task without owner is unassigned: %+v", unassigned)
	}

	pp := f.s.planificacion(ctx, f.ws, rd)
	ps := pp["projects"].([]internalProject)
	if len(ps) != 1 || ps[0].Title != "Nueva web" || ps[0].Steps != 2 || ps[0].Done != 1 || ps[0].Next != "Maquetar" || ps[0].End != "2026-12-15" || ps[0].Closed {
		t.Fatalf("internal projects: %+v", ps)
	}

	if after := folderDigest(t, dir); after != before {
		t.Fatal("the views changed the folder")
	}
}
