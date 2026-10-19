package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"sort"
	"time"
)

// KPIValue is a computed indicator. Value is nil when unknown; "no_data",
// "not_configured" and "stale" are states distinct from ok/warning/alert.
type KPIValue struct {
	Code        string   `json:"code"`
	Area        string   `json:"area"`
	Name        string   `json:"name"`
	Unit        string   `json:"unit"`
	Formula     string   `json:"formula"`
	Direction   string   `json:"direction"`
	Period      string   `json:"period"`
	Value       *float64 `json:"value"`
	Target      *float64 `json:"target"`
	Alert       *float64 `json:"alert"`
	Expected    *float64 `json:"expected,omitempty"`
	Status      string   `json:"status"`
	Explanation string   `json:"explanation"`
	Coverage    string   `json:"coverage,omitempty"`
	Source      string   `json:"source"`
	Enabled     bool     `json:"enabled"`
}

func pf(v float64) *float64 { return &v }

func monthBounds() (time.Time, time.Time, float64) {
	now := madridNow()
	start := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	end := start.AddDate(0, 1, 0)
	elapsed := float64(now.Day()) / float64(end.AddDate(0, 0, -1).Day())
	return start, end, elapsed
}

// ComputeKPIs evaluates the enabled KPI definitions of a workspace.
func (s *Service) ComputeKPIs(ctx context.Context, ws, area string) ([]KPIValue, error) {
	rows, err := s.Pool.Query(ctx, `SELECT code, area, name, unit, formula, direction, period, target::float8, alert::float8, enabled FROM biz_kpi
		WHERE workspace_id=$1 AND ($2='' OR area=$2) ORDER BY array_position(ARRAY['direccion','ventas','entrega','finanzas','marca','equipo'], area), code`, ws, area)
	if err != nil {
		return nil, err
	}
	var defs []KPIValue
	for rows.Next() {
		var k KPIValue
		if err := rows.Scan(&k.Code, &k.Area, &k.Name, &k.Unit, &k.Formula, &k.Direction, &k.Period, &k.Target, &k.Alert, &k.Enabled); err != nil {
			rows.Close()
			return nil, err
		}
		defs = append(defs, k)
	}
	rows.Close()
	for i := range defs {
		s.evalKPI(ctx, ws, &defs[i])
	}
	return defs, nil
}

func (s *Service) scalar(ctx context.Context, sql string, args ...any) *float64 {
	var v *float64
	if err := s.Pool.QueryRow(ctx, sql, args...).Scan(&v); err != nil {
		return nil
	}
	return v
}

