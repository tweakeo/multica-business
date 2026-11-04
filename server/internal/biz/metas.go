package biz

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"golang.org/x/text/unicode/norm"
)

// Metas.md (human layout) holds the target of every KPI in one table a
// person reads and edits: Código · Indicador · Meta · Alerta · Por qué. It is
// the company's configuration: when it exists, the targets come from it, and
// a change made in the app rewrites only the Meta and Alerta cells of its
// row. An empty Meta cell means "sin meta" (value without a verdict).

const metasHeader = "# Metas\n\n> Metas de los indicadores. Cámbialas aquí: la app las lee cada vez que calcula el resumen. " +
	"Meta vacía = sin meta (se ve el valor, sin veredicto). Alerta = a partir de qué valor deja de ser «por debajo de la meta» y pasa a alerta.\n\n" +
	"| Código | Indicador | Meta | Alerta | Por qué |\n|---|---|---|---|---|\n"

type kpiTarget struct{ target, alert *float64 }

func tableCells(line string) []string {
	t := strings.TrimSpace(line)
	if !strings.HasPrefix(t, "|") {
		return nil
	}
	t = strings.TrimSuffix(strings.TrimPrefix(t, "|"), "|")
	cells := strings.Split(t, "|")
	for i := range cells {
		cells[i] = strings.TrimSpace(cells[i])
	}
	return cells
}

func headerKey(s string) string {
	s = strings.ToLower(norm.NFC.String(strings.TrimSpace(s)))
	return strings.NewReplacer("ó", "o", "é", "e", "í", "i", "á", "a", "ú", "u").Replace(s)
}

var numberRe = regexp.MustCompile(`-?\d+(?:[.,]\d+)?`)

// metaNumber reads "3", "3,5", "≥ 3 meses" or "0 €". Empty, "—" or text
// without a number is no value.
func metaNumber(s string) *float64 {
	m := numberRe.FindString(s)
	if m == "" {
		return nil
	}
	v, err := strconv.ParseFloat(strings.ReplaceAll(m, ",", "."), 64)
	if err != nil {
		return nil
	}
	return &v
}

func fmtMeta(v *float64) string {
	if v == nil {
		return ""
	}
	return strings.ReplaceAll(strconv.FormatFloat(*v, 'f', -1, 64), ".", ",")
}

type metasTable struct {
	lines              []string
	code, meta, alerta int
	header, last       int // line of the header row and of the last table row
}

func parseMetasTable(data string) metasTable {
	t := metasTable{lines: strings.Split(data, "\n"), header: -1, last: -1, code: -1, meta: -1, alerta: -1}
	for i, ln := range t.lines {
		cells := tableCells(ln)
		if cells == nil {
			if t.header >= 0 && t.last >= 0 {
				break
			}
			continue
		}
		if t.header < 0 {
			for j, c := range cells {
				switch headerKey(c) {
				case "codigo":
					t.code = j
				case "meta":
					t.meta = j
				case "alerta":
					t.alerta = j
				}
			}
			if t.code >= 0 && t.meta >= 0 {
				t.header, t.last = i, i
			}
			continue
		}
		t.last = i
	}
	return t
}

// parseMetas maps each KPI code of the table to its target and alert.
func parseMetas(data string) map[string]kpiTarget {
	t := parseMetasTable(data)
	out := map[string]kpiTarget{}
	if t.header < 0 {
		return out
	}
	for _, ln := range t.lines[t.header+1 : t.last+1] {
		cells := tableCells(ln)
		if len(cells) <= t.code || len(cells) <= t.meta {
			continue
		}
		code := strings.Trim(cells[t.code], "`* ")
		if code == "" || strings.Trim(code, "-: ") == "" {
			continue
		}
		k := kpiTarget{target: metaNumber(cells[t.meta])}
		if t.alerta >= 0 && len(cells) > t.alerta {
			k.alert = metaNumber(cells[t.alerta])
		}
		out[code] = k
	}
	return out
}

// kpiTargets reads Metas.md. ok is false when the company has no such file
// (demo layout, no folder, file not created yet): the database targets rule.
func (s *Service) kpiTargets(ctx context.Context, ws string) (map[string]kpiTarget, bool) {
	root := s.Folder.Root(ctx, s.Pool, ws)
	if root == "" {
		return nil, false
	}
	l, err := LoadLayout(root)
	if err != nil || l.Metas == "" {
		return nil, false
	}
	data, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(l.metasFile())))
	if err != nil {
		return nil, false
	}
	return parseMetas(string(data)), true
}

func applyTargets(k *KPIValue, metas map[string]kpiTarget, ok bool) {
	if !ok {
		return
	}
	t := metas[k.Code]
	k.Target, k.Alert = t.target, t.alert
}

