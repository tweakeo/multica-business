package biz

import (
	"encoding/json"
	"fmt"
	"os"
	"path"
	"path/filepath"
	"strings"
)

// Layout says where each record lives inside the company folder. It is read
// from <carpeta>/.tls/layout.json; without that file the folder keeps the
// original layout (the bundled demo). `"preset": "humana"` selects the
// numbered, human structure (1 · Dirección … 6 · Equipo, Fiscal/AAAA/Tn,
// Registros/*.csv, Buzón/, Archivo/); any other key overrides the preset.
//
// Directory templates use {<área>} for an area folder, {quarter} for the
// fiscal quarter folder and {year}/{q} inside Quarter. An empty entry in Dirs
// means the type has no Markdown file of its own (it lives in a register).
type Layout struct {
	Preset     string            `json:"preset,omitempty"`
	Areas      map[string]string `json:"areas,omitempty"`
	Dirs       map[string]string `json:"dirs,omitempty"`
	Quarter    string            `json:"quarter,omitempty"`
	Package    string            `json:"package,omitempty"`
	Registros  string            `json:"registros,omitempty"`  // "" = no shared registers
	Decisiones string            `json:"decisiones,omitempty"` // "" = one file per decision; else one append-only file
	Archivo    string            `json:"archivo,omitempty"`
	Buzon      string            `json:"buzon,omitempty"`
	Skeleton   []string          `json:"skeleton,omitempty"` // folders created on export
	Skip       []string          `json:"skip,omitempty"`     // folder names never read as records
	Privado    []string          `json:"privado,omitempty"`  // paths people see and agents never get
}

const layoutFile = ".tls/layout.json"

func demoLayout() Layout {
	return Layout{
		Preset: "demo",
		Areas:  map[string]string{"direccion": "Dirección", "ventas": "Ventas", "entrega": "Entrega", "finanzas": "Finanzas", "marca": "Marca", "equipo": "Equipo"},
		Dirs: map[string]string{
			"organization": "{ventas}/Organizaciones", "contact": "{ventas}/Contactos", "opportunity": "{ventas}/Oportunidades",
			"offer": "{ventas}/Ofertas", "service": "{entrega}/Servicios",
			"invoice_draft": "{finanzas}/Borradores", "payment": "{quarter}/Cobros y pagos", "account": "{finanzas}/Bancos",
			"kpi": "{direccion}/KPI", "objective": "{direccion}/Objetivos", "decision": "{direccion}/Decisiones", "routine": "{direccion}/Rutinas",
			"content": "{marca}/Contenidos", "conversation": "{marca}/Conversaciones", "role": "{equipo}/Roles", "document": "Documentos",
		},
		Quarter: "{finanzas}/{year}/T{q}",
		Package: "{quarter}/Paquete gestoría",
		Archivo: "Archivo",
		Skip:    []string{"Paquete gestoría"},
	}
}

func humanLayout() Layout {
	l := demoLayout()
	l.Preset = "humana"
	l.Areas = map[string]string{"direccion": "1 · Dirección", "ventas": "2 · Ventas", "entrega": "3 · Entrega", "finanzas": "4 · Finanzas", "marca": "5 · Marca", "equipo": "6 · Equipo"}
	l.Dirs["organization"] = "{ventas}/Empresas"
	l.Dirs["offer"] = "{ventas}/Productos/Versiones"
	l.Dirs["service"] = "{ventas}/Productos"
	l.Dirs["payment"] = "" // pagos.csv is the register
	l.Dirs["account"] = "{finanzas}/Registros/Bancos"
	l.Dirs["invoice_draft"] = "{finanzas}/Fiscal/Borradores"
	l.Quarter = "{finanzas}/Fiscal/{year}/T{q}"
	l.Package = "{quarter}/Modelos/Paquete gestoría"
	l.Registros = "{finanzas}/Registros"
	l.Decisiones = "{direccion}/Decisiones.md"
	l.Buzon = "Buzón"
	l.Skeleton = []string{"Buzón", "Archivo", "{direccion}/Contratos", "{finanzas}/Gestoría", "{finanzas}/Trámites"}
	for _, a := range []string{"direccion", "ventas", "entrega", "finanzas", "marca", "equipo"} {
		l.Skeleton = append(l.Skeleton, "{"+a+"}/Sistemas", "{"+a+"}/Recursos")
	}
	l.Skip = append(l.Skip, "Buzón", "Sistemas", "Recursos", "Contratos", "Gestoría", "Trámites")
	l.Privado = []string{"{finanzas}/Trámites/Baja IT 2026"}
	return l
}

