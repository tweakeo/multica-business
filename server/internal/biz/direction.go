package biz

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/jackc/pgx/v5"
)

func (s *Service) registerDirection() {
	s.register(&Command{
		Action: "decision.create", Capability: "DIR-01", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Area     string          `json:"area"`
				Title    string          `json:"title"`
				Context  string          `json:"context"`
				Decision string          `json:"decision"`
				Why      string          `json:"why"`
				Purpose  string          `json:"purpose"`
				Refs     json.RawMessage `json:"refs"`
			}](p)
			if err != nil {
				return nil, err
			}
			if !IsArea(in.Area) || strings.TrimSpace(in.Title) == "" {
				return nil, invalid("La decisión necesita área y título")
			}
			if len(in.Refs) == 0 {
				in.Refs = json.RawMessage(`[]`)
			}
			status, decidedAt := "open", any(nil)
			if strings.TrimSpace(in.Decision) != "" {
				if strings.TrimSpace(in.Why) == "" || strings.TrimSpace(in.Purpose) == "" {
					return nil, invalid("Una decisión tomada registra su porqué y su para qué")
				}
				status, decidedAt = "decided", "now"
			}
			// Agents prepare the decision; only a person decides it.
			if a.Type != "member" && status == "decided" {
				status, decidedAt = "open", nil
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_decision (workspace_id, area, title, status, context, decision, why, purpose, refs, author_type, author_id, decided_at)
				VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, CASE WHEN $12::text='now' THEN now() END) RETURNING to_jsonb(biz_decision.*)`,
				ws, in.Area, in.Title, status, in.Context, in.Decision, in.Why, in.Purpose, in.Refs, a.Type, nullable(map[bool]string{true: a.UserID, false: a.ID}[a.Type == "member"]), decidedAt).Scan(&row); err != nil {
				return nil, err
			}
			res := entityResult("decision", row)
			s.Folder.Journal(ctx, tx, ws, "decision", str(res["id"]))
			return res, nil
		},
	})

	// Decide an open decision. Decided ones are never edited: a correction is
	// a new decision that supersedes the previous one.
	s.register(&Command{
		Action: "decision.decide", Capability: "DIR-01", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			if a.Type != "member" {
				return nil, errf(403, "forbidden", "Solo una persona autorizada decide; el agente prepara argumentos")
			}
			in, err := decode[struct {
				ID       string `json:"id"`
				Decision string `json:"decision"`
				Why      string `json:"why"`
				Purpose  string `json:"purpose"`
			}](p)
			if err != nil {
				return nil, err
			}
			if strings.TrimSpace(in.Decision) == "" || strings.TrimSpace(in.Why) == "" || strings.TrimSpace(in.Purpose) == "" {
				return nil, invalid("Indica la decisión, su porqué y su para qué")
			}
			var row json.RawMessage
			err = tx.QueryRow(ctx, `UPDATE biz_decision SET status='decided', decision=$3, why=$4, purpose=$5, decided_at=now(), author_type='member', author_id=$6,
				version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 AND status='open' RETURNING to_jsonb(biz_decision.*)`,
				in.ID, ws, in.Decision, in.Why, in.Purpose, a.UserID).Scan(&row)
			if err != nil {
				return nil, invalid("Solo se decide una decisión abierta")
			}
			s.Folder.Journal(ctx, tx, ws, "decision", in.ID)
			return entityResult("decision", row), nil
		},
	})

	s.register(&Command{
		Action: "decision.supersede", Capability: "DIR-01", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			if a.Type != "member" {
				return nil, errf(403, "forbidden", "Solo una persona corrige una decisión")
			}
			in, err := decode[struct {
				ID       string `json:"id"`
				Decision string `json:"decision"`
				Why      string `json:"why"`
				Purpose  string `json:"purpose"`
			}](p)
			if err != nil {
				return nil, err
			}
			var area, title string
			var refs json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_decision SET status='superseded', version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 AND status='decided'
				RETURNING area, title, refs`, in.ID, ws).Scan(&area, &title, &refs); err != nil {
				return nil, invalid("Solo se corrige una decisión tomada")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_decision (workspace_id, area, title, status, decision, why, purpose, refs, author_type, author_id, decided_at, supersedes_id)
				VALUES ($1,$2,$3,'decided',$4,$5,$6,$7,'member',$8, now(), $9) RETURNING to_jsonb(biz_decision.*)`,
				ws, area, title, in.Decision, in.Why, in.Purpose, refs, a.UserID, in.ID).Scan(&row); err != nil {
				return nil, err
			}
			res := entityResult("decision", row)
			s.Folder.Journal(ctx, tx, ws, "decision", in.ID)
			s.Folder.Journal(ctx, tx, ws, "decision", str(res["id"]))
			return res, nil
		},
	})

	s.register(&Command{
		Action: "objective.save", Capability: "DIR-02", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID         string   `json:"id"`
				Area       string   `json:"area"`
				Period     string   `json:"period"`
				Title      string   `json:"title"`
				Kind       string   `json:"kind"`
				KPICode    string   `json:"kpi_code"`
				Target     *float64 `json:"target"`
				Baseline   *float64 `json:"baseline"`
				Status     string   `json:"status"`
				Result     string   `json:"result"`
				Learnings  string   `json:"learnings"`
				DeferredTo string   `json:"deferred_to"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.Status == "" {
				in.Status = "active"
			}
			if in.Kind == "" {
				in.Kind = "cumulative"
			}
			if in.Status == "deferred" && in.DeferredTo == "" {
				return nil, invalid("Un objetivo aplazado necesita destino")
			}
			var row json.RawMessage
			if in.ID == "" {
				if !IsArea(in.Area) || in.Period == "" || strings.TrimSpace(in.Title) == "" {
					return nil, invalid("El objetivo necesita área, periodo y título")
				}
				if (in.Kind == "cumulative" || in.Kind == "level") && (in.Target == nil || in.KPICode == "") {
					return nil, invalid("Un objetivo con número comprobable necesita KPI y meta (DIR-02)")
				}
				err = tx.QueryRow(ctx, `INSERT INTO biz_objective (workspace_id, area, period, title, kind, kpi_code, target, baseline, owner_type, owner_id, status)
					VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING to_jsonb(biz_objective.*)`, ws, in.Area, in.Period, in.Title, in.Kind, in.KPICode, in.Target, in.Baseline,
					nullable(map[bool]string{true: "member"}[a.Type == "member"]), nullable(a.UserID), in.Status).Scan(&row)
			} else {
				err = tx.QueryRow(ctx, `UPDATE biz_objective SET status=$3, result=coalesce(nullif($4,''), result), learnings=coalesce(nullif($5,''), learnings),
					deferred_to=$6, target=coalesce($7, target), version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_objective.*)`,
					in.ID, ws, in.Status, in.Result, in.Learnings, in.DeferredTo, in.Target).Scan(&row)
			}
			if err != nil {
				return nil, invalid("No se pudo guardar el objetivo: %v", err)
			}
			res := entityResult("objective", row)
			s.Folder.Journal(ctx, tx, ws, "objective", str(res["id"]))
			return res, nil
		},
	})

	s.register(&Command{
		Action: "routine.save", Capability: "DIR-05", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Kind      string `json:"kind"`
				PeriodKey string `json:"period_key"`
				Focus     string `json:"focus"`
				Plan      string `json:"plan"`
				Verdict   string `json:"verdict"`
				Review    string `json:"review"`
				Close     bool   `json:"close"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.PeriodKey == "" {
				return nil, invalid("Falta el periodo de la rutina")
			}
			if in.Close && strings.TrimSpace(in.Verdict) == "" && strings.TrimSpace(in.Review) == "" {
				return nil, invalid("Cerrar exige veredicto o balance")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_routine (workspace_id, kind, period_key, focus, plan, verdict, review, closed_at, author_type, author_id)
				VALUES ($1,$2,$3,$4,$5,$6,$7, CASE WHEN $8 THEN now() END, $9, $10)
				ON CONFLICT (workspace_id, kind, period_key) DO UPDATE SET
					focus=coalesce(nullif(EXCLUDED.focus,''), biz_routine.focus), plan=coalesce(nullif(EXCLUDED.plan,''), biz_routine.plan),
					verdict=coalesce(nullif(EXCLUDED.verdict,''), biz_routine.verdict), review=coalesce(nullif(EXCLUDED.review,''), biz_routine.review),
					closed_at=coalesce(EXCLUDED.closed_at, biz_routine.closed_at), version=biz_routine.version+1, updated_at=now()
				RETURNING to_jsonb(biz_routine.*)`, ws, in.Kind, in.PeriodKey, in.Focus, in.Plan, in.Verdict, in.Review, in.Close, a.Type,
				nullable(map[bool]string{true: a.UserID, false: a.ID}[a.Type == "member"])).Scan(&row); err != nil {
				return nil, invalid("No se pudo guardar la rutina: %v", err)
			}
			res := entityResult("routine", row)
			s.Folder.Journal(ctx, tx, ws, "routine", str(res["id"]))
			return res, nil
		},
	})

	s.register(&Command{
		Action: "settings.set", Capability: "DIR-11", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Key   string          `json:"key"`
				Value json.RawMessage `json:"value"`
			}](p)
			if err != nil {
				return nil, err
			}
			allowed := map[string]bool{"kill_switch": true, "read_only": true, "company_folder": true, "mode": true, "company_profile": true, "capacity_hours_per_day": true, "import_mode": true, "rituals_enabled": true}
			if !allowed[in.Key] {
				return nil, invalid("Ajuste no permitido: %s", in.Key)
			}
			if _, err := tx.Exec(ctx, `INSERT INTO biz_setting (workspace_id, key, value, updated_by) VALUES ($1,$2,$3,$4)
				ON CONFLICT (workspace_id, key) DO UPDATE SET value=EXCLUDED.value, updated_by=EXCLUDED.updated_by, updated_at=now()`,
				ws, in.Key, in.Value, a.Type+":"+a.UserID); err != nil {
				return nil, err
			}
			if in.Key == "kill_switch" && string(in.Value) == "true" {
				// Stop new effects now: cancel queued runs of this company's agents.
				_, _ = tx.Exec(ctx, `UPDATE agent_task_queue SET status='cancelled', completed_at=now(), cancelled_by_type='system', cancelled_by_name='Interruptor global' WHERE status='queued'
					AND agent_id IN (SELECT agent_id FROM biz_agent WHERE workspace_id=$1)`, ws)
			}
			return map[string]any{"entity_type": "setting", "key": in.Key, "value": in.Value}, nil
		},
	})

	s.register(&Command{
		Action: "area.set", Capability: "DIR-11", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Code    string `json:"code"`
				Paused  *bool  `json:"paused"`
				Enabled *bool  `json:"enabled"`
				Note    string `json:"note"`
			}](p)
			if err != nil {
				return nil, err
			}
			if !IsArea(in.Code) {
				return nil, invalid("Área desconocida")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_area (workspace_id, code, paused, enabled, note) VALUES ($1,$2,coalesce($3,false),coalesce($4,true),$5)
				ON CONFLICT (workspace_id, code) DO UPDATE SET paused=coalesce($3, biz_area.paused), enabled=coalesce($4, biz_area.enabled),
				note=CASE WHEN $5<>'' THEN $5 ELSE biz_area.note END, updated_at=now() RETURNING to_jsonb(biz_area.*)`,
				ws, in.Code, in.Paused, in.Enabled, in.Note).Scan(&row); err != nil {
				return nil, err
			}
			return entityResult("area", row), nil
		},
	})

	s.register(&Command{
		Action: "policy.set", Capability: "EQU-06", Area: "equipo",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Capability string          `json:"capability"`
				Mode       string          `json:"mode"`
				Limits     json.RawMessage `json:"limits"`
			}](p)
			if err != nil {
				return nil, err
			}
			c, ok := CapabilityByCode(in.Capability)
			if !ok {
				return nil, invalid("Capacidad desconocida")
			}
			if len(in.Limits) == 0 {
				in.Limits = json.RawMessage(`{}`)
			}
			// Dependencies: a capability cannot run unattended if what it
			// relies on is switched off.
			if in.Mode == "autonomous" || in.Mode == "supervised" {
				for _, dep := range c.Requires {
					var depMode string
					if err := tx.QueryRow(ctx, `SELECT mode FROM biz_policy WHERE workspace_id=$1 AND capability=$2`, ws, dep).Scan(&depMode); err == nil && depMode == "off" {
						return nil, invalid("%s depende de %s, que está desactivada", in.Capability, dep)
					}
				}
			}
			if _, err := tx.Exec(ctx, `INSERT INTO biz_policy (workspace_id, capability, mode, limits, updated_by) VALUES ($1,$2,$3,$4,$5)
				ON CONFLICT (workspace_id, capability) DO UPDATE SET mode=EXCLUDED.mode, limits=EXCLUDED.limits, updated_by=EXCLUDED.updated_by, updated_at=now()`,
				ws, in.Capability, in.Mode, in.Limits, a.UserID); err != nil {
				return nil, invalid("Modo no válido: %v", err)
			}
			return map[string]any{"entity_type": "policy", "capability": in.Capability, "mode": in.Mode}, nil
		},
	})

	s.register(&Command{
		Action: "kpi.update", Capability: "DIR-04", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Code    string   `json:"code"`
				Target  *float64 `json:"target"`
				Alert   *float64 `json:"alert"`
				Enabled *bool    `json:"enabled"`
			}](p)
			if err != nil {
				return nil, err
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_kpi SET target=coalesce($3, target), alert=coalesce($4, alert), enabled=coalesce($5, enabled), version=version+1, updated_at=now()
				WHERE workspace_id=$1 AND code=$2 RETURNING to_jsonb(biz_kpi.*)`, ws, in.Code, in.Target, in.Alert, in.Enabled).Scan(&row); err != nil {
				return nil, errf(404, "not_found", "KPI no encontrado")
			}
			res := entityResult("kpi", row)
			s.Folder.Journal(ctx, tx, ws, "kpi", str(res["id"]))
			return res, nil
		},
	})
}