// writeMetaRow sets the Meta and Alerta cells of the KPI's row (adding the
// row, or the file, when missing). Every other cell and line is left as the
// person wrote it.
func writeMetaRow(root string, l Layout, m map[string]any) (string, string, error) {
	rel := l.metasFile()
	target := filepath.Join(root, filepath.FromSlash(rel))
	old, err := os.ReadFile(target)
	if os.IsNotExist(err) {
		old, err = []byte(metasHeader), nil
	}
	if err != nil {
		return "", "", err
	}
	code := str(m["code"])
	tv, av := metaNumber(fmt.Sprint(m["target"])), metaNumber(fmt.Sprint(m["alert"]))
	if m["target"] == nil {
		tv = nil
	}
	if m["alert"] == nil {
		av = nil
	}
	t := parseMetasTable(string(old))
	if t.header < 0 {
		// No table a person made: append ours below their text.
		old = []byte(strings.TrimRight(string(old), "\n") + "\n\n" + metasHeader[strings.Index(metasHeader, "| Código"):])
		t = parseMetasTable(string(old))
	}
	row := ""
	for i := t.header + 1; i <= t.last; i++ {
		cells := tableCells(t.lines[i])
		if len(cells) > t.code && strings.Trim(cells[t.code], "`* ") == code {
			cells[t.meta] = fmtMeta(tv)
			if t.alerta >= 0 && len(cells) > t.alerta {
				cells[t.alerta] = fmtMeta(av)
			}
			row = "| " + strings.Join(cells, " | ") + " |"
			t.lines[i] = row
		}
	}
	if row == "" {
		n := len(tableCells(t.lines[t.header]))
		cells := make([]string, n)
		cells[t.code] = code
		cells[t.meta] = fmtMeta(tv)
		if t.alerta >= 0 {
			cells[t.alerta] = fmtMeta(av)
		}
		for j, c := range tableCells(t.lines[t.header]) {
			if headerKey(c) == "indicador" {
				cells[j] = str(m["name"])
			}
		}
		row = "| " + strings.Join(cells, " | ") + " |"
		t.lines = append(t.lines[:t.last+1], append([]string{row}, t.lines[t.last+1:]...)...)
	}
	text := strings.Join(t.lines, "\n")
	if err := atomicWrite(target, []byte(text)); err != nil {
		return "", "", err
	}
	return rel + "#" + code, hashBytes([]byte(row)), nil
}

// --- Fiscal quarter --------------------------------------------------------

var reviewDirRe = regexp.MustCompile(`(?i)^revisi[oó]n (\d{4}-\d{2}-\d{2})`)

// fiscalOnTime judges the last closed quarter: it must be prepared by day 10
// of its filing month. Prepared = the period is past "open" in TLS, or the
// quarter folder holds a dated review ("Revisión AAAA-MM-DD") or the gestoría
// package. Value 0 = on time (or still in time), 1 = late.
func (s *Service) fiscalOnTime(ctx context.Context, ws string, now time.Time) (*float64, string) {
	y, q := quarterOf(now)
	q--
	if q == 0 {
		y, q = y-1, 4
	}
	start := time.Date(now.Year(), time.Month((int(now.Month())-1)/3*3+1), 1, 0, 0, 0, 0, time.UTC)
	deadline := start.AddDate(0, 0, 9) // day 10
	name := fmt.Sprintf("T%d %d", q, y)

	var prepared *time.Time
	var how string
	var status string
	var updated time.Time
	if err := s.Pool.QueryRow(ctx, `SELECT status, updated_at FROM biz_period WHERE workspace_id=$1 AND year=$2 AND quarter=$3`, ws, y, q).Scan(&status, &updated); err == nil && status != "open" {
		d := updated.In(madridLoc())
		prepared, how = &d, "periodo en TLS"
	}
	if root := s.Folder.Root(ctx, s.Pool, ws); root != "" {
		if l, err := LoadLayout(root); err == nil {
			dir := filepath.Join(root, filepath.FromSlash(l.quarterDir(y, q)))
			if entries, err := os.ReadDir(dir); err == nil {
				for _, e := range entries {
					m := reviewDirRe.FindStringSubmatch(norm.NFC.String(e.Name()))
					if m == nil {
						continue
					}
					if d, err := time.Parse("2006-01-02", m[1]); err == nil && (prepared == nil || d.Before(*prepared)) {
						prepared, how = &d, "«"+norm.NFC.String(e.Name())+"» en la carpeta"
					}
				}
			}
			if st, err := os.Stat(filepath.Join(root, filepath.FromSlash(l.packageDir(y, q)))); err == nil && prepared == nil {
				d := st.ModTime().In(madridLoc())
				prepared, how = &d, "paquete de gestoría en la carpeta"
			}
		}
	}
	day := func(t time.Time) string { return t.Format("02/01/2006") }
	switch {
	case prepared != nil && !dateOnly(*prepared).After(deadline):
		return pf(0), fmt.Sprintf("%s preparado el %s, antes del día 10 (%s).", name, day(*prepared), how)
	case prepared != nil:
		return pf(1), fmt.Sprintf("%s preparado el %s, después del día 10 (%s).", name, day(*prepared), how)
	case !dateOnly(now).After(deadline):
		return pf(0), fmt.Sprintf("%s aún sin preparar; hay tiempo hasta el %s.", name, day(deadline))
	default:
		return pf(1), fmt.Sprintf("%s sin preparar y ya pasó el día 10 (%s).", name, day(deadline))
	}
}

func madridLoc() *time.Location {
	if loc, err := time.LoadLocation("Europe/Madrid"); err == nil {
		return loc
	}
	return time.UTC
}

func dateOnly(t time.Time) time.Time { return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC) }
