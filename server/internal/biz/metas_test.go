package biz

import (
	"context"
	"strings"
	"testing"
	"time"
)

const metasTxt = "# Metas\n\nTexto de Manu.\n\n| Código | Indicador | Meta | Alerta | Por qué |\n|---|---|---|---|---|\n" +
	"| FIN-RUNWAY | Meses de caja | ≥ 3 meses | 1,5 | Colchón mínimo |\n| DIR-DEC14 | Decisiones viejas | 0 |  | Nada se queda sin decidir |\n| MAR-PUB | Piezas | — |  | En reposo |\n\nNota final.\n"

func TestParseMetasReadsHumanCells(t *testing.T) {
	m := parseMetas(metasTxt)
	if r := m["FIN-RUNWAY"]; r.target == nil || *r.target != 3 || r.alert == nil || *r.alert != 1.5 {
		t.Fatalf("runway: %+v", r)
	}
	if r := m["DIR-DEC14"]; r.target == nil || *r.target != 0 || r.alert != nil {
		t.Fatalf("dec: %+v", r)
	}
	if r, ok := m["MAR-PUB"]; !ok || r.target != nil {
		t.Fatalf("sin meta: %+v %v", r, ok)
	}
}

// A change in the app rewrites only the Meta and Alerta cells of its row;
// a KPI without a row is appended to the table.
func TestWriteMetaRowKeepsText(t *testing.T) {
	dir := targetCopy(t)
	l := mustLayout(dir)
	writeFile(t, dir, l.metasFile(), metasTxt)
	if _, _, err := writeMetaRow(dir, l, map[string]any{"code": "FIN-RUNWAY", "target": 4.0, "alert": nil}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := writeMetaRow(dir, l, map[string]any{"code": "FIN-UNREC", "name": "Movimientos sin conciliar", "target": 0.0, "alert": 10.0}); err != nil {
		t.Fatal(err)
	}
	got := readFile(t, dir, l.metasFile())
	want := strings.Replace(metasTxt, "| FIN-RUNWAY | Meses de caja | ≥ 3 meses | 1,5 | Colchón mínimo |", "| FIN-RUNWAY | Meses de caja | 4 |  | Colchón mínimo |", 1)
	want = strings.Replace(want, "| En reposo |\n", "| En reposo |\n| FIN-UNREC | Movimientos sin conciliar | 0 | 10 |  |\n", 1)
	if got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
}

// With Metas.md the targets come from the folder: kpi.update writes the row,
// a person's edit is read back, and the summary gives a verdict with text.
func TestMetasDriveTheVerdict(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()
	if err := f.s.EnsureBootstrap(ctx, f.ws); err != nil {
		t.Fatal(err)
	}
	f.must(owner, "kpi.update", map[string]any{"code": "DIR-DEC14", "target": 0, "alert": 2})
	f.s.Folder.FlushPending(ctx, f.ws)
	l := mustLayout(dir)
	if txt := readFile(t, dir, l.metasFile()); !strings.Contains(txt, "| DIR-DEC14 | Decisiones abiertas más de 14 días | 0 | 2 |") {
		t.Fatalf("Metas.md:\n%s", txt)
	}
	byCode := func() map[string]KPIValue {
		ks, err := f.s.ComputeKPIs(ctx, f.ws, "")
		if err != nil {
			t.Fatal(err)
		}
		m := map[string]KPIValue{}
		for _, k := range ks {
			m[k.Code] = k
		}
		return m
	}
	if k := byCode()["DIR-DEC14"]; k.Status != "ok" || k.Value == nil || *k.Value != 0 || k.Explanation != "0 frente a la meta ≤ 0: en meta." {
		t.Fatalf("DIR-DEC14: %+v", k)
	}
	// A person removes the target in the file: no verdict.
	txt := readFile(t, dir, l.metasFile())
	writeFile(t, dir, l.metasFile(), strings.Replace(txt, "| 0 | 2 |", "|  |  |", 1))
	if k := byCode()["DIR-DEC14"]; k.Status != "not_configured" || k.Target != nil {
		t.Fatalf("sin meta: %+v", k)
	}
	// Unknown is not zero: nothing registered gives no verdict.
	if k := byCode()["FIN-UNREC"]; k.Status != "no_data" || k.Value != nil {
		t.Fatalf("FIN-UNREC: %+v", k)
	}
}

func TestFiscalOnTimeReadsTheReview(t *testing.T) {
	f := newFixture(t)
	dir := targetCopy(t)
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	ctx := context.Background()
	oct := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	if v, why := f.s.fiscalOnTime(ctx, f.ws, oct); v == nil || *v != 1 || !strings.Contains(why, "T3 2026 sin preparar") {
		t.Fatalf("late: %v %s", v, why)
	}
	if v, why := f.s.fiscalOnTime(ctx, f.ws, time.Date(2026, 10, 3, 12, 0, 0, 0, time.UTC)); v == nil || *v != 0 || !strings.Contains(why, "hasta el 10/10/2026") {
		t.Fatalf("in time: %v %s", v, why)
	}
	writeFile(t, dir, "4 · Finanzas/Fiscal/2026/T3/Revisión 2026-10-05/LEEME.md", "x")
	if v, why := f.s.fiscalOnTime(ctx, f.ws, oct); v == nil || *v != 0 || !strings.Contains(why, "preparado el 05/10/2026, antes del día 10") {
		t.Fatalf("on time: %v %s", v, why)
	}
	if v, why := f.s.fiscalOnTime(ctx, f.ws, time.Date(2027, 1, 12, 9, 0, 0, 0, time.UTC)); v == nil || *v != 1 || !strings.Contains(why, "T4 2026") {
		t.Fatalf("T4: %v %s", v, why)
	}
}
