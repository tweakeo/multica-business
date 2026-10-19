package biz

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Actor is who is asking for a command. Members act through the UI; agents
// through the multica CLI with a task-scoped token; "system" is the event
// worker acting on a recorded fact.
type Actor struct {
	Type   string `json:"type"` // member | agent | system
	ID     string `json:"id"`
	UserID string `json:"user_id,omitempty"`
	TaskID string `json:"task_id,omitempty"`
	Role   string `json:"role,omitempty"` // workspace role for members
}

func (a Actor) idOrNil() any {
	if a.ID == "" {
		return nil
	}
	return a.ID
}

// Error carries an HTTP status so handlers can report domain failures
// precisely (validation 422, lock 423, forbidden 403, conflict 409).
type Error struct {
	Status int    `json:"-"`
	Code   string `json:"code"`
	Msg    string `json:"error"`
}

func (e *Error) Error() string { return e.Msg }

func errf(status int, code, format string, args ...any) *Error {
	return &Error{Status: status, Code: code, Msg: fmt.Sprintf(format, args...)}
}

func invalid(format string, args ...any) *Error {
	return errf(http.StatusUnprocessableEntity, "validation_failed", format, args...)
}

// Publisher pushes realtime invalidations to connected clients.
type Publisher func(workspaceID, eventType, actorType, actorID string, payload any)

// Hooks reach Multica's own services (projects, issues) without importing
// the handler package.
type Hooks struct {
	CreateProject func(ctx context.Context, ws string, p ProjectSpec) (string, error)
	CreateIssue   func(ctx context.Context, ws string, p IssueSpec) (string, error)
}

type ProjectSpec struct {
	Title, Description, Icon, Status string
	LeadType, LeadID                 string
	StartDate, DueDate               string
	WorkflowID                       string
}

type IssueSpec struct {
	Title, Description, Status, Priority string
	AssigneeType, AssigneeID            string
	ProjectID, ParentID                 string
	StartDate, DueDate                  string
	CreatorType, CreatorID              string
}

type Service struct {
	Pool    *pgxpool.Pool
	Publish Publisher
	Hooks   Hooks
	Folder  *Folder
	Log     *slog.Logger

	commands map[string]*Command
}

func NewService(pool *pgxpool.Pool, publish Publisher, hooks Hooks) *Service {
	s := &Service{Pool: pool, Publish: publish, Hooks: hooks, Log: slog.Default().With("component", "biz")}
	s.Folder = &Folder{svc: s}
	s.commands = map[string]*Command{}
	s.registerSales()
	s.registerFinance()
	s.registerDelivery()
	s.registerBrand()
	s.registerDirection()
	s.registerTeam()
	return s
}

// Command is one business mutation. Every write — from the UI, an agent or
// an approval being executed — goes through Run, so authorization, audit,
// events and the portable folder are applied uniformly.
type Command struct {
	Action     string
	Capability string
	Area       string
	// Sensitive reports whether this particular payload has external,
	// monetary, contractual or irreversible effects (§16).
	Sensitive func(p json.RawMessage) bool
	// Describe summarises the request for an approval card.
	Describe func(ctx context.Context, s *Service, ws string, p json.RawMessage) Description
	Exec     func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error)
}

type Description struct {
	Title      string   `json:"title"`
	Summary    string   `json:"summary"`
	EntityType string   `json:"entity_type"`
	EntityID   string   `json:"entity_id"`
	Effects    []Effect `json:"effects"`
}

// Effect is one before/after line shown to the approver.
type Effect struct {
	Field  string `json:"field"`
	Before string `json:"before"`
	After  string `json:"after"`
}

func always(bool) func(json.RawMessage) bool {
	return func(json.RawMessage) bool { return true }
}

func never(json.RawMessage) bool { return false }

func (s *Service) register(c *Command) {
	if c.Sensitive == nil {
		c.Sensitive = never
	}
	s.commands[c.Action] = c
}

// Actions lists registered commands for the API reference agents read.
func (s *Service) Actions() []map[string]any {
	out := make([]map[string]any, 0, len(s.commands))
	for _, c := range s.commands {
		out = append(out, map[string]any{"action": c.Action, "capability": c.Capability, "area": c.Area})
	}
	sort.Slice(out, func(i, j int) bool { return out[i]["action"].(string) < out[j]["action"].(string) })
	return out
}

