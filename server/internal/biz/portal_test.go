package biz

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const portalTxt = `# Portal · Demo

Texto libre de Manu.

## Viaje

| Sesión | Estado | Fecha | Resumen para el cliente | Nota interna |
|---|---|---|---|---|
| S1 · Diagnóstico | Hecha | 2026-09-07 | Punto de partida | Cliente con prisa |
| S2 | Kit listo | 2026-10-23 | | Falta vídeo |
| S8 | No incluida | | | Encargo sin S8 |

## Tareas del cliente

- [x] Rellenar la plantilla de recopilación · S2 · vence 2026-10-20
- [ ] Revisar los paneles · S5 · vence 2026-10-01
- [ ] Traer las cuentas, con detalle
`

const incidenciasTxt = `# Incidencias

Nota de Manu que no se toca.

| ID | Fecha | Quién reporta | Email | Tipo | Severidad | Estado | Descripción | Responsable | Resolución |
|---|---|---|---|---|---|---|---|---|---|
| INC-001 | 2026-10-10 | Ana | ana@x.es | Accesos | Grave | En curso | No entra | Manu | Revisando permisos |
| INC-002 | 2026-10-19 | Ana | ana@x.es | Técnica | Leve | Resuelta | Vista rota | Manu | Arreglada |

Línea final.
`

var portalNow = time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)

func portalFixture(t *testing.T, demo bool) (string, Layout) {
	t.Helper()
	dir := t.TempDir()
	l := humanLayout()
	front := "---\nid: x\nestado: En curso\n"
	if demo {
		front += "demo: true\n"
	}
	writeFile(t, dir, "3 · Entrega/Proyectos/demo/Proyecto.md", front+"---\n\n# Demo — Implementación TLS\n\nCliente: [Ejemplo SL](../x.md)\n")
	writeFile(t, dir, "3 · Entrega/Proyectos/demo/Portal.md", portalTxt)
	writeFile(t, dir, "3 · Entrega/Proyectos/demo/Incidencias.md", incidenciasTxt)
	writeFile(t, dir, "3 · Entrega/Proyectos/demo/Materiales/S2 · Estructura/Guion interno.md", "x")
	writeFile(t, dir, "3 · Entrega/Portal Cliente/demo/S1 · Diagnóstico/Resumen.md", "x")
	writeFile(t, dir, "3 · Entrega/Portal Cliente/demo/Bienvenida.md", "x")
	writeFile(t, dir, "3 · Entrega/Recursos/Sesiones/portadas/S3 · Flujos del equipo.png", "x")
	return dir, l
}

func TestPortalInternalView(t *testing.T) {
	root, l := portalFixture(t, true)
	p, err := readPortal(root, l, "demo", false, portalNow)
	if err != nil {
		t.Fatal(err)
	}
	if p.Title != "Demo — Implementación TLS" || p.Client != "Ejemplo SL" || !p.Demo || p.Closed || !p.HasPortal {
		t.Fatalf("header: %+v", p)
	}
	if len(p.Sessions) != 9 || p.Sessions[0].State != "hecha" || p.Sessions[1].State != "preparada" || p.Sessions[1].Name != "Estructura de negocio" ||
		p.Sessions[2].Name != "Flujos del equipo" || p.Sessions[7].State != "no_incluida" {
		t.Fatalf("sessions: %+v", p.Sessions)
	}
	if p.Sessions[0].Note != "Cliente con prisa" || p.Sessions[2].Cover == "" {
		t.Fatalf("internal fields: %+v", p.Sessions[0])
	}
	if len(p.Sessions[1].Kit) != 1 || p.Sessions[1].Kit[0].Client || len(p.Sessions[0].Kit) != 1 || !p.Sessions[0].Kit[0].Client {
		t.Fatalf("kit: %+v / %+v", p.Sessions[0].Kit, p.Sessions[1].Kit)
	}
	if len(p.Documents) != 1 || p.Documents[0].Name != "Bienvenida.md" {
		t.Fatalf("documents: %+v", p.Documents)
	}
	if len(p.Tasks) != 3 || p.Tasks[0].Session != "S2" || p.Tasks[0].Due != "2026-10-20" || p.Tasks[0].Text != "Rellenar la plantilla de recopilación" ||
		!p.Tasks[1].Overdue || p.Tasks[2].Text != "Traer las cuentas, con detalle" {
		t.Fatalf("tasks: %+v", p.Tasks)
	}
	if len(p.Incidents) != 2 || !p.Incidents[0].Open || p.Incidents[1].Open || p.Incidents[0].AgeDays != 11 || p.Incidents[0].Resolution != "Revisando permisos" {
		t.Fatalf("incidents: %+v", p.Incidents)
	}
	pr := p.Progress
	if pr.SessionsTotal != 8 || pr.SessionsDone != 1 || pr.Current != "S2" || pr.TasksDone != 1 || pr.TasksTotal != 3 || pr.IncidentsOpen != 1 || pr.Percent != 12 {
		t.Fatalf("progress: %+v", pr)
	}
	if !strings.Contains(p.Intro, "Texto libre de Manu") {
		t.Fatalf("intro: %q", p.Intro)
	}
}

