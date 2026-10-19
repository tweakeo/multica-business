package biz

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/multica-ai/multica/server/internal/middleware"
)

// Routes mounts /api/biz inside the workspace-member group, so membership
// and the X-Workspace-ID selection are already enforced. Agents reach it
// with their task token, which pins the workspace server-side.
func (s *Service) Routes(r chi.Router) {
	r.Get("/meta", s.handle(s.getMeta))
	r.Post("/bootstrap", s.handle(s.postBootstrap))
	r.Get("/overview", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) { return s.Overview(ctx, ws) }))
	r.Get("/areas/{area}", s.handle(s.getArea))
	r.Get("/kpis", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
		return s.ComputeKPIs(ctx, ws, r.URL.Query().Get("area"))
	}))
	r.Get("/exceptions", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
		return s.Exceptions(ctx, ws, r.URL.Query().Get("area"))
	}))
	r.Get("/list/{entity}", s.handle(s.getList))
	r.Get("/record/{entity}/{id}", s.handle(s.getRecord))
	r.Get("/projects", s.handle(s.getProjects))
	r.Get("/team", s.handle(s.getTeam))
	r.Get("/search", s.handle(s.getSearch))
	r.Get("/audit", s.handle(s.getAudit))
	r.Get("/events", s.handle(s.getEvents))
	r.Get("/actions", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) { return s.Actions(), nil }))
	r.Post("/run/{action}", s.handleRun)
	r.Post("/approvals/{id}/decide", s.handle(s.postDecide))
	r.Get("/folder/status", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) { return s.Folder.Status(ctx, ws) }))
	r.Post("/folder/export", s.handle(s.postFolderExport))
	r.Post("/folder/rebuild", s.handle(s.postFolderRebuild))
	r.Post("/events/process", s.handle(func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
		s.ProcessEvents(ctx)
		return map[string]any{"ok": true}, nil
	}))
}

func actorFrom(r *http.Request) Actor {
	if r.Header.Get("X-Actor-Source") == "task_token" {
		return Actor{Type: "agent", ID: r.Header.Get("X-Agent-ID"), TaskID: r.Header.Get("X-Task-ID"), UserID: r.Header.Get("X-User-ID")}
	}
	a := Actor{Type: "member", ID: r.Header.Get("X-User-ID"), UserID: r.Header.Get("X-User-ID")}
	if m, ok := middleware.MemberFromContext(r.Context()); ok {
		a.Role = m.Role
	}
	return a
}

type handlerFn func(ctx context.Context, ws string, a Actor, r *http.Request) (any, error)

func (s *Service) handle(fn handlerFn) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ws := middleware.WorkspaceIDFromContext(r.Context())
		if ws == "" {
			writeErr(w, errf(http.StatusBadRequest, "workspace_required", "Falta el espacio de trabajo"))
			return
		}
		out, err := fn(r.Context(), ws, actorFrom(r), r)
		if err != nil {
			writeErr(w, err)
			return
		}
		writeJSON(w, http.StatusOK, out)
	}
}

func (s *Service) handleRun(w http.ResponseWriter, r *http.Request) {
	ws := middleware.WorkspaceIDFromContext(r.Context())
	body, err := io.ReadAll(io.LimitReader(r.Body, 4<<20))
	if err != nil {
		writeErr(w, invalid("Cuerpo no legible"))
		return
	}
	res, err := s.Run(r.Context(), ws, actorFrom(r), chi.URLParam(r, "action"), body)
	if err != nil {
		writeErr(w, err)
		return
	}
	status := http.StatusOK
	if res.Status == "approval_required" {
		status = http.StatusAccepted
	}
	writeJSON(w, status, res)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if raw, ok := v.(json.RawMessage); ok {
		_, _ = w.Write(raw)
		return
	}
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, err error) {
	var e *Error
	if errors.As(err, &e) {
		writeJSON(w, e.Status, e)
		return
	}
	writeJSON(w, http.StatusInternalServerError, &Error{Code: "internal", Msg: err.Error()})
}

// --- Reads ---------------------------------------------------------------