func (s *Service) evalKPI(ctx context.Context, ws string, k *KPIValue) {
	if !k.Enabled {
		k.Status = "disabled"
		return
	}
	mStart, mEnd, elapsed := monthBounds()
	cumulative := false
	switch k.Code {
	case "DIR-OBJ":
		k.Value, k.Explanation = s.objectivesOnTrack(ctx, ws)
		k.Source = "/empresa/direccion?tab=objetivos"
	case "DIR-DEC":
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM biz_decision WHERE workspace_id=$1 AND status='open'`, ws)
		k.Source = "/empresa/direccion?tab=decisiones"
	case "DIR-APR":
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM biz_approval WHERE workspace_id=$1 AND status='pending'`, ws)
		k.Source = "/empresa?tab=aprobaciones"
	case "VEN-PIPE":
		k.Value = s.scalar(ctx, `SELECT coalesce(sum(value_minor),0)/100.0 FROM biz_opportunity WHERE workspace_id=$1 AND archived_at IS NULL AND stage IN ('entrada','cualificacion','diagnostico','propuesta','negociacion','aceptada')`, ws)
		k.Source = "/empresa/ventas?tab=gestion"
	case "VEN-FCST":
		k.Value = s.scalar(ctx, `SELECT coalesce(sum(value_minor*probability/100.0),0)/100.0 FROM biz_opportunity WHERE workspace_id=$1 AND archived_at IS NULL AND stage IN ('entrada','cualificacion','diagnostico','propuesta','negociacion','aceptada')`, ws)
		k.Explanation = "Previsión: no es venta aceptada ni cobro."
		k.Source = "/empresa/ventas?tab=analisis"
	case "VEN-WON":
		cumulative = true
		k.Value = s.scalar(ctx, `SELECT coalesce(sum(value_minor),0)/100.0 FROM biz_opportunity WHERE workspace_id=$1 AND stage='ganada' AND won_at >= $2 AND won_at < $3`, ws, mStart, mEnd)
		k.Source = "/empresa/ventas?tab=gestion&stage=ganada"
	case "VEN-CONV":
		var with, accepted float64
		_ = s.Pool.QueryRow(ctx, `SELECT count(*) FILTER (WHERE proposal IS NOT NULL), count(*) FILTER (WHERE stage IN ('aceptada','ganada'))
			FROM biz_opportunity WHERE workspace_id=$1 AND updated_at > now()-interval '90 days'`, ws).Scan(&with, &accepted)
		if with > 0 {
			k.Value = pf(math.Round(accepted / with * 100))
		}
		k.Coverage = fmt.Sprintf("%.0f propuestas en 90 días", with)
		k.Source = "/empresa/ventas?tab=analisis"
	case "VEN-STALE":
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM biz_opportunity WHERE workspace_id=$1 AND archived_at IS NULL AND stage IN ('entrada','cualificacion','diagnostico','propuesta','negociacion')
			AND coalesce(last_contact_at, created_at) < now()-interval '14 days'`, ws)
		k.Source = "/empresa/ventas?tab=gestion&filter=stale"
	case "ENT-ONTIME":
		var done, ontime float64
		_ = s.Pool.QueryRow(ctx, `SELECT count(*), count(*) FILTER (WHERE i.updated_at::date <= i.due_date) FROM issue i JOIN biz_project_link l ON l.project_id=i.project_id
			JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status WHERE i.workspace_id=$1 AND st.category='done' AND i.due_date IS NOT NULL
			AND i.updated_at > now()-interval '30 days'`, ws).Scan(&done, &ontime)
		if done > 0 {
			k.Value = pf(math.Round(ontime / done * 100))
		}
		k.Coverage = fmt.Sprintf("%.0f tareas terminadas con vencimiento (fecha de cierre aproximada por última actualización)", done)
		k.Source = "/empresa/entrega?tab=analisis"
	case "ENT-OVERDUE":
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM issue i JOIN biz_project_link l ON l.project_id=i.project_id JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status
			WHERE i.workspace_id=$1 AND st.category NOT IN ('done','closed') AND i.due_date < $2`, ws, today())
		k.Source = "/empresa/entrega?tab=gestion&filter=overdue"
	case "ENT-ACTIVE":
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM project p JOIN biz_project_link l ON l.project_id=p.id WHERE p.workspace_id=$1 AND p.status IN ('planned','in_progress')`, ws)
		k.Source = "/empresa/entrega?tab=gestion"
	case "FIN-CASH":
		k.Value, k.Coverage = s.cash(ctx, ws)
		k.Source = "/empresa/finanzas?tab=gestion&view=bancos"
	case "FIN-RUNWAY":
		k.Value, k.Explanation = s.runway(ctx, ws)
		k.Source = "/empresa/finanzas?tab=analisis"
	case "FIN-AR":
		k.Value = s.scalar(ctx, `SELECT coalesce(sum(total_minor-paid_minor),0)/100.0 FROM biz_invoice WHERE workspace_id=$1 AND direction='issued' AND status IN ('issued','partially_paid') AND due_date < $2`, ws, today())
		k.Source = "/empresa/finanzas?tab=gestion&view=cobros"
	case "FIN-UNREC":
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM biz_bank_movement WHERE workspace_id=$1 AND status IN ('unreconciled','proposed')`, ws)
		k.Source = "/empresa/finanzas?tab=gestion&view=bancos"
	case "FIN-MARGIN":
		var inc, exp float64
		_ = s.Pool.QueryRow(ctx, `SELECT coalesce(sum(base_minor) FILTER (WHERE direction='issued'),0), coalesce(sum(base_minor) FILTER (WHERE direction='received' AND nature='operating'),0)
			FROM biz_invoice WHERE workspace_id=$1 AND status NOT IN ('draft','void') AND issue_date >= $2 AND issue_date < $3`, ws, mStart, mEnd).Scan(&inc, &exp)
		if inc > 0 {
			k.Value = pf(math.Round((inc - exp) / inc * 100))
		}
		k.Explanation = fmt.Sprintf("Devengo del mes: ingresos %s, gastos %s. No es resultado de caja.", eur(int64(inc)), eur(int64(exp)))
		k.Source = "/empresa/finanzas?tab=analisis"
	case "MAR-QCONV":
		cumulative = true
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM biz_conversation WHERE workspace_id=$1 AND qualified AND updated_at >= $2 AND updated_at < $3`, ws, mStart, mEnd)
		k.Source = "/empresa/marca?tab=gestion&view=conversaciones"
	case "MAR-PUB":
		cumulative = true
		k.Value = s.scalar(ctx, `SELECT count(*)::float8 FROM biz_content WHERE workspace_id=$1 AND status='publicado' AND published_at >= $2 AND published_at < $3`, ws, mStart, mEnd)
		k.Source = "/empresa/marca?tab=gestion"
	case "EQU-HEALTH":
		var total, healthy float64
		_ = s.Pool.QueryRow(ctx, `SELECT count(*), count(*) FILTER (WHERE coalesce(last.status,'none') <> 'failed') FROM biz_agent g
			LEFT JOIN LATERAL (SELECT status FROM agent_task_queue t WHERE t.agent_id=g.agent_id AND t.status IN ('completed','failed') ORDER BY t.created_at DESC LIMIT 1) last ON true
			WHERE g.workspace_id=$1`, ws).Scan(&total, &healthy)
		if total > 0 {
			k.Value = pf(math.Round(healthy / total * 100))
		}
		k.Source = "/empresa/equipo?tab=gestion"
	case "EQU-COST":
		var ticks, tokens, runs, reported float64
		_ = s.Pool.QueryRow(ctx, `SELECT coalesce(sum(u.cost_usd_ticks),0), coalesce(sum(u.input_tokens+u.output_tokens),0), count(DISTINCT u.task_id), count(u.cost_usd_ticks)
			FROM task_usage u JOIN agent_task_queue t ON t.id=u.task_id JOIN biz_agent g ON g.agent_id=t.agent_id
			WHERE g.workspace_id=$1 AND u.created_at >= $2`, ws, mStart).Scan(&ticks, &tokens, &runs, &reported)
		if reported > 0 {
			k.Value = pf(math.Round(ticks/1e10*100) / 100)
		}
		k.Coverage = fmt.Sprintf("%.0f ejecuciones · %.0f tokens. El proveedor informa coste en %.0f registros.", runs, tokens, reported)
		k.Source = "/empresa/equipo?tab=analisis"
	case "EQU-ROLES":
		var total, filled float64
		_ = s.Pool.QueryRow(ctx, `SELECT count(*), count(*) FILTER (WHERE occupant_id IS NOT NULL) FROM biz_role WHERE workspace_id=$1 AND archived_at IS NULL`, ws).Scan(&total, &filled)
		if total > 0 {
			k.Value = pf(math.Round(filled / total * 100))
		}
		k.Source = "/empresa/equipo?tab=sistemas"
	default:
		k.Status = "not_configured"
		k.Explanation = "Sin fórmula implementada para este código."
		return
	}
	if k.Value == nil {
		k.Status = "no_data"
		if k.Explanation == "" {
			k.Explanation = "Sin datos suficientes para calcularlo."
		}
		return
	}
	if k.Target == nil {
		k.Status = "not_configured"
		if k.Explanation == "" {
			k.Explanation = "Sin meta configurada: se muestra el valor sin veredicto."
		}
		return
	}
	target, alert := *k.Target, k.Alert
	if cumulative {
		exp := math.Round(target*elapsed*100) / 100
		k.Expected = &exp
		k.Explanation = fmt.Sprintf("Acumulado del mes frente a trayectoria lineal declarada (%.0f%% del mes → %.2f esperado).", elapsed*100, exp)
		target = exp
		if alert != nil {
			a := *alert * elapsed
			alert = &a
		}
	}
	v := *k.Value
	switch k.Direction {
	case "down":
		switch {
		case v <= target:
			k.Status = "ok"
		case alert != nil && v >= *alert:
			k.Status = "alert"
		default:
			k.Status = "warning"
		}
	case "range":
		k.Status = "ok"
	default:
		switch {
		case v >= target:
			k.Status = "ok"
		case alert != nil && v <= *alert:
			k.Status = "alert"
		default:
			k.Status = "warning"
		}
	}
}

// cash uses the bank-reported running balance when available, otherwise the
// declared opening balance plus imported movements. Unknown stays unknown.
func (s *Service) cash(ctx context.Context, ws string) (*float64, string) {
	rows, err := s.Pool.Query(ctx, `SELECT a.name, a.opening_balance_minor, a.opening_on,
		(SELECT balance_after_minor FROM biz_bank_movement m WHERE m.account_id=a.id AND balance_after_minor IS NOT NULL ORDER BY booked_on DESC, created_at DESC LIMIT 1),
		(SELECT coalesce(sum(amount_minor),0) FROM biz_bank_movement m WHERE m.account_id=a.id AND (a.opening_on IS NULL OR m.booked_on > a.opening_on))
		FROM biz_bank_account a WHERE a.workspace_id=$1 AND a.archived_at IS NULL`, ws)
	if err != nil {
		return nil, ""
	}
	defer rows.Close()
	var total int64
	accounts, unknown := 0, []string{}
	for rows.Next() {
		var name string
		var opening, last *int64
		var openingOn *time.Time
		var sum int64
		_ = rows.Scan(&name, &opening, &openingOn, &last, &sum)
		accounts++
		switch {
		case last != nil:
			total += *last
		case opening != nil:
			total += *opening + sum
		default:
			unknown = append(unknown, name)
		}
	}
	if accounts == 0 || len(unknown) == accounts {
		return nil, "Sin saldo conocido: importa un extracto con saldo o declara el saldo inicial."
	}
	cov := fmt.Sprintf("%d cuentas", accounts)
	if len(unknown) > 0 {
		cov += fmt.Sprintf(" · saldo desconocido en: %v (no se suma como cero)", unknown)
	}
	v := float64(total) / 100
	return &v, cov
}

// runway = available cash / normalised fixed monthly outflow (last 3 full
// months of operating expenses, payroll, taxes and loans).
func (s *Service) runway(ctx context.Context, ws string) (*float64, string) {
	cash, _ := s.cash(ctx, ws)
	if cash == nil {
		return nil, "Caja desconocida: no se calcula runway."
	}
	now := madridNow()
	end := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	start := end.AddDate(0, -3, 0)
	var out float64
	var months int
	_ = s.Pool.QueryRow(ctx, `SELECT coalesce(-sum(amount_minor),0)/100.0, count(DISTINCT date_trunc('month', booked_on)) FROM biz_bank_movement
		WHERE workspace_id=$1 AND amount_minor < 0 AND nature IN ('operating_expense','payroll','tax','loan') AND booked_on >= $2 AND booked_on < $3`, ws, start, end).Scan(&out, &months)
	if months == 0 || out <= 0 {
		return nil, "Sin meses completos de gasto importados: el runway no se calcula."
	}
	monthly := out / float64(months)
	v := math.Round(*cash/monthly*10) / 10
	return &v, fmt.Sprintf("Caja %s / salida mensual normalizada %s (media de %d meses completos).", eur(int64(*cash*100)), eur(int64(monthly*100)), months)
}

func (s *Service) objectivesOnTrack(ctx context.Context, ws string) (*float64, string) {
	now := madridNow()
	y, q := quarterOf(now)
	period := fmt.Sprintf("%d-T%d", y, q)
	rows, err := s.Pool.Query(ctx, `SELECT kpi_code, target::float8 FROM biz_objective WHERE workspace_id=$1 AND period=$2 AND status='active' AND kpi_code<>''`, ws, period)
	if err != nil {
		return nil, ""
	}
	type o struct {
		code   string
		target *float64
	}
	var objs []o
	for rows.Next() {
		var x o
		_ = rows.Scan(&x.code, &x.target)
		objs = append(objs, x)
	}
	rows.Close()
	if len(objs) == 0 {
		return nil, "Sin objetivos activos con KPI en " + period
	}
	onTrack, measured := 0, 0
	for _, x := range objs {
		k := KPIValue{Code: x.code, Enabled: true}
		_ = s.Pool.QueryRow(ctx, `SELECT area, direction, target::float8, alert::float8 FROM biz_kpi WHERE workspace_id=$1 AND code=$2`, ws, x.code).Scan(&k.Area, &k.Direction, &k.Target, &k.Alert)
		if x.target != nil {
			k.Target = x.target
		}
		s.evalKPI(ctx, ws, &k)
		if k.Status == "no_data" || k.Status == "not_configured" {
			continue
		}
		measured++
		if k.Status == "ok" {
			onTrack++
		}
	}
	if measured == 0 {
		return nil, "Los KPI de los objetivos aún no tienen datos"
	}
	v := math.Round(float64(onTrack) / float64(measured) * 100)
	return &v, fmt.Sprintf("%d de %d objetivos medibles en trayectoria (%s).", onTrack, measured, period)
}

// --- Exceptions ----------------------------------------------------------

type Exception struct {
	Area           string         `json:"area"`
	Kind           string         `json:"kind"`
	Severity       string         `json:"severity"`
	Title          string         `json:"title"`
	What           string         `json:"what"`
	Why            string         `json:"why"`
	Action         string         `json:"action"`
	Consequence    string         `json:"consequence"`
	Recommendation string         `json:"recommendation"`
	EntityType     string         `json:"entity_type"`
	EntityID       string         `json:"entity_id"`
	Capability     string         `json:"capability"`
	Factors        map[string]int `json:"factors"`
	Score          int            `json:"score"`
}

func (s *Service) Exceptions(ctx context.Context, ws, area string) ([]Exception, error) {
	var out []Exception
	add := func(e Exception) {
		if area != "" && e.Area != area {
			return
		}
		w := map[string]int{"alta": 3, "media": 2, "baja": 1}[e.Severity]
		e.Score = w*10 + e.Factors["urgencia"]*3 + e.Factors["impacto"]*2 + e.Factors["riesgo"]
		out = append(out, e)
	}
	q := func(sql string, args []any, fn func(vals []any)) {
		rows, err := s.Pool.Query(ctx, sql, args...)
		if err != nil {
			s.Log.Warn("biz exceptions query failed", "error", err)
			return
		}
		defer rows.Close()
		for rows.Next() {
			vals, err := rows.Values()
			if err == nil {
				fn(vals)
			}
		}
	}
	ws1 := []any{ws}
	t := today()

	q(`SELECT id::text, title, approval.capability, area, requested_by_type, extract(day from now()-created_at)::int FROM biz_approval approval WHERE workspace_id=$1 AND status='pending'`, ws1, func(v []any) {
		add(Exception{Area: str(v[3]), Kind: "approval_pending", Severity: "alta", Title: "Aprobación pendiente: " + str(v[1]),
			What: "Un " + map[string]string{"agent": "agente", "member": "miembro"}[str(v[4])] + " pide ejecutar una acción sensible.", Why: "Nada sale de la empresa sin tu visto bueno.",
			Action: "Revisa campos, destinatario e importes y aprueba o rechaza con motivo.", Consequence: "El trabajo queda detenido.", Recommendation: "Decide hoy.",
			EntityType: "approval", EntityID: str(v[0]), Capability: str(v[2]), Factors: map[string]int{"urgencia": 3, "impacto": 2, "riesgo": 2, "antiguedad_dias": int(num(v[5]))}})
	})
	q(`SELECT id::text, title, stage, extract(day from now()-coalesce(last_contact_at, created_at))::int, value_minor FROM biz_opportunity WHERE workspace_id=$1 AND archived_at IS NULL
		AND stage IN ('entrada','cualificacion','diagnostico','propuesta','negociacion') AND coalesce(last_contact_at, created_at) < now()-interval '14 days'`, ws1, func(v []any) {
		add(Exception{Area: "ventas", Kind: "stale_opportunity", Severity: "media", Title: "Oportunidad quieta: " + str(v[1]),
			What: fmt.Sprintf("%d días sin contacto en etapa %s.", int(num(v[3])), str(v[2])), Why: "Una oportunidad sin toque se enfría y la previsión deja de ser fiable.",
			Action: "Registra un toque o márcala como perdida/pausada con motivo.", Consequence: fmt.Sprintf("Riesgo de perder %s.", eur(int64(num(v[4])))),
			Recommendation: "Pide al agente Comercial un borrador de seguimiento.", EntityType: "opportunity", EntityID: str(v[0]), Capability: "VEN-09",
			Factors: map[string]int{"urgencia": 2, "impacto": 2, "riesgo": 1, "antiguedad_dias": int(num(v[3]))}})
	})
	q(`SELECT id::text, title, next_action, (now()::date - next_action_on)::int FROM biz_opportunity WHERE workspace_id=$1 AND archived_at IS NULL AND next_action_on < $2
		AND stage NOT IN ('ganada','perdida','pausada')`, []any{ws, t}, func(v []any) {
		add(Exception{Area: "ventas", Kind: "next_action_due", Severity: "media", Title: "Próxima acción vencida: " + str(v[1]), What: str(v[2]) + fmt.Sprintf(" (vencida hace %d días)", int(num(v[3]))),
			Why: "El compromiso con el interesado tiene fecha.", Action: "Haz la acción o reprograma con motivo.", Consequence: "El interesado percibe abandono.",
			Recommendation: "Resuélvela antes de abrir trabajo nuevo.", EntityType: "opportunity", EntityID: str(v[0]), Capability: "VEN-08", Factors: map[string]int{"urgencia": 3, "impacto": 1, "riesgo": 1}})
	})
	q(`SELECT o.id::text, o.title FROM biz_opportunity o WHERE o.workspace_id=$1 AND o.stage='aceptada' AND NOT EXISTS
		(SELECT 1 FROM biz_invoice i WHERE i.opportunity_id=o.id AND i.status NOT IN ('draft','void'))`, ws1, func(v []any) {
		add(Exception{Area: "finanzas", Kind: "accepted_not_invoiced", Severity: "alta", Title: "Aceptada sin factura emitida: " + str(v[1]),
			What: "La propuesta está aceptada y la factura sigue en borrador.", Why: "Sin factura no hay cobro y sin cobro no arranca el proyecto (política).",
			Action: "Revisa el borrador y emítelo.", Consequence: "El cliente espera y el proyecto no empieza.", Recommendation: "Emitir hoy.",
			EntityType: "opportunity", EntityID: str(v[0]), Capability: "FIN-02", Factors: map[string]int{"urgencia": 3, "impacto": 3, "riesgo": 1}})
	})
	q(`SELECT i.id::text, coalesce(i.number,''), coalesce(o.name,''), i.total_minor-i.paid_minor, ($2::date - i.due_date)::int FROM biz_invoice i LEFT JOIN biz_organization o ON o.id=i.organization_id
		WHERE i.workspace_id=$1 AND i.direction='issued' AND i.status IN ('issued','partially_paid') AND i.due_date < $2`, []any{ws, t}, func(v []any) {
		days := int(num(v[4]))
		sev := "media"
		if days > 15 {
			sev = "alta"
		}
		add(Exception{Area: "finanzas", Kind: "overdue_invoice", Severity: sev, Title: fmt.Sprintf("Cobro vencido %s · %s", str(v[1]), str(v[2])),
			What: fmt.Sprintf("%s pendientes, vencida hace %d días.", eur(int64(num(v[3]))), days), Why: "Afecta a la caja y al runway.",
			Action: "Revisa si hay un movimiento sin conciliar; si no, envía recordatorio (escalonado).", Consequence: "Más días de caja comprometida.",
			Recommendation: "Pide al agente Financiero el recordatorio; se enviará tras tu aprobación.", EntityType: "invoice", EntityID: str(v[0]), Capability: "FIN-04",
			Factors: map[string]int{"urgencia": 2, "impacto": 3, "riesgo": 2, "dias_vencida": days}})
	})
	q(`SELECT m.id::text, m.description, m.amount_minor, coalesce(i.number,''), m.match_reason FROM biz_bank_movement m LEFT JOIN biz_invoice i ON i.id=m.invoice_id
		WHERE m.workspace_id=$1 AND m.status='proposed'`, ws1, func(v []any) {
		add(Exception{Area: "finanzas", Kind: "match_proposed", Severity: "media", Title: "Conciliación propuesta: " + str(v[1]),
			What: fmt.Sprintf("%s con factura %s. %s.", eur(int64(num(v[2]))), str(v[3]), str(v[4])), Why: "Un movimiento detectado no confirma el cobro por sí mismo.",
			Action: "Confirma o rechaza la conciliación.", Consequence: "El cobro no cuenta y el proyecto no arranca.", Recommendation: "Confirmar si el importe y la referencia coinciden.",
			EntityType: "movement", EntityID: str(v[0]), Capability: "FIN-07", Factors: map[string]int{"urgencia": 2, "impacto": 2, "riesgo": 1}})
	})
	q(`SELECT count(*) FROM biz_bank_movement WHERE workspace_id=$1 AND status='unreconciled' AND nature IN ('operating_income','operating_expense')`, ws1, func(v []any) {
		if n := int(num(v[0])); n > 0 {
			add(Exception{Area: "finanzas", Kind: "unreconciled", Severity: "baja", Title: fmt.Sprintf("%d movimientos operativos sin conciliar", n),
				What: "Movimientos sin factura asociada.", Why: "El paquete trimestral los listará como diferencias.", Action: "Concilia, clasifica o adjunta justificante.",
				Consequence: "Trimestre sin cerrar.", Recommendation: "Revisar en la vista de bancos.", EntityType: "", Capability: "FIN-07", Factors: map[string]int{"urgencia": 1, "impacto": 1}})
		}
	})
	q(`SELECT i.id::text, i.number, coalesce(o.name,'') FROM biz_invoice i LEFT JOIN biz_organization o ON o.id=i.organization_id WHERE i.workspace_id=$1 AND i.direction='received' AND i.document_id IS NULL`, ws1, func(v []any) {
		add(Exception{Area: "finanzas", Kind: "missing_receipt", Severity: "baja", Title: "Gasto sin justificante: " + str(v[2]) + " " + str(v[1]),
			What: "Factura recibida registrada sin documento original.", Why: "La gestoría necesita el justificante.", Action: "Adjunta el PDF en la carpeta y enlázalo.",
			Consequence: "Gasto no deducible sin justificante.", Recommendation: "Pedir el PDF al proveedor.", EntityType: "invoice", EntityID: str(v[0]), Capability: "FIN-09",
			Factors: map[string]int{"urgencia": 1, "impacto": 1, "riesgo": 1}})
	})
	q(`SELECT i.id::text, i.title, p.title, ($2::date - i.due_date)::int, coalesce(a.name, u.name, 'sin responsable') FROM issue i JOIN biz_project_link l ON l.project_id=i.project_id JOIN project p ON p.id=i.project_id
		JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status LEFT JOIN agent a ON i.assignee_type='agent' AND a.id=i.assignee_id
		LEFT JOIN "user" u ON i.assignee_type='member' AND u.id=i.assignee_id
		WHERE i.workspace_id=$1 AND st.category NOT IN ('done','closed') AND i.due_date < $2`, []any{ws, t}, func(v []any) {
		add(Exception{Area: "entrega", Kind: "overdue_task", Severity: "alta", Title: "Tarea vencida: " + str(v[1]),
			What: fmt.Sprintf("%s · vencida hace %d días · %s", str(v[2]), int(num(v[3])), str(v[4])), Why: "El vencimiento es un compromiso con el cliente.",
			Action: "Termínala o renegocia el compromiso con autorización.", Consequence: "Incumplimiento con el cliente.", Recommendation: "Prioriza sobre trabajo nuevo.",
			EntityType: "issue", EntityID: str(v[0]), Capability: "ENT-07", Factors: map[string]int{"urgencia": 3, "impacto": 2, "riesgo": 2}})
	})
	q(`SELECT p.id::text, p.title, extract(day from now()-max(coalesce(i.updated_at, p.updated_at)))::int FROM project p JOIN biz_project_link l ON l.project_id=p.id LEFT JOIN issue i ON i.project_id=p.id
		WHERE p.workspace_id=$1 AND p.status='in_progress' GROUP BY p.id HAVING max(coalesce(i.updated_at, p.updated_at)) < now()-interval '7 days'`, ws1, func(v []any) {
		add(Exception{Area: "entrega", Kind: "stale_project", Severity: "media", Title: "Proyecto quieto: " + str(v[1]), What: fmt.Sprintf("%d días sin movimiento.", int(num(v[2]))),
			Why: "Un proyecto quieto suele esconder un bloqueo.", Action: "Revisa qué falta y desbloquea.", Consequence: "Riesgo de vencimiento.", Recommendation: "Pregunta al agente Implementador.",
			EntityType: "project", EntityID: str(v[0]), Capability: "ENT-07", Factors: map[string]int{"urgencia": 2, "impacto": 2}})
	})
	q(`SELECT p.id::text, p.title FROM project p LEFT JOIN biz_project_link l ON l.project_id=p.id WHERE p.workspace_id=$1 AND p.status IN ('planned','in_progress')
		AND (l.project_id IS NULL OR (l.kind='strategic' AND l.objective_id IS NULL))`, ws1, func(v []any) {
		add(Exception{Area: "direccion", Kind: "project_without_objective", Severity: "baja", Title: "Proyecto sin objetivo: " + str(v[1]),
			What: "Proyecto activo que no cuelga de un objetivo ni de un servicio.", Why: "Todo proyecto activo responde a un objetivo estratégico, de cumplimiento o de servicio (DIR-03).",
			Action: "Enlázalo a un objetivo o archívalo.", Consequence: "Trabajo que no mueve ningún número.", Recommendation: "Revisión semanal.",
			EntityType: "project", EntityID: str(v[0]), Capability: "DIR-03", Factors: map[string]int{"impacto": 1}})
	})
	q(`SELECT id::text, title, extract(day from now()-created_at)::int FROM biz_decision WHERE workspace_id=$1 AND status='open' AND created_at < now()-interval '7 days'`, ws1, func(v []any) {
		add(Exception{Area: "direccion", Kind: "decision_open", Severity: "media", Title: "Decisión abierta: " + str(v[1]), What: fmt.Sprintf("Abierta hace %d días.", int(num(v[2]))),
			Why: "Lo no decidido frena a quien depende de ello.", Action: "Decide con porqué y para qué, o descártala.", Consequence: "Dependencia del dueño.",
			Recommendation: "Pide al comité de agentes los argumentos.", EntityType: "decision", EntityID: str(v[0]), Capability: "DIR-01", Factors: map[string]int{"urgencia": 1, "impacto": 2}})
	})
	q(`SELECT id::text, title, scheduled_at FROM biz_content WHERE workspace_id=$1 AND status='programado' AND scheduled_at < now()`, ws1, func(v []any) {
		add(Exception{Area: "marca", Kind: "content_overdue", Severity: "media", Title: "Publicación sin confirmar: " + str(v[1]),
			What: "Pasó la fecha programada y no consta la publicación.", Why: "Publicado exige confirmación o evidencia.", Action: "Añade la evidencia o márcala como fallida.",
			Consequence: "El calendario no refleja la realidad.", Recommendation: "Verificar en la red social.", EntityType: "content", EntityID: str(v[0]), Capability: "MAR-04", Factors: map[string]int{"urgencia": 2}})
	})
	q(`SELECT id::text, channel, handle FROM biz_conversation WHERE workspace_id=$1 AND NOT qualified AND contact_id IS NULL AND created_at < now()-interval '3 days'`, ws1, func(v []any) {
		add(Exception{Area: "marca", Kind: "conversation_unqualified", Severity: "baja", Title: "Conversación sin cualificar: " + str(v[2]) + " (" + str(v[1]) + ")",
			What: "Conversación de hace más de 3 días sin decidir si pasa a Ventas.", Why: "Las conversaciones útiles son el número que mide Marca.", Action: "Cualifícala o descártala.",
			Consequence: "Demanda perdida.", Recommendation: "Revisar con el agente de Marca.", EntityType: "conversation", EntityID: str(v[0]), Capability: "MAR-07", Factors: map[string]int{"impacto": 1}})
	})
	q(`SELECT a.id::text, a.name, g.area FROM biz_agent g JOIN agent a ON a.id=g.agent_id
		JOIN LATERAL (SELECT status FROM agent_task_queue t WHERE t.agent_id=g.agent_id AND t.status IN ('completed','failed') ORDER BY t.created_at DESC LIMIT 1) last ON last.status='failed'
		WHERE g.workspace_id=$1`, ws1, func(v []any) {
		add(Exception{Area: "equipo", Kind: "agent_failed", Severity: "alta", Title: "Agente con fallo: " + str(v[1]), What: "Su última ejecución falló (área " + str(v[2]) + ").",
			Why: "Lo que dependía de él está parado.", Action: "Abre la ejecución, corrige la causa y reintenta.", Consequence: "Trabajo detenido en el área.", Recommendation: "Revisar el runtime y las instrucciones.",
			EntityType: "agent", EntityID: str(v[0]), Capability: "EQU-07", Factors: map[string]int{"urgencia": 2, "impacto": 2, "riesgo": 1}})
	})
	q(`SELECT id::text, name, area FROM biz_role WHERE workspace_id=$1 AND occupant_id IS NULL AND archived_at IS NULL`, ws1, func(v []any) {
		add(Exception{Area: "equipo", Kind: "role_vacant", Severity: "baja", Title: "Rol vacante: " + str(v[1]), What: "Área " + str(v[2]) + " sin ocupante en este rol.",
			Why: "Nadie responde de sus decisiones y KPI.", Action: "Asigna una persona o un agente.", Consequence: "Las decisiones vuelven al dueño.", Recommendation: "Revisión mensual de equipo.",
			EntityType: "role", EntityID: str(v[0]), Capability: "EQU-02", Factors: map[string]int{"impacto": 1}})
	})
	if s.KillSwitchOn(ctx, ws) {
		add(Exception{Area: "direccion", Kind: "kill_switch", Severity: "alta", Title: "Interruptor global activado", What: "Ningún agente ni automatismo puede escribir.",
			Why: "Es una parada de seguridad.", Action: "Desactívalo cuando quieras reanudar.", Consequence: "El trabajo automático está detenido.", Recommendation: "Revisa el motivo antes de reanudar.",
			Capability: "DIR-11", Factors: map[string]int{"urgencia": 3, "impacto": 3}})
	}
	if n := s.Folder.PendingCount(ctx, ws); n > 0 && s.Folder.Root(ctx, s.Pool, ws) != "" {
		add(Exception{Area: "direccion", Kind: "folder_pending", Severity: "baja", Title: fmt.Sprintf("%d escrituras pendientes en la carpeta", n), What: "Cambios confirmados aún no escritos en la carpeta portable.",
			Why: "La carpeta es la copia legible y recuperable.", Action: "Se reintentan solas; si persisten, revisa permisos de la carpeta.", Consequence: "La carpeta va por detrás.",
			Recommendation: "Revisar el estado de la carpeta.", Capability: "DIR-09", Factors: map[string]int{"riesgo": 1}})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Score > out[j].Score })
	if out == nil {
		out = []Exception{}
	}
	return out, nil
}

// --- Overview ------------------------------------------------------------

type AreaHealth struct {
	AreaInfo
	Status      string     `json:"status"`
	Explanation string     `json:"explanation"`
	KPIs        []KPIValue `json:"kpis"`
	Exceptions  int        `json:"exceptions"`
	Paused      bool       `json:"paused"`
	Maturity    Maturity   `json:"maturity"`
}

type Maturity struct {
	Stage    int      `json:"stage"`
	Label    string   `json:"label"`
	Evidence []string `json:"evidence"`
	Note     string   `json:"note"`
}

var stageLabels = []string{"", "Validación", "Estandarización", "Sistematización", "Automatización", "Equipo y delegación", "Empresa"}

func (s *Service) Overview(ctx context.Context, ws string) (map[string]any, error) {
	kpis, err := s.ComputeKPIs(ctx, ws, "")
	if err != nil {
		return nil, err
	}
	exc, _ := s.Exceptions(ctx, ws, "")
	byArea := map[string][]KPIValue{}
	for _, k := range kpis {
		byArea[k.Area] = append(byArea[k.Area], k)
	}
	excByArea := map[string]int{}
	for _, e := range exc {
		excByArea[e.Area]++
	}
	paused := map[string]bool{}
	rows, _ := s.Pool.Query(ctx, `SELECT code, paused FROM biz_area WHERE workspace_id=$1`, ws)
	for rows != nil && rows.Next() {
		var c string
		var p bool
		_ = rows.Scan(&c, &p)
		paused[c] = p
	}
	if rows != nil {
		rows.Close()
	}
	var areas []AreaHealth
	worst, worstScore := "", -1.0
	for _, a := range Areas {
		h := AreaHealth{AreaInfo: a, KPIs: byArea[a.Code], Exceptions: excByArea[a.Code], Paused: paused[a.Code], Maturity: s.maturity(ctx, ws, a.Code)}
		alerts, warns, oks, unknown := 0, 0, 0, 0
		for _, k := range h.KPIs {
			switch k.Status {
			case "alert":
				alerts++
			case "warning":
				warns++
			case "ok":
				oks++
			default:
				unknown++
			}
		}
		// An excess in one KPI never compensates a critical one.
		switch {
		case alerts > 0:
			h.Status = "alert"
			h.Explanation = fmt.Sprintf("%d indicador(es) en alerta", alerts)
		case warns > 0:
			h.Status = "warning"
			h.Explanation = fmt.Sprintf("%d indicador(es) por debajo de la meta", warns)
		case oks > 0:
			h.Status = "ok"
			h.Explanation = fmt.Sprintf("%d indicador(es) en meta", oks)
		default:
			h.Status = "no_data"
			h.Explanation = "Sin datos suficientes"
		}
		if unknown > 0 && h.Status != "no_data" {
			h.Explanation += fmt.Sprintf(" · %d sin datos o sin meta", unknown)
		}
		measured := alerts + warns + oks
		if measured > 0 {
			score := float64(alerts*2+warns)/float64(measured) + float64(h.Exceptions)*0.05
			if score > worstScore {
				worst, worstScore = a.Code, score
			}
		}
		areas = append(areas, h)
	}
	var objectives json.RawMessage
	y, q := quarterOf(madridNow())
	objectives, _ = listJSON(ctx, s.Pool, `SELECT * FROM biz_objective WHERE workspace_id=$1 AND period=$2 ORDER BY area, created_at`, ws, fmt.Sprintf("%d-T%d", y, q))
	decisions, _ := listJSON(ctx, s.Pool, `SELECT id, area, title, status, created_at FROM biz_decision WHERE workspace_id=$1 AND status='open' ORDER BY created_at`, ws)
	var ownerDependency, approvals int
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM biz_approval WHERE workspace_id=$1 AND status='pending'`, ws).Scan(&approvals)
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM issue i JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status
		WHERE i.workspace_id=$1 AND i.assignee_type='member' AND st.category NOT IN ('done','closed')`, ws).Scan(&ownerDependency)
	cash, cashCov := s.cash(ctx, ws)
	runway, runwayExp := s.runway(ctx, ws)
	top := exc
	if len(top) > 12 {
		top = top[:12]
	}
	var mode string
	_ = json.Unmarshal(s.Setting(ctx, s.Pool, ws, "mode"), &mode)
	return map[string]any{
		"areas": areas, "bottleneck": worst, "exceptions": top, "exceptions_total": len(exc), "objectives": objectives, "open_decisions": decisions,
		"cash": cash, "cash_coverage": cashCov, "runway": runway, "runway_explanation": runwayExp,
		"owner_dependency": map[string]int{"pending_approvals": approvals, "open_tasks_on_people": ownerDependency},
		"controls": map[string]any{"kill_switch": s.KillSwitchOn(ctx, ws), "read_only": s.settingBool(ctx, s.Pool, ws, "read_only")},
		"mode": mode, "folder_pending": s.Folder.PendingCount(ctx, ws),
	}, nil
}

// maturity is an explainable estimate from evidence, never from counting
// agents. The person reviews it.
func (s *Service) maturity(ctx context.Context, ws, area string) Maturity {
	var caps, implemented, delegated int
	for _, c := range Capabilities {
		if c.Area != area || c.Level != "E" {
			continue
		}
		caps++
		if c.Status == "implemented" {
			implemented++
		}
	}
	var hasRole, roleHasManual, roleOccupied bool
	_ = s.Pool.QueryRow(ctx, `SELECT count(*)>0, bool_or(manual<>''), bool_or(occupant_id IS NOT NULL) FROM biz_role WHERE workspace_id=$1 AND area=$2`, ws, area).Scan(&hasRole, &roleHasManual, &roleOccupied)
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM biz_policy WHERE workspace_id=$1 AND mode IN ('supervised','autonomous') AND capability LIKE $2`, ws, map[string]string{
		"direccion": "DIR", "ventas": "VEN", "entrega": "ENT", "finanzas": "FIN", "marca": "MAR", "equipo": "EQU"}[area]+"-%").Scan(&delegated)
	var agentAssigned bool
	_ = s.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM biz_agent WHERE workspace_id=$1 AND area=$2)`, ws, area).Scan(&agentAssigned)
	ev := []string{}
	stage := 1
	ev = append(ev, fmt.Sprintf("%d de %d capacidades esenciales implementadas en esta build", implemented, caps))
	if hasRole && roleHasManual {
		stage = 2
		ev = append(ev, "Rol con manual escrito")
	}
	if stage >= 2 && implemented*2 >= caps {
		stage = 3
		ev = append(ev, "Procesos esenciales sistematizados")
	}
	if stage >= 3 && agentAssigned {
		stage = 4
		ev = append(ev, "Agente de área con permisos acotados")
	}
	if stage >= 4 && roleOccupied && delegated >= 2 {
		stage = 5
		ev = append(ev, fmt.Sprintf("%d capacidades delegadas en modo supervisado o autónomo", delegated))
	}
	return Maturity{Stage: stage, Label: stageLabels[stage], Evidence: ev, Note: "Estimación explicable; revísala en la revisión trimestral."}
}