// LoadLayout reads .tls/layout.json. A missing file is the demo layout; an
// unreadable one is an error so the app never writes to guessed paths.
func LoadLayout(root string) (Layout, error) {
	data, err := os.ReadFile(filepath.Join(root, layoutFile))
	if os.IsNotExist(err) {
		return demoLayout(), nil
	}
	if err != nil {
		return Layout{}, err
	}
	var in Layout
	if err := json.Unmarshal(data, &in); err != nil {
		return Layout{}, fmt.Errorf("%s no válido: %v", layoutFile, err)
	}
	l := demoLayout()
	if in.Preset == "humana" {
		l = humanLayout()
	}
	for k, v := range in.Areas {
		l.Areas[k] = v
	}
	for k, v := range in.Dirs {
		l.Dirs[k] = v
	}
	set := func(dst *string, v string) {
		if v != "" {
			*dst = v
		}
	}
	set(&l.Quarter, in.Quarter)
	set(&l.Package, in.Package)
	set(&l.Registros, in.Registros)
	set(&l.Decisiones, in.Decisiones)
	set(&l.Archivo, in.Archivo)
	set(&l.Buzon, in.Buzon)
	if in.Skeleton != nil {
		l.Skeleton = in.Skeleton
	}
	l.Skip = append(l.Skip, in.Skip...)
	l.Privado = append(l.Privado, in.Privado...)
	return l, nil
}

// expand resolves {área} placeholders. Paths are always slash-separated.
func (l Layout) expand(tpl string) string {
	for code, name := range l.Areas {
		tpl = strings.ReplaceAll(tpl, "{"+code+"}", name)
	}
	return tpl
}

func (l Layout) quarterDir(year, quarter int) string {
	s := strings.NewReplacer("{year}", fmt.Sprint(year), "{q}", fmt.Sprint(quarter)).Replace(l.Quarter)
	return l.expand(s)
}

// dir returns the folder for a type ("" = no file of its own).
func (l Layout) dir(typ string) string {
	return l.expand(l.Dirs[typ])
}

func (l Layout) packageDir(year, quarter int) string {
	return l.expand(strings.ReplaceAll(l.Package, "{quarter}", l.quarterDir(year, quarter)))
}

func (l Layout) registersDir() string { return l.expand(l.Registros) }

func (l Layout) decisionsFile() string { return l.expand(l.Decisiones) }

// skipDir reports folders that never hold records: systems, resources, the
// inbox, gestoría packages and hidden folders (.obsidian, .tls…). Archivo is
// walked, but only explicit records are read there (see scan).
func (l Layout) skipDir(name string) bool {
	if strings.HasPrefix(name, ".") {
		return true
	}
	for _, s := range l.Skip {
		if name == s {
			return true
		}
	}
	return false
}

func (l Layout) archived(rel string) bool {
	return strings.HasPrefix(filepath.ToSlash(rel), l.Archivo+"/")
}

// recordNote is false for index and template notes, which live next to the
// records but are not records (Contactos.md, Plantilla persona.md, Área.md).
func (l Layout) recordNote(rel string) bool {
	rel = filepath.ToSlash(rel)
	base := strings.TrimSuffix(path.Base(rel), ".md")
	return base != path.Base(path.Dir(rel)) && !strings.HasPrefix(base, "Plantilla") && base != "Área" && base != "LEEME" && base != "README"
}

// inferType maps a note without tls_type to its type by folder. Only direct
// children of a record folder count.
func (l Layout) inferType(rel string) string {
	if !l.recordNote(rel) {
		return ""
	}
	parent := path.Dir(filepath.ToSlash(rel))
	for typ := range entityTables {
		if d := l.dir(typ); d != "" && d == parent {
			return typ
		}
	}
	return ""
}

// legacyTypes maps the `tipo:` field of hand-made notes to record types.
var legacyTypes = map[string]string{"empresa": "organization", "organizacion": "organization", "organización": "organization",
	"persona": "contact", "contacto": "contact", "oportunidad": "opportunity"}

// fieldAliases: human field names read as the column they mean. When the app
// writes a file that uses the alias, it keeps the alias instead of adding a
// second key.
var fieldAliases = map[string]string{"nombre": "name", "titulo": "title", "título": "title", "notas": "notes"}