func (s *Service) EnsureBootstrap(ctx context.Context, ws string) error {
	for _, a := range Areas {
		if _, err := s.Pool.Exec(ctx, `INSERT INTO biz_area (workspace_id, code) VALUES ($1,$2) ON CONFLICT DO NOTHING`, ws, a.Code); err != nil {
			return err
		}
	}
	for _, k := range DefaultKPIs {
		if _, err := s.Pool.Exec(ctx, `INSERT INTO biz_kpi (workspace_id, code, area, name, unit, formula, direction, target, alert, period)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) ON CONFLICT (workspace_id, code) DO NOTHING`, ws, k.Code, k.Area, k.Name, k.Unit, k.Formula, k.Direction, k.Target, k.Alert, k.Period); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) postBootstrap(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	if a.Type != "member" {
		return nil, errf(403, "forbidden", "Solo una persona inicializa la empresa")
	}
	return map[string]any{"ok": true}, s.EnsureBootstrap(ctx, ws)
}

func (s *Service) getMeta(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	_ = s.EnsureBootstrap(ctx, ws)
	policies := map[string]string{}
	rows, err := s.Pool.Query(ctx, `SELECT capability, mode FROM biz_policy WHERE workspace_id=$1`, ws)
	if err == nil {
		for rows.Next() {
			var c, m string
			_ = rows.Scan(&c, &m)
			policies[c] = m
		}
		rows.Close()
	}
	caps := make([]map[string]any, 0, len(Capabilities))
	for _, c := range Capabilities {
		mode, explicit := policies[c.Code]
		if !explicit {
			mode = map[bool]string{true: "supervised", false: "assisted"}[c.Sensitive]
		}
		b, _ := json.Marshal(c)
		var m map[string]any
		_ = json.Unmarshal(b, &m)
		m["mode"], m["mode_explicit"] = mode, explicit
		caps = append(caps, m)
	}
	areas, _ := listJSON(ctx, s.Pool, `SELECT * FROM biz_area WHERE workspace_id=$1`, ws)
	settings, _ := listJSON(ctx, s.Pool, `SELECT key, value, updated_at, updated_by FROM biz_setting WHERE workspace_id=$1 AND key NOT LIKE 'done:%' AND key NOT LIKE 'invoice_counter_%'`, ws)
	return map[string]any{
		"areas": Areas, "area_state": areas, "capabilities": caps, "stages": OpportunityStages, "stage_probability": StageProbability,
		"actions": s.Actions(), "settings": settings, "actor": a,
	}, nil
}

func (s *Service) getArea(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	area := chi.URLParam(r, "area")
	if !IsArea(area) {
		return nil, errf(404, "not_found", "Área desconocida")
	}
	kpis, err := s.ComputeKPIs(ctx, ws, area)
	if err != nil {
		return nil, err
	}
	exc, _ := s.Exceptions(ctx, ws, area)
	roles, _ := listJSON(ctx, s.Pool, `SELECT r.*, coalesce(ag.name, u.name) AS occupant_name FROM biz_role r LEFT JOIN agent ag ON r.occupant_type='agent' AND ag.id=r.occupant_id
		LEFT JOIN "user" u ON r.occupant_type='member' AND u.id=r.occupant_id WHERE r.workspace_id=$1 AND r.area=$2`, ws, area)
	agents, _ := listJSON(ctx, s.Pool, `SELECT g.*, a.name, a.description FROM biz_agent g JOIN agent a ON a.id=g.agent_id WHERE g.workspace_id=$1 AND (g.area=$2 OR g.is_coordinator)`, ws, area)
	var state json.RawMessage
	_ = s.Pool.QueryRow(ctx, `SELECT to_jsonb(a) FROM biz_area a WHERE workspace_id=$1 AND code=$2`, ws, area).Scan(&state)
	var info AreaInfo
	for _, x := range Areas {
		if x.Code == area {
			info = x
		}
	}
	caps := []Capability{}
	for _, c := range Capabilities {
		if c.Area == area {
			caps = append(caps, c)
		}
	}
	return map[string]any{"area": info, "state": state, "kpis": kpis, "exceptions": exc, "roles": roles, "agents": agents, "capabilities": caps, "maturity": s.maturity(ctx, ws, area)}, nil
}

// listQueries are the only list shapes exposed; every one filters by workspace.
var listQueries = map[string]string{
	"organization": `SELECT o.*, (SELECT count(*) FROM biz_contact c WHERE c.organization_id=o.id) AS contacts,
		(SELECT count(*) FROM biz_opportunity x WHERE x.organization_id=o.id) AS opportunities,
		(SELECT coalesce(sum(total_minor),0) FROM biz_invoice i WHERE i.organization_id=o.id AND i.direction='issued' AND i.status NOT IN ('draft','void')) AS billed_minor
		FROM biz_organization o WHERE o.workspace_id=$1`,
	"contact": `SELECT c.*, org.name AS organization_name, ct.title AS source_content_title FROM biz_contact c LEFT JOIN biz_organization org ON org.id=c.organization_id
		LEFT JOIN biz_content ct ON ct.id=c.source_content_id WHERE c.workspace_id=$1`,
	"opportunity": `SELECT o.*, c.name AS contact_name, c.email AS contact_email, org.name AS organization_name, s.name AS service_name, s.code AS service_code,
		coalesce(ag.name, u.name) AS owner_name, extract(day from now()-coalesce(o.last_contact_at, o.created_at))::int AS days_since_contact
		FROM biz_opportunity o LEFT JOIN biz_contact c ON c.id=o.contact_id LEFT JOIN biz_organization org ON org.id=o.organization_id
		LEFT JOIN biz_service s ON s.id=o.service_id LEFT JOIN agent ag ON o.owner_type='agent' AND ag.id=o.owner_id LEFT JOIN "user" u ON o.owner_type='member' AND u.id=o.owner_id
		WHERE o.workspace_id=$1`,
	"service": `SELECT s.*, w.name AS workflow_name, (SELECT to_jsonb(v) FROM biz_offer_version v WHERE v.service_id=s.id AND v.active ORDER BY version DESC LIMIT 1) AS offer,
		(SELECT count(*) FROM biz_project_link l JOIN project p ON p.id=l.project_id WHERE l.service_id=s.id AND p.status IN ('planned','in_progress')) AS active_projects,
		(SELECT count(*) FROM biz_opportunity o WHERE o.service_id=s.id AND o.stage NOT IN ('ganada','perdida')) AS open_opportunities
		FROM biz_service s LEFT JOIN issue_workflow w ON w.id=s.workflow_id WHERE s.workspace_id=$1`,
	"offer":   `SELECT v.*, s.name AS service_name FROM biz_offer_version v JOIN biz_service s ON s.id=v.service_id WHERE v.workspace_id=$1`,
	"invoice": `SELECT i.*, org.name AS organization_name, o.title AS opportunity_title, ($2::date - i.due_date)::int AS days_overdue, d.rel_path AS document_path FROM biz_invoice i LEFT JOIN biz_organization org ON org.id=i.organization_id LEFT JOIN biz_opportunity o ON o.id=i.opportunity_id LEFT JOIN biz_document d ON d.id=i.document_id WHERE i.workspace_id=$1`,
	"payment": `SELECT p.*, i.number AS invoice_number, i.direction FROM biz_payment p JOIN biz_invoice i ON i.id=p.invoice_id WHERE p.workspace_id=$1`,
	"account": `SELECT a.*, (SELECT count(*) FROM biz_bank_movement m WHERE m.account_id=a.id) AS movements,
		(SELECT balance_after_minor FROM biz_bank_movement m WHERE m.account_id=a.id AND balance_after_minor IS NOT NULL ORDER BY booked_on DESC, created_at DESC LIMIT 1) AS last_balance_minor
		FROM biz_bank_account a WHERE a.workspace_id=$1`,
	"movement": `SELECT m.*, a.name AS account_name, i.number AS invoice_number, org.name AS invoice_organization FROM biz_bank_movement m JOIN biz_bank_account a ON a.id=m.account_id
		LEFT JOIN biz_invoice i ON i.id=m.invoice_id LEFT JOIN biz_organization org ON org.id=i.organization_id WHERE m.workspace_id=$1`,
	"period":       `SELECT * FROM biz_period p WHERE p.workspace_id=$1`,
	"kpi":          `SELECT * FROM biz_kpi k WHERE k.workspace_id=$1`,
	"objective":    `SELECT * FROM biz_objective o WHERE o.workspace_id=$1`,
	"decision":     `SELECT d.*, coalesce(u.name, ag.name) AS author_name FROM biz_decision d LEFT JOIN "user" u ON d.author_type='member' AND u.id=d.author_id LEFT JOIN agent ag ON d.author_type='agent' AND ag.id=d.author_id WHERE d.workspace_id=$1`,
	"content":      `SELECT c.*, (SELECT count(*) FROM biz_conversation v WHERE v.content_id=c.id) AS conversations, (SELECT count(*) FROM biz_contact x WHERE x.source_content_id=c.id) AS contacts FROM biz_content c WHERE c.workspace_id=$1`,
	"conversation": `SELECT v.*, c.title AS content_title, x.name AS contact_name FROM biz_conversation v LEFT JOIN biz_content c ON c.id=v.content_id LEFT JOIN biz_contact x ON x.id=v.contact_id WHERE v.workspace_id=$1`,
	"routine":      `SELECT * FROM biz_routine r WHERE r.workspace_id=$1`,
	"role":         `SELECT r.*, coalesce(ag.name, u.name) AS occupant_name FROM biz_role r LEFT JOIN agent ag ON r.occupant_type='agent' AND ag.id=r.occupant_id LEFT JOIN "user" u ON r.occupant_type='member' AND u.id=r.occupant_id WHERE r.workspace_id=$1`,
	"document":     `SELECT * FROM biz_document d WHERE d.workspace_id=$1`,
	"approval": `SELECT p.*, coalesce(ag.name, u.name) AS requested_by_name, du.name AS decided_by_name FROM biz_approval p LEFT JOIN agent ag ON p.requested_by_type='agent' AND ag.id=p.requested_by_id
		LEFT JOIN "user" u ON p.requested_by_type='member' AND u.id=p.requested_by_id LEFT JOIN "user" du ON du.id=p.decided_by WHERE p.workspace_id=$1`,
}

var listOrder = map[string]string{
	"opportunity": "updated_at DESC", "invoice": "coalesce(issue_date, created_at::date) DESC, created_at DESC", "movement": "booked_on DESC, created_at DESC",
	"period": "year DESC, quarter DESC", "decision": "created_at DESC", "approval": "created_at DESC", "routine": "period_key DESC", "payment": "paid_on DESC",
	"content": "coalesce(scheduled_at, created_at) DESC", "conversation": "occurred_at DESC", "kpi": "area, code", "role": "area, name", "objective": "period DESC, area",
}

var filterable = map[string]bool{"stage": true, "status": true, "area": true, "service_id": true, "organization_id": true, "direction": true, "kind": true,
	"account_id": true, "contact_id": true, "nature": true, "channel": true, "pillar": true, "period": true, "invoice_id": true, "opportunity_id": true}

func (s *Service) getList(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	entity := chi.URLParam(r, "entity")
	base, ok := listQueries[entity]
	if !ok {
		return nil, errf(404, "not_found", "Colección desconocida")
	}
	args := []any{ws}
	if entity == "invoice" {
		args = append(args, today())
	}
	sql := "SELECT * FROM (" + base + ") t WHERE true"
	q := r.URL.Query()
	for key, vals := range q {
		if !filterable[key] || len(vals) == 0 || vals[0] == "" {
			continue
		}
		parts := strings.Split(vals[0], ",")
		args = append(args, parts)
		sql += fmt.Sprintf(" AND t.%s::text = ANY($%d)", key, len(args))
	}
	if term := strings.TrimSpace(q.Get("q")); term != "" {
		args = append(args, "%"+term+"%")
		sql += fmt.Sprintf(" AND to_jsonb(t)::text ILIKE $%d", len(args))
	}
	if q.Get("archived") != "true" && entity != "approval" {
		sql += " AND (to_jsonb(t)->>'archived_at') IS NULL"
	}
	if order, ok := listOrder[entity]; ok {
		sql += " ORDER BY " + order
	} else {
		sql += " ORDER BY created_at DESC"
	}
	limit := 500
	if l, err := strconv.Atoi(q.Get("limit")); err == nil && l > 0 && l < 2000 {
		limit = l
	}
	sql += fmt.Sprintf(" LIMIT %d", limit)
	return listJSON(ctx, s.Pool, sql, args...)
}

func (s *Service) getRecord(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	entity, id := chi.URLParam(r, "entity"), chi.URLParam(r, "id")
	base, ok := listQueries[entity]
	if !ok {
		return nil, errf(404, "not_found", "Tipo desconocido")
	}
	args := []any{ws}
	if entity == "invoice" {
		args = append(args, today())
	}
	args = append(args, id)
	row, err := oneJSON(ctx, s.Pool, fmt.Sprintf("SELECT * FROM (%s) t WHERE t.id::text=$%d", base, len(args)), args...)
	if err != nil {
		return nil, err
	}
	rel := map[string]json.RawMessage{}
	related := func(name, sql string, args ...any) {
		v, err := listJSON(ctx, s.Pool, sql, args...)
		if err == nil {
			rel[name] = v
		}
	}
	switch entity {
	case "opportunity":
		related("invoices", `SELECT id, number, status, total_minor, paid_minor, issue_date, due_date FROM biz_invoice WHERE opportunity_id=$1 ORDER BY created_at`, id)
		related("conversations", `SELECT * FROM biz_conversation WHERE contact_id=(SELECT contact_id FROM biz_opportunity WHERE id=$1) ORDER BY occurred_at DESC`, id)
		related("project", `SELECT p.id, p.title, p.status, (SELECT count(*) FROM issue i WHERE i.project_id=p.id) AS tasks FROM project p WHERE p.id=(SELECT project_id FROM biz_opportunity WHERE id=$1)`, id)
	case "organization":
		related("contacts", `SELECT id, name, email, position, kind FROM biz_contact WHERE organization_id=$1`, id)
		related("opportunities", `SELECT id, title, stage, value_minor FROM biz_opportunity WHERE organization_id=$1 ORDER BY created_at DESC`, id)
		related("invoices", `SELECT id, number, direction, status, total_minor, paid_minor, issue_date FROM biz_invoice WHERE organization_id=$1 ORDER BY created_at DESC`, id)
		related("projects", `SELECT p.id, p.title, p.status FROM biz_project_link l JOIN project p ON p.id=l.project_id WHERE l.organization_id=$1`, id)
	case "contact":
		related("opportunities", `SELECT id, title, stage, value_minor FROM biz_opportunity WHERE contact_id=$1`, id)
		related("conversations", `SELECT * FROM biz_conversation WHERE contact_id=$1 ORDER BY occurred_at DESC`, id)
	case "invoice":
		related("payments", `SELECT * FROM biz_payment WHERE invoice_id=$1 ORDER BY paid_on`, id)
		related("movements", `SELECT id, booked_on, description, amount_minor, status FROM biz_bank_movement WHERE invoice_id=$1`, id)
	case "content":
		related("conversations", `SELECT * FROM biz_conversation WHERE content_id=$1`, id)
		related("contacts", `SELECT id, name, kind FROM biz_contact WHERE source_content_id=$1`, id)
	case "service":
		related("offers", `SELECT * FROM biz_offer_version WHERE service_id=$1 ORDER BY version DESC`, id)
		related("projects", `SELECT p.id, p.title, p.status FROM biz_project_link l JOIN project p ON p.id=l.project_id WHERE l.service_id=$1 ORDER BY p.created_at DESC`, id)
	}
	related("audit", `SELECT b.*, coalesce(ag.name, u.name) AS actor_name FROM biz_audit b LEFT JOIN agent ag ON b.actor_type='agent' AND ag.id=b.actor_id
		LEFT JOIN "user" u ON b.actor_type='member' AND u.id=b.actor_id WHERE b.workspace_id=$1 AND b.entity_id::text=$2 ORDER BY at DESC LIMIT 50`, ws, id)
	related("events", `SELECT id, type, status, attempts, occurred_at, processed_at, last_error FROM biz_event WHERE workspace_id=$1 AND entity_id::text=$2 ORDER BY occurred_at DESC`, ws, id)
	related("documents", `SELECT * FROM biz_document WHERE workspace_id=$1 AND entity_id::text=$2`, ws, id)
	related("approvals", `SELECT id, title, status, created_at, decided_at, reason FROM biz_approval WHERE workspace_id=$1 AND entity_id::text=$2 ORDER BY created_at DESC`, ws, id)
	related("file", `SELECT rel_path, state, committed_at FROM biz_journal WHERE workspace_id=$1 AND entity_id::text=$2 AND state IN ('committed','intent') ORDER BY created_at DESC LIMIT 1`, ws, id)
	return map[string]any{"entity_type": entity, "record": row, "related": rel}, nil
}

func (s *Service) getProjects(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	return listJSON(ctx, s.Pool, `SELECT p.id, p.title, p.status, p.icon, p.start_date, p.due_date, p.lead_type, p.lead_id, p.workflow_id, l.kind, l.service_id, l.organization_id, l.opportunity_id, l.objective_id,
		s.name AS service_name, s.code AS service_code, org.name AS organization_name, ob.title AS objective_title, coalesce(ag.name, u.name) AS lead_name,
		count(i.id) AS tasks, count(i.id) FILTER (WHERE st.category IN ('done','closed')) AS tasks_done,
		count(i.id) FILTER (WHERE st.category NOT IN ('done','closed') AND i.due_date < $2) AS tasks_overdue,
		min(i.due_date) FILTER (WHERE st.category NOT IN ('done','closed')) AS next_due,
		max(i.updated_at) AS last_activity
		FROM project p LEFT JOIN biz_project_link l ON l.project_id=p.id LEFT JOIN biz_service s ON s.id=l.service_id LEFT JOIN biz_organization org ON org.id=l.organization_id
		LEFT JOIN biz_objective ob ON ob.id=l.objective_id LEFT JOIN agent ag ON p.lead_type='agent' AND ag.id=p.lead_id LEFT JOIN "user" u ON p.lead_type='member' AND u.id=p.lead_id
		LEFT JOIN issue i ON i.project_id=p.id LEFT JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status
		WHERE p.workspace_id=$1 GROUP BY p.id, l.project_id, s.id, org.id, ob.id, ag.id, u.id ORDER BY p.status, p.created_at DESC`, ws, today())
}

func (s *Service) getTeam(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	mStart, _, _ := monthBounds()
	members, _ := listJSON(ctx, s.Pool, `SELECT m.user_id AS id, m.role, u.name, u.email,
		(SELECT count(*) FROM issue i JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status WHERE i.workspace_id=$1 AND i.assignee_type='member' AND i.assignee_id=m.user_id AND st.category NOT IN ('done','closed')) AS open_tasks,
		(SELECT json_agg(r.name) FROM biz_role r WHERE r.workspace_id=$1 AND r.occupant_type='member' AND r.occupant_id=m.user_id) AS roles
		FROM member m JOIN "user" u ON u.id=m.user_id WHERE m.workspace_id=$1`, ws)
	agents, err := listJSON(ctx, s.Pool, `SELECT a.id, a.name, a.description, a.model, a.max_concurrent_tasks, a.archived_at, g.area, g.is_coordinator, g.budget_monthly_minor, g.max_delegation_depth,
		rt.provider, rt.status AS runtime_status, rt.last_seen_at,
		(SELECT json_agg(r.name) FROM biz_role r WHERE r.occupant_type='agent' AND r.occupant_id=a.id) AS roles,
		last.status AS last_status, last.completed_at AS last_run_at, last.error AS last_error,
		(SELECT count(*) FROM agent_task_queue t WHERE t.agent_id=a.id AND t.status IN ('queued','dispatched','running')) AS active_runs,
		(SELECT count(*) FROM biz_approval p WHERE p.requested_by_id=a.id AND p.status='pending') AS waiting_approval,
		(SELECT count(*) FROM agent_task_queue t WHERE t.agent_id=a.id AND t.created_at >= $2) AS runs_month,
		(SELECT coalesce(sum(u.input_tokens+u.output_tokens),0) FROM task_usage u JOIN agent_task_queue t ON t.id=u.task_id WHERE t.agent_id=a.id AND u.created_at >= $2) AS tokens_month,
		(SELECT sum(u.cost_usd_ticks) FROM task_usage u JOIN agent_task_queue t ON t.id=u.task_id WHERE t.agent_id=a.id AND u.created_at >= $2) AS cost_ticks_month,
		ar.paused AS area_paused
		FROM agent a LEFT JOIN biz_agent g ON g.agent_id=a.id LEFT JOIN agent_runtime rt ON rt.id=a.runtime_id LEFT JOIN biz_area ar ON ar.workspace_id=a.workspace_id AND ar.code=g.area
		LEFT JOIN LATERAL (SELECT status, completed_at, error FROM agent_task_queue t WHERE t.agent_id=a.id AND t.status IN ('completed','failed','cancelled') ORDER BY t.created_at DESC LIMIT 1) last ON true
		WHERE a.workspace_id=$1 AND a.archived_at IS NULL ORDER BY array_position(ARRAY['direccion','ventas','entrega','finanzas','marca','equipo'], g.area), a.name`, ws, mStart)
	if err != nil {
		return nil, err
	}
	roles, _ := listJSON(ctx, s.Pool, listQueries["role"]+` ORDER BY r.area, r.name`, ws)
	return map[string]any{"members": members, "agents": agents, "roles": roles, "kill_switch": s.KillSwitchOn(ctx, ws)}, nil
}

func (s *Service) getSearch(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	term := strings.TrimSpace(r.URL.Query().Get("q"))
	if len(term) < 2 {
		return json.RawMessage(`[]`), nil
	}
	like := "%" + term + "%"
	return listJSON(ctx, s.Pool, `
		SELECT 'organization' AS type, id::text, name AS title, kind AS subtitle FROM biz_organization WHERE workspace_id=$1 AND (name ILIKE $2 OR tax_id ILIKE $2)
		UNION ALL SELECT 'contact', id::text, name, coalesce(email,'') FROM biz_contact WHERE workspace_id=$1 AND (name ILIKE $2 OR email ILIKE $2)
		UNION ALL SELECT 'opportunity', id::text, title, stage FROM biz_opportunity WHERE workspace_id=$1 AND title ILIKE $2
		UNION ALL SELECT 'invoice', id::text, coalesce(number, 'Borrador'), direction || ' · ' || status FROM biz_invoice WHERE workspace_id=$1 AND (number ILIKE $2 OR notes ILIKE $2)
		UNION ALL SELECT 'content', id::text, title, status FROM biz_content WHERE workspace_id=$1 AND title ILIKE $2
		UNION ALL SELECT 'decision', id::text, title, status FROM biz_decision WHERE workspace_id=$1 AND title ILIKE $2
		UNION ALL SELECT 'project', id::text, title, status FROM project WHERE workspace_id=$1 AND title ILIKE $2
		LIMIT 40`, ws, like)
}

func (s *Service) getAudit(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	return listJSON(ctx, s.Pool, `SELECT b.*, coalesce(ag.name, u.name, b.actor_type) AS actor_name FROM biz_audit b LEFT JOIN agent ag ON b.actor_type='agent' AND ag.id=b.actor_id
		LEFT JOIN "user" u ON b.actor_type='member' AND u.id=b.actor_id WHERE b.workspace_id=$1 AND ($2='' OR b.actor_type=$2) ORDER BY at DESC LIMIT 300`, ws, r.URL.Query().Get("actor_type"))
}

func (s *Service) getEvents(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	return listJSON(ctx, s.Pool, `SELECT * FROM biz_event WHERE workspace_id=$1 AND ($2='' OR status=$2) ORDER BY occurred_at DESC LIMIT 300`, ws, r.URL.Query().Get("status"))
}

func (s *Service) postDecide(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	var in struct {
		Approve bool   `json:"approve"`
		Reason  string `json:"reason"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		return nil, invalid("Cuerpo no válido")
	}
	if !in.Approve && strings.TrimSpace(in.Reason) == "" {
		return nil, invalid("Rechazar exige motivo")
	}
	return s.DecideApproval(ctx, ws, a, chi.URLParam(r, "id"), in.Approve, in.Reason)
}

func (s *Service) postFolderExport(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	if a.Type != "member" {
		return nil, errf(403, "forbidden", "Solo una persona exporta la carpeta")
	}
	n, err := s.Folder.ExportAll(ctx, ws)
	return map[string]any{"journaled": n}, err
}

func (s *Service) postFolderRebuild(ctx context.Context, ws string, a Actor, r *http.Request) (any, error) {
	if a.Type != "member" || (a.Role != "owner" && a.Role != "admin") {
		return nil, errf(403, "forbidden", "Solo propietarios y administradores reconstruyen desde la carpeta")
	}
	var in struct {
		Apply bool `json:"apply"`
	}
	_ = json.NewDecoder(r.Body).Decode(&in)
	return s.Folder.Rebuild(ctx, ws, in.Apply)
}