// RunResult is either an executed result or a pending approval.
type RunResult struct {
	Status   string `json:"status"` // executed | approval_required
	Result   any    `json:"result,omitempty"`
	Approval any    `json:"approval,omitempty"`
}

func (s *Service) Run(ctx context.Context, ws string, a Actor, action string, payload json.RawMessage) (*RunResult, error) {
	cmd, ok := s.commands[action]
	if !ok {
		return nil, errf(http.StatusNotFound, "unknown_action", "acción desconocida: %s", action)
	}
	if len(payload) == 0 {
		payload = json.RawMessage(`{}`)
	}
	need, err := s.authorize(ctx, ws, a, cmd, payload)
	if err != nil {
		s.audit(ctx, s.Pool, ws, a, action, cmd.Capability, "", "", "", "denied", map[string]any{"reason": err.Error()})
		return nil, err
	}
	if need {
		appr, err := s.requestApproval(ctx, ws, a, cmd, payload)
		if err != nil {
			return nil, err
		}
		return &RunResult{Status: "approval_required", Approval: appr}, nil
	}
	res, err := s.execute(ctx, ws, a, cmd, payload, "")
	if err != nil {
		return nil, err
	}
	return &RunResult{Status: "executed", Result: res}, nil
}

func (s *Service) execute(ctx context.Context, ws string, a Actor, cmd *Command, payload json.RawMessage, approvalID string) (any, error) {
	var result any
	err := s.withTx(ctx, func(tx pgx.Tx) error {
		r, err := cmd.Exec(ctx, tx, s, ws, a, payload)
		if err != nil {
			return err
		}
		result = r
		entityType, entityID := resultEntity(r)
		s.audit(ctx, tx, ws, a, cmd.Action, cmd.Capability, entityType, entityID, approvalID, "ok", json.RawMessage(payload))
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.afterCommit(ws, a, cmd.Action, result)
	return result, nil
}

// afterCommit flushes folder writes and realtime invalidations. Both are
// recoverable: folder writes are journaled, clients refetch on reconnect.
func (s *Service) afterCommit(ws string, a Actor, action string, result any) {
	go s.Folder.FlushPending(context.Background(), ws)
	go s.ProcessEvents(context.Background())
	if s.Publish != nil {
		entityType, entityID := resultEntity(result)
		s.Publish(ws, "biz:changed", a.Type, a.ID, map[string]any{"action": action, "entity_type": entityType, "entity_id": entityID})
	}
}

func resultEntity(r any) (string, string) {
	if m, ok := r.(map[string]any); ok {
		t, _ := m["entity_type"].(string)
		id, _ := m["id"].(string)
		return t, id
	}
	return "", ""
}

func (s *Service) withTx(ctx context.Context, fn func(pgx.Tx) error) error {
	tx, err := s.Pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// --- Authorization -------------------------------------------------------

func (s *Service) Setting(ctx context.Context, q Querier, ws, key string) json.RawMessage {
	var v json.RawMessage
	if err := q.QueryRow(ctx, `SELECT value FROM biz_setting WHERE workspace_id=$1 AND key=$2`, ws, key).Scan(&v); err != nil {
		return nil
	}
	return v
}

func (s *Service) settingBool(ctx context.Context, q Querier, ws, key string) bool {
	var b bool
	_ = json.Unmarshal(s.Setting(ctx, q, ws, key), &b)
	return b
}

// KillSwitchOn is also consulted by the task claim path so no new agent run
// starts while the switch is on.
func (s *Service) KillSwitchOn(ctx context.Context, ws string) bool {
	return s.settingBool(ctx, s.Pool, ws, "kill_switch")
}

// AgentAreaPaused reports whether the agent's business area is paused.
func (s *Service) AgentAreaPaused(ctx context.Context, ws, agentID string) bool {
	var paused bool
	_ = s.Pool.QueryRow(ctx, `SELECT a.paused FROM biz_agent g JOIN biz_area a ON a.workspace_id=g.workspace_id AND a.code=g.area WHERE g.agent_id=$1 AND g.workspace_id=$2`, agentID, ws).Scan(&paused)
	return paused
}

func (s *Service) policyMode(ctx context.Context, ws, capability string, sensitive bool) (string, json.RawMessage) {
	var mode string
	var limits json.RawMessage
	if err := s.Pool.QueryRow(ctx, `SELECT mode, limits FROM biz_policy WHERE workspace_id=$1 AND capability=$2`, ws, capability).Scan(&mode, &limits); err == nil {
		return mode, limits
	}
	if sensitive {
		return "supervised", nil
	}
	return "assisted", nil
}

func (s *Service) authorize(ctx context.Context, ws string, a Actor, cmd *Command, payload json.RawMessage) (needsApproval bool, err error) {
	if s.settingBool(ctx, s.Pool, ws, "read_only") && cmd.Action != "settings.set" {
		return false, errf(http.StatusLocked, "read_only", "La empresa está en modo lectura: no se admiten cambios")
	}
	if a.Type == "member" {
		if (cmd.Action == "settings.set" || cmd.Action == "policy.set" || cmd.Action == "area.set") && a.Role != "owner" && a.Role != "admin" {
			return false, errf(http.StatusForbidden, "forbidden", "Solo propietarios y administradores cambian controles y políticas")
		}
		return false, nil
	}
	// Agents and automations from here on.
	if s.settingBool(ctx, s.Pool, ws, "kill_switch") {
		return false, errf(http.StatusLocked, "kill_switch", "Interruptor global activado: los agentes y automatismos no pueden escribir")
	}
	if a.Type == "system" {
		return false, nil
	}
	if cmd.Action == "settings.set" || cmd.Action == "policy.set" || cmd.Action == "area.set" || cmd.Action == "approval.decide" || cmd.Action == "agent.assign" {
		return false, errf(http.StatusForbidden, "forbidden", "Un agente no puede cambiar permisos, políticas ni decidir aprobaciones")
	}
	var area string
	var coordinator bool
	if err := s.Pool.QueryRow(ctx, `SELECT area, is_coordinator FROM biz_agent WHERE agent_id=$1 AND workspace_id=$2`, a.ID, ws).Scan(&area, &coordinator); err != nil {
		return false, errf(http.StatusForbidden, "agent_not_registered", "Este agente no tiene un área asignada en Empresa")
	}
	var paused bool
	_ = s.Pool.QueryRow(ctx, `SELECT paused FROM biz_area WHERE workspace_id=$1 AND code=$2`, ws, cmd.Area).Scan(&paused)
	if paused {
		return false, errf(http.StatusLocked, "area_paused", "El área %s está en pausa", cmd.Area)
	}
	if area != cmd.Area && !coordinator {
		return false, errf(http.StatusForbidden, "out_of_scope", "La acción %s pertenece al área %s y el agente es de %s", cmd.Action, cmd.Area, area)
	}
	sensitive := cmd.Sensitive(payload)
	mode, limits := s.policyMode(ctx, ws, cmd.Capability, sensitive)
	switch mode {
	case "off", "manual":
		return false, errf(http.StatusForbidden, "capability_manual", "La capacidad %s está en modo %s: solo la ejecuta una persona", cmd.Capability, mode)
	case "assisted", "supervised":
		return sensitive, nil
	case "autonomous":
		if sensitive && exceedsLimits(payload, limits) {
			return true, nil
		}
		return false, nil
	}
	return true, nil
}

// exceedsLimits applies an optional max_amount_minor ceiling for autonomous mode.
func exceedsLimits(payload, limits json.RawMessage) bool {
	var l struct {
		MaxAmountMinor *int64 `json:"max_amount_minor"`
	}
	if len(limits) == 0 || json.Unmarshal(limits, &l) != nil || l.MaxAmountMinor == nil {
		return false
	}
	var p struct {
		AmountMinor int64 `json:"amount_minor"`
	}
	_ = json.Unmarshal(payload, &p)
	return p.AmountMinor > *l.MaxAmountMinor
}

// --- Approvals -----------------------------------------------------------

func hashPayload(action string, p json.RawMessage) string {
	var v any
	_ = json.Unmarshal(p, &v)
	canon, _ := json.Marshal(v) // map keys are sorted by encoding/json
	sum := sha256.Sum256(append([]byte(action+"|"), canon...))
	return hex.EncodeToString(sum[:])
}

func (s *Service) entityVersion(ctx context.Context, q Querier, entityType, id string) *int {
	table, ok := entityTables[entityType]
	if !ok || id == "" {
		return nil
	}
	var v int
	if err := q.QueryRow(ctx, fmt.Sprintf(`SELECT version FROM %s WHERE id=$1`, table), id).Scan(&v); err != nil {
		return nil
	}
	return &v
}

func (s *Service) requestApproval(ctx context.Context, ws string, a Actor, cmd *Command, payload json.RawMessage) (json.RawMessage, error) {
	d := Description{Title: cmd.Action}
	if cmd.Describe != nil {
		d = cmd.Describe(ctx, s, ws, payload)
	}
	if d.Effects == nil {
		d.Effects = []Effect{}
	}
	effects, _ := json.Marshal(d.Effects)
	hash := hashPayload(cmd.Action, payload)
	var out json.RawMessage
	err := s.withTx(ctx, func(tx pgx.Tx) error {
		// A new request for the same action on the same entity replaces any
		// pending one: approving stale content must not be possible.
		if d.EntityID != "" {
			if _, err := tx.Exec(ctx, `UPDATE biz_approval SET status='invalidated', reason='Sustituida por una petición nueva', updated_at=now()
				WHERE workspace_id=$1 AND action=$2 AND entity_id=$3 AND status='pending' AND payload_hash<>$4`, ws, cmd.Action, d.EntityID, hash); err != nil {
				return err
			}
		}
		var existing string
		if err := tx.QueryRow(ctx, `SELECT id FROM biz_approval WHERE workspace_id=$1 AND payload_hash=$2 AND status='pending'`, ws, hash).Scan(&existing); err == nil {
			return tx.QueryRow(ctx, `SELECT to_jsonb(a) FROM biz_approval a WHERE id=$1`, existing).Scan(&out)
		}
		var entityID any
		if d.EntityID != "" {
			entityID = d.EntityID
		}
		var taskID any
		if a.TaskID != "" {
			taskID = a.TaskID
		}
		err := tx.QueryRow(ctx, `INSERT INTO biz_approval (workspace_id, capability, action, area, title, summary, entity_type, entity_id, entity_version,
				payload, payload_hash, effects, requested_by_type, requested_by_id, task_id, expires_at)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15, now() + interval '14 days')
			RETURNING to_jsonb(biz_approval.*)`,
			ws, cmd.Capability, cmd.Action, cmd.Area, d.Title, d.Summary, d.EntityType, entityID, s.entityVersion(ctx, tx, d.EntityType, d.EntityID),
			payload, hash, effects, a.Type, a.idOrNil(), taskID).Scan(&out)
		if err != nil {
			return err
		}
		var id string
		_ = json.Unmarshal(jsonField(out, "id"), &id)
		s.audit(ctx, tx, ws, a, "approval.requested", cmd.Capability, d.EntityType, d.EntityID, id, "pending", json.RawMessage(payload))
		return nil
	})
	if err != nil {
		return nil, err
	}
	if s.Publish != nil {
		s.Publish(ws, "biz:changed", a.Type, a.ID, map[string]any{"action": "approval.requested", "entity_type": "approval"})
	}
	return out, nil
}

// DecideApproval approves (and executes) or rejects. Executing re-checks the
// payload hash, the entity version and the global switches.
func (s *Service) DecideApproval(ctx context.Context, ws string, approver Actor, id string, approve bool, reason string) (json.RawMessage, error) {
	if approver.Type != "member" || (approver.Role != "owner" && approver.Role != "admin") {
		return nil, errf(http.StatusForbidden, "forbidden", "Solo propietarios y administradores deciden aprobaciones")
	}
	var action, status, hash, entityType string
	var entityID *string
	var entityVersion *int
	var payload json.RawMessage
	var requestedType string
	var requestedID *string
	err := s.Pool.QueryRow(ctx, `SELECT action, status, payload_hash, entity_type, entity_id::text, entity_version, payload, requested_by_type, requested_by_id::text
		FROM biz_approval WHERE id=$1 AND workspace_id=$2`, id, ws).Scan(&action, &status, &hash, &entityType, &entityID, &entityVersion, &payload, &requestedType, &requestedID)
	if err != nil {
		return nil, errf(http.StatusNotFound, "not_found", "Aprobación no encontrada")
	}
	if status != "pending" {
		return nil, errf(http.StatusConflict, "not_pending", "La aprobación ya está %s", status)
	}
	finish := func(newStatus, why string, result any) (json.RawMessage, error) {
		res, _ := json.Marshal(result)
		var out json.RawMessage
		err := s.Pool.QueryRow(ctx, `UPDATE biz_approval SET status=$3, decided_by=$4, decided_at=now(), reason=$5,
			executed_at=CASE WHEN $3='executed' THEN now() ELSE executed_at END, result=$6, updated_at=now()
			WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_approval.*)`, id, ws, newStatus, approver.UserID, why, res).Scan(&out)
		s.audit(ctx, s.Pool, ws, approver, "approval."+newStatus, "", entityType, deref(entityID), id, newStatus, map[string]any{"reason": why})
		if s.Publish != nil {
			s.Publish(ws, "biz:changed", approver.Type, approver.ID, map[string]any{"action": "approval." + newStatus, "entity_type": "approval", "entity_id": id})
		}
		return out, err
	}
	if !approve {
		return finish("rejected", reason, nil)
	}
	cmd := s.commands[action]
	if cmd == nil || hashPayload(action, payload) != hash {
		return finish("invalidated", "El contenido aprobado no coincide con el solicitado", nil)
	}
	if entityVersion != nil {
		if cur := s.entityVersion(ctx, s.Pool, entityType, deref(entityID)); cur == nil || *cur != *entityVersion {
			return finish("invalidated", "El registro cambió después de pedir la aprobación", nil)
		}
	}
	if s.settingBool(ctx, s.Pool, ws, "read_only") {
		return nil, errf(http.StatusLocked, "read_only", "Modo lectura activo")
	}
	if requestedType == "agent" && s.settingBool(ctx, s.Pool, ws, "kill_switch") {
		return nil, errf(http.StatusLocked, "kill_switch", "Interruptor global activado: no se ejecutan peticiones de agentes")
	}
	// Executed as the approver; the audit row links back to the requester.
	result, err := s.execute(ctx, ws, approver, cmd, payload, id)
	if err != nil {
		_, _ = finish("failed", err.Error(), map[string]any{"error": err.Error()})
		return nil, err
	}
	return finish("executed", reason, result)
}

// --- Audit and events ----------------------------------------------------

func (s *Service) audit(ctx context.Context, q Querier, ws string, a Actor, action, capability, entityType, entityID, approvalID, result string, details any) {
	d, _ := json.Marshal(details)
	if len(d) == 0 || string(d) == "null" {
		d = []byte(`{}`)
	}
	var eid, aid any
	if entityID != "" {
		eid = entityID
	}
	if approvalID != "" {
		aid = approvalID
	}
	if _, err := q.Exec(ctx, `INSERT INTO biz_audit (workspace_id, actor_type, actor_id, action, capability, entity_type, entity_id, approval_id, result, details)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`, ws, a.Type, a.idOrNil(), action, capability, entityType, eid, aid, result, redact(d)); err != nil {
		s.Log.Warn("biz audit insert failed", "error", err)
	}
}

// redact drops obvious secrets from audit details.
func redact(d []byte) []byte {
	var m map[string]any
	if json.Unmarshal(d, &m) != nil {
		return d
	}
	for k := range m {
		switch k {
		case "password", "token", "secret", "api_key", "iban":
			m[k] = "[redacted]"
		}
	}
	out, _ := json.Marshal(m)
	return out
}

// Emit records a business event in the outbox inside the caller's transaction.
func (s *Service) Emit(ctx context.Context, tx pgx.Tx, ws, typ, entityType, entityID, idempotencyKey string, payload any) error {
	p, _ := json.Marshal(payload)
	var eid any
	if entityID != "" {
		eid = entityID
	}
	_, err := tx.Exec(ctx, `INSERT INTO biz_event (workspace_id, type, entity_type, entity_id, idempotency_key, payload)
		VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (workspace_id, idempotency_key) DO NOTHING`, ws, typ, entityType, eid, idempotencyKey, p)
	return err
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

func jsonField(raw json.RawMessage, key string) json.RawMessage {
	var m map[string]json.RawMessage
	if json.Unmarshal(raw, &m) != nil {
		return nil
	}
	return m[key]
}

func decode[T any](p json.RawMessage) (T, error) {
	var v T
	if err := json.Unmarshal(p, &v); err != nil {
		return v, invalid("Datos no válidos: %v", err)
	}
	return v, nil
}

func today() time.Time {
	loc, err := time.LoadLocation("Europe/Madrid")
	if err != nil {
		loc = time.UTC
	}
	n := time.Now().In(loc)
	return time.Date(n.Year(), n.Month(), n.Day(), 0, 0, 0, 0, time.UTC)
}

var errNotFound = errors.New("not found")