func TestPortalClientViewHidesInternal(t *testing.T) {
	root, l := portalFixture(t, true)
	p, err := readPortal(root, l, "demo", true, portalNow)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Sessions) != 8 {
		t.Fatalf("S8 not included must be hidden: %d", len(p.Sessions))
	}
	for _, s := range p.Sessions {
		if s.Note != "" || s.Cover != "" {
			t.Fatalf("internal leaked: %+v", s)
		}
		for _, d := range s.Kit {
			if !d.Client {
				t.Fatalf("internal kit leaked: %+v", d)
			}
		}
	}
	for _, in := range p.Incidents {
		if in.Email != "" || in.Owner != "" || in.Resolution != "" {
			t.Fatalf("internal incident fields leaked: %+v", in)
		}
	}
	if p.Intro != "" {
		t.Fatal("free text is internal")
	}
	if _, err := readPortal(root, l, "../x", true, portalNow); err == nil {
		t.Fatal("path escape accepted")
	}
}

func TestAppendIncidentKeepsText(t *testing.T) {
	in := incidentInput{Reporter: "Luis | jefe", Email: "l@x.es", Date: "2026-10-21", Type: "Técnica", Severity: "Media", Description: "Falla\nel panel", Steps: "Abrir"}
	out, id := appendIncident(incidenciasTxt, in)
	if id != "INC-003" {
		t.Fatalf("id %s", id)
	}
	want := "| INC-003 | 2026-10-21 | Luis \\| jefe | l@x.es | Técnica | Media | Recibida | Falla el panel — Pasos: Abrir |  |  |"
	if !strings.Contains(out, want) {
		t.Fatalf("row missing:\n%s", out)
	}
	if strings.Replace(out, want+"\n", "", 1) != incidenciasTxt {
		t.Fatalf("other lines changed:\n%s", out)
	}
	got := parseIncidents(out, portalNow)
	if len(got) != 3 || got[2].Reporter != "Luis | jefe" || !got[2].Open {
		t.Fatalf("%+v", got[2])
	}
	fresh, id := appendIncident("", in)
	if id != "INC-001" || !strings.HasPrefix(fresh, "# Incidencias") || len(parseIncidents(fresh, portalNow)) != 1 {
		t.Fatalf("new file:\n%s", fresh)
	}
}

func TestStaleIncidentsSkipDemo(t *testing.T) {
	root, l := portalFixture(t, true)
	if n, found := staleIncidents(root, l, 3, portalNow); n != 0 || found {
		t.Fatalf("demo counted: %d %v", n, found)
	}
	root, l = portalFixture(t, false)
	if n, found := staleIncidents(root, l, 3, portalNow); n != 1 || !found {
		t.Fatalf("real: %d %v", n, found)
	}
	list := listPortals(root, l, portalNow)
	if len(list) != 1 || list[0].Sessions != nil || list[0].Progress.SessionsDone != 1 {
		t.Fatalf("list: %+v", list)
	}
	_ = os.Remove(filepath.Join(root, "3 · Entrega/Proyectos/demo/Portal.md"))
	p, _ := readPortal(root, l, "demo", false, portalNow)
	if p.HasPortal || len(p.Sessions) != 9 || p.Progress.Current != "S1" {
		t.Fatalf("no portal: %+v", p.Progress)
	}
}
