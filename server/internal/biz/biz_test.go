package biz

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// --- Pure helpers ------------------------------------------------------------

func TestParseAmountNeverUsesFloats(t *testing.T) {
	cases := map[string]int64{
		"1.234,56": 123456, "-80,00": -8000, "0,1": 10, "181,50": 18150, "1234.56": 123456, "+3400,00": 340000, "-0,01": -1, "12": 1200,
	}
	for in, want := range cases {
		got, err := parseAmount(in)
		if err != nil || got != want {
			t.Errorf("parseAmount(%q) = %d, %v; want %d", in, got, err, want)
		}
	}
	for _, bad := range []string{"", "1,234", "abc", "1,2,3"} {
		if _, err := parseAmount(bad); err == nil && bad != "1,2,3" {
			t.Errorf("parseAmount(%q) should fail", bad)
		}
	}
}

func TestRoundBPHalfUp(t *testing.T) {
	if got := roundBP(15000, 2100); got != 3150 {
		t.Fatalf("21%% of 150,00 = %d", got)
	}
	if got := roundBP(333, 2100); got != 70 { // 69,93 → 70
		t.Fatalf("rounding: %d", got)
	}
	if got := roundBP(-333, 2100); got != -70 {
		t.Fatalf("negative rounding: %d", got)
	}
}

func TestValidateStageRules(t *testing.T) {
	if err := validateStage("ganada", "o", "s", true, ""); err == nil {
		t.Error("ganada must be reserved for confirmed payment")
	}
	if err := validateStage("cualificacion", "", "", false, ""); err == nil {
		t.Error("cualificacion needs an owner")
	}
	if err := validateStage("diagnostico", "o", "", false, ""); err == nil {
		t.Error("diagnostico needs a service")
	}
	if err := validateStage("negociacion", "o", "s", false, ""); err == nil {
		t.Error("negociacion needs a proposal")
	}
	if err := validateStage("perdida", "o", "s", false, " "); err == nil {
		t.Error("perdida needs a reason")
	}
	if err := validateStage("negociacion", "o", "s", true, ""); err != nil {
		t.Errorf("valid move refused: %v", err)
	}
}

func TestCapabilityCatalogIsComplete(t *testing.T) {
	per := map[string]int{}
	seen := map[string]bool{}
	for _, c := range Capabilities {
		if seen[c.Code] {
			t.Errorf("duplicate capability %s", c.Code)
		}
		seen[c.Code] = true
		per[c.Area]++
		for _, dep := range c.Requires {
			if _, ok := CapabilityByCode(dep); !ok {
				t.Errorf("%s requires unknown %s", c.Code, dep)
			}
		}
	}
	want := map[string]int{"direccion": 13, "ventas": 15, "entrega": 13, "finanzas": 12, "marca": 12, "equipo": 13}
	for a, n := range want {
		if per[a] != n {
			t.Errorf("area %s has %d capabilities, want %d", a, per[a], n)
		}
	}
	if len(Capabilities) != 78 {
		t.Errorf("catalog has %d capabilities, want 78", len(Capabilities))
	}
}

func TestAddWorkdaysSkipsWeekends(t *testing.T) {
	fri := time.Date(2026, 10, 16, 0, 0, 0, 0, time.UTC)
	if got := addWorkdays(fri, 1); got.Weekday() != time.Monday {
		t.Fatalf("Friday + 1 workday = %s", got.Weekday())
	}
	sat := time.Date(2026, 10, 17, 0, 0, 0, 0, time.UTC)
	if got := addWorkdays(sat, 0); got.Weekday() != time.Monday {
		t.Fatalf("a Saturday start rolls to Monday, got %s", got.Weekday())
	}
}

func TestRenderParseRoundTripKeepsUnknownFields(t *testing.T) {
	row := map[string]any{"id": "11111111-1111-1111-1111-111111111111", "name": "Panadería", "notes": "Texto humano\nlibre", "kind": "client",
		"attrs": map[string]any{"campo_externo": "se conserva"}}
	data, err := render("organization", row)
	if err != nil {
		t.Fatal(err)
	}
	rec, err := parseRecord("x.md", data)
	if err != nil {
		t.Fatal(err)
	}
	if rec.ID != "11111111-1111-1111-1111-111111111111" || rec.Type != "organization" || rec.Body != "Texto humano\nlibre" || rec.Front["campo_externo"] != "se conserva" {
		t.Fatalf("round trip lost data: %+v", rec)
	}
}

// --- Database-backed scenarios ------------------------------------------------
// They use DATABASE_URL and a random workspace id (biz tables carry no foreign
// keys), so they never touch real companies. Skipped without a database.

type fixture struct {
	t        *testing.T
	s        *Service
	ws       string
	projects int32
	issues   int32
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	url := os.Getenv("DATABASE_URL")
	if url == "" {
		t.Skip("DATABASE_URL not set")
	}
	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Skip("database unavailable")
	}
	if err := pool.Ping(context.Background()); err != nil {
		t.Skip("database unavailable")
	}
	f := &fixture{t: t, ws: uuid.NewString()}
	f.s = NewService(pool, nil, Hooks{
		CreateProject: func(ctx context.Context, ws string, p ProjectSpec) (string, error) {
			atomic.AddInt32(&f.projects, 1)
			return uuid.NewString(), nil
		},
		CreateIssue: func(ctx context.Context, ws string, p IssueSpec) (string, error) {
			atomic.AddInt32(&f.issues, 1)
			return uuid.NewString(), nil
		},
	})
	t.Cleanup(func() {
		for _, table := range []string{"biz_setting", "biz_area", "biz_role", "biz_agent", "biz_service", "biz_offer_version", "biz_organization", "biz_contact",
			"biz_opportunity", "biz_invoice", "biz_payment", "biz_bank_account", "biz_bank_movement", "biz_period", "biz_kpi", "biz_objective", "biz_decision",
			"biz_content", "biz_conversation", "biz_routine", "biz_policy", "biz_approval", "biz_event", "biz_audit", "biz_document", "biz_journal", "biz_project_link"} {
			_, _ = pool.Exec(context.Background(), "DELETE FROM "+table+" WHERE workspace_id=$1", f.ws)
		}
		pool.Close()
	})
	if err := f.s.EnsureBootstrap(context.Background(), f.ws); err != nil {
		t.Fatal(err)
	}
	return f
}

var owner = Actor{Type: "member", ID: "00000000-0000-0000-0000-0000000000aa", UserID: "00000000-0000-0000-0000-0000000000aa", Role: "owner"}

func (f *fixture) run(a Actor, action string, payload any) (*RunResult, error) {
	b, _ := json.Marshal(payload)
	return f.s.Run(context.Background(), f.ws, a, action, b)
}

func (f *fixture) must(a Actor, action string, payload any) map[string]any {
	f.t.Helper()
	res, err := f.run(a, action, payload)
	if err != nil {
		f.t.Fatalf("%s: %v", action, err)
	}
	m, _ := res.Result.(map[string]any)
	return m
}

func (f *fixture) service(code string, price int64) string {
	svc := f.must(owner, "service.save", map[string]any{"code": code, "name": code, "recurrence": "quarterly",
		"template": map[string]any{"phases": []any{map[string]any{"name": "Fase", "tasks": []any{map[string]any{"title": "Tarea", "offset": 0, "duration": 1}}}}}})
	f.must(owner, "offer.version", map[string]any{"service_id": svc["id"], "price_minor": price, "tax_rate_bp": 2100})
	return svc["id"].(string)
}

func (f *fixture) agent(area string) Actor {
	id := uuid.NewString()
	if _, err := f.s.Pool.Exec(context.Background(), `INSERT INTO biz_agent (agent_id, workspace_id, area) VALUES ($1,$2,$3)`, id, f.ws, area); err != nil {
		f.t.Fatal(err)
	}
	return Actor{Type: "agent", ID: id, TaskID: uuid.NewString()}
}

func errCode(err error) string {
	var e *Error
	if errors.As(err, &e) {
		return e.Code
	}
	return ""
}

func TestAgentPolicyEnforcement(t *testing.T) {
	f := newFixture(t)
	f.service("TRIM", 15000)
	sales := f.agent("ventas")
	lead := f.must(owner, "lead.create", map[string]any{"contact": map[string]any{"name": "Ana"}, "channel": "web", "service_code": "TRIM"})
	oppID := lead["id"].(string)

	// Internal write inside its own area: allowed in the default assisted mode.
	if _, err := f.run(sales, "contact.touch", map[string]any{"opportunity_id": oppID, "summary": "Llamada"}); err != nil {
		t.Fatalf("assisted internal write refused: %v", err)
	}
	// Another area's action: denied.
	if _, err := f.run(sales, "invoice.draft", map[string]any{"opportunity_id": oppID}); errCode(err) != "out_of_scope" {
		t.Fatalf("out-of-area action: got %v", err)
	}
	// Sensitive action: becomes an approval, not an execution.
	res, err := f.run(sales, "message.send", map[string]any{"opportunity_id": oppID, "to": "ana@example.com", "subject": "Hola", "body": "Texto"})
	if err != nil || res.Status != "approval_required" {
		t.Fatalf("sensitive action must require approval: %+v %v", res, err)
	}
	// Permission changes are never available to agents.
	if _, err := f.run(sales, "policy.set", map[string]any{"capability": "VEN-08", "mode": "autonomous"}); errCode(err) != "forbidden" {
		t.Fatalf("agent changed a policy: %v", err)
	}
	// Manual mode: the agent cannot run the capability at all.
	f.must(owner, "policy.set", map[string]any{"capability": "VEN-08", "mode": "manual"})
	if _, err := f.run(sales, "contact.touch", map[string]any{"opportunity_id": oppID, "summary": "x"}); errCode(err) != "capability_manual" {
		t.Fatalf("manual mode not enforced: %v", err)
	}
	f.must(owner, "policy.set", map[string]any{"capability": "VEN-08", "mode": "assisted"})
	// Area pause and global kill switch block agent writes; people continue.
	f.must(owner, "area.set", map[string]any{"code": "ventas", "paused": true})
	if _, err := f.run(sales, "contact.touch", map[string]any{"opportunity_id": oppID, "summary": "x"}); errCode(err) != "area_paused" {
		t.Fatalf("area pause not enforced: %v", err)
	}
	f.must(owner, "area.set", map[string]any{"code": "ventas", "paused": false})
	f.must(owner, "settings.set", map[string]any{"key": "kill_switch", "value": true})
	if _, err := f.run(sales, "contact.touch", map[string]any{"opportunity_id": oppID, "summary": "x"}); errCode(err) != "kill_switch" {
		t.Fatalf("kill switch not enforced: %v", err)
	}
	if !f.s.KillSwitchOn(context.Background(), f.ws) {
		t.Fatal("claim gate would not see the kill switch")
	}
	if _, err := f.run(owner, "contact.touch", map[string]any{"opportunity_id": oppID, "summary": "Persona sigue"}); err != nil {
		t.Fatalf("people must keep working under the kill switch: %v", err)
	}
	f.must(owner, "settings.set", map[string]any{"key": "kill_switch", "value": false})
	// Read-only mode blocks everyone.
	f.must(owner, "settings.set", map[string]any{"key": "read_only", "value": true})
	if _, err := f.run(owner, "contact.touch", map[string]any{"opportunity_id": oppID, "summary": "x"}); errCode(err) != "read_only" {
		t.Fatalf("read-only not enforced: %v", err)
	}
	f.must(owner, "settings.set", map[string]any{"key": "read_only", "value": false})
}

func TestApprovalInvalidatedWhenContentOrRecordChanges(t *testing.T) {
	f := newFixture(t)
	f.service("TRIM", 15000)
	sales := f.agent("ventas")
	opp := f.must(owner, "lead.create", map[string]any{"contact": map[string]any{"name": "Ana", "email": "ana@x.es"}, "channel": "web", "service_code": "TRIM"})
	send := func(body string) map[string]any {
		res, err := f.run(sales, "message.send", map[string]any{"opportunity_id": opp["id"], "to": "ana@x.es", "subject": "Hola", "body": body})
		if err != nil || res.Status != "approval_required" {
			t.Fatalf("expected approval: %v", err)
		}
		var m map[string]any
		b, _ := json.Marshal(res.Approval)
		_ = json.Unmarshal(b, &m)
		return m
	}
	first := send("Versión 1")
	second := send("Versión 2 (cambia el contenido)")
	var status string
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT status FROM biz_approval WHERE id=$1`, first["id"]).Scan(&status)
	if status != "invalidated" {
		t.Fatalf("changing content must invalidate the earlier approval, got %s", status)
	}
	// The record changes after the request: approving now must not execute.
	f.must(owner, "contact.touch", map[string]any{"opportunity_id": opp["id"], "summary": "Cambio posterior"})
	out, err := f.s.DecideApproval(context.Background(), f.ws, owner, second["id"].(string), true, "")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(out), `"invalidated"`) {
		t.Fatalf("stale approval executed: %s", out)
	}
	// Agents cannot decide approvals.
	if _, err := f.s.DecideApproval(context.Background(), f.ws, sales, second["id"].(string), true, ""); err == nil {
		t.Fatal("an agent decided an approval")
	}
}

func TestPaymentConfirmationCreatesExactlyOneProject(t *testing.T) {
	f := newFixture(t)
	f.service("TRIM", 15000)
	opp := f.must(owner, "lead.create", map[string]any{"contact": map[string]any{"name": "Ana"}, "organization": map[string]any{"name": "Taller SL"}, "channel": "web", "service_code": "TRIM"})
	id := opp["id"].(string)
	f.must(owner, "opportunity.move", map[string]any{"id": id, "stage": "cualificacion"})
	f.must(owner, "opportunity.proposal", map[string]any{"id": id})
	// Commercial acceptance never means "won": that needs the money.
	if _, err := f.run(owner, "opportunity.move", map[string]any{"id": id, "stage": "ganada"}); err == nil {
		t.Fatal("moved to ganada without payment")
	}
	f.must(owner, "opportunity.accept", map[string]any{"id": id, "evidence": "Correo de aceptación"})
	f.s.ProcessEvents(context.Background())
	var invoiceID string
	var total int64
	if err := f.s.Pool.QueryRow(context.Background(), `SELECT id, total_minor FROM biz_invoice WHERE opportunity_id=$1`, id).Scan(&invoiceID, &total); err != nil {
		t.Fatalf("draft invoice not created from acceptance: %v", err)
	}
	if total != 18150 {
		t.Fatalf("invoice total from proposal snapshot = %d, want 18150", total)
	}
	// Changing the current price does not touch the accepted snapshot.
	var serviceID string
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT service_id FROM biz_opportunity WHERE id=$1`, id).Scan(&serviceID)
	f.must(owner, "offer.version", map[string]any{"service_id": serviceID, "price_minor": 20000})
	var after int64
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT total_minor FROM biz_invoice WHERE id=$1`, invoiceID).Scan(&after)
	if after != 18150 {
		t.Fatal("new offer version changed an existing invoice")
	}
	f.must(owner, "invoice.issue", map[string]any{"id": invoiceID})
	if _, err := f.run(owner, "payment.confirm", map[string]any{"invoice_id": invoiceID, "amount_minor": total}); err == nil {
		t.Fatal("payment confirmed without movement or evidence")
	}
	f.must(owner, "payment.confirm", map[string]any{"invoice_id": invoiceID, "amount_minor": total, "evidence": "Transferencia ref. 123"})
	f.s.ProcessEvents(context.Background())
	// Redeliver every event of this workspace: no second project.
	if _, err := f.s.Pool.Exec(context.Background(), `UPDATE biz_event SET status='pending', next_attempt_at=now() WHERE workspace_id=$1`, f.ws); err != nil {
		t.Fatal(err)
	}
	f.s.ProcessEvents(context.Background())
	f.s.ProcessEvents(context.Background())
	if n := atomic.LoadInt32(&f.projects); n != 1 {
		t.Fatalf("projects created = %d, want exactly 1", n)
	}
	var stage string
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT stage FROM biz_opportunity WHERE id=$1`, id).Scan(&stage)
	if stage != "ganada" {
		t.Fatalf("stage after payment = %s", stage)
	}
	// Emitting the same fact twice is a no-op by idempotency key.
	var events int
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT count(*) FROM biz_event WHERE workspace_id=$1 AND type='cobro.confirmado'`, f.ws).Scan(&events)
	if events != 1 {
		t.Fatalf("cobro.confirmado events = %d", events)
	}
}

func TestBankImportIsIdempotentAndUnknownBalanceStaysUnknown(t *testing.T) {
	f := newFixture(t)
	acc := f.must(owner, "account.create", map[string]any{"name": "Cuenta sin saldo"})
	if v, _ := f.s.cash(context.Background(), f.ws); v != nil {
		t.Fatalf("unknown balance reported as %v", *v)
	}
	csv := "fecha;fecha_valor;concepto;importe;saldo\n01/10/2026;01/10/2026;RECIBO ALQUILER;-663,00;\n02/10/2026;02/10/2026;TRASPASO A AHORRO;-1.000,00;\n"
	first := f.must(owner, "bank.import", map[string]any{"account_id": acc["id"], "csv": csv})
	second := f.must(owner, "bank.import", map[string]any{"account_id": acc["id"], "csv": csv})
	if first["inserted"] != 2 || second["inserted"] != 0 || second["duplicates"] != 2 {
		t.Fatalf("re-import duplicated movements: %v / %v", first, second)
	}
	var nature string
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT nature FROM biz_bank_movement WHERE workspace_id=$1 AND description LIKE 'TRASPASO%'`, f.ws).Scan(&nature)
	if nature != "internal_transfer" {
		t.Fatalf("internal transfer classified as %s", nature)
	}
	if v, _ := f.s.cash(context.Background(), f.ws); v != nil {
		t.Fatalf("cash without opening balance or bank balance must stay unknown, got %v", *v)
	}
	if _, err := f.run(owner, "bank.import", map[string]any{"account_id": uuid.NewString(), "csv": csv}); err == nil {
		t.Fatal("movement accepted without a valid account (FIN-01)")
	}
}

func TestPeriodRequiresEvidenceAndKeepsHistory(t *testing.T) {
	f := newFixture(t)
	p := f.must(owner, "period.prepare", map[string]any{"year": 2026, "quarter": 3})
	id := p["id"].(string)
	f.must(owner, "period.transition", map[string]any{"id": id, "to": "approved"})
	if _, err := f.run(owner, "period.transition", map[string]any{"id": id, "to": "sent"}); err == nil {
		t.Fatal("marked as sent without evidence")
	}
	if _, err := f.run(owner, "period.transition", map[string]any{"id": id, "to": "filed", "evidence": "x"}); err == nil {
		t.Fatal("skipped a state")
	}
	f.must(owner, "period.transition", map[string]any{"id": id, "to": "sent", "evidence": "Correo a la asesora 20/10"})
	f.must(owner, "period.transition", map[string]any{"id": id, "to": "open", "reason": "Falta una factura"})
	var history json.RawMessage
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT history FROM biz_period WHERE id=$1`, id).Scan(&history)
	if !strings.Contains(string(history), "Falta una factura") {
		t.Fatalf("reopen reason not kept: %s", history)
	}
}

func TestFolderRebuildRestoresProjectionFieldByField(t *testing.T) {
	f := newFixture(t)
	dir := t.TempDir()
	f.must(owner, "settings.set", map[string]any{"key": "company_folder", "value": dir})
	f.service("RENTA", 9000)
	lead := f.must(owner, "lead.create", map[string]any{"contact": map[string]any{"name": "Lucía", "email": "l@x.es"}, "organization": map[string]any{"name": "Ferrer SL", "tax_id": "B1"}, "channel": "referido", "service_code": "RENTA", "notes": "Nota humana"})
	f.must(owner, "decision.create", map[string]any{"area": "direccion", "title": "Política", "decision": "Cobrar antes", "why": "Caja", "purpose": "Foco"})
	if _, err := f.s.Folder.ExportAll(context.Background(), f.ws); err != nil {
		t.Fatal(err)
	}
	before, _ := rowMap(context.Background(), f.s.Pool, "opportunity", lead["id"].(string))
	// An external, human edit with an unknown field must survive.
	matches, _ := filepath.Glob(filepath.Join(dir, "Ventas", "Organizaciones", "*.md"))
	if len(matches) != 1 {
		t.Fatalf("organization files: %v", matches)
	}
	data, _ := os.ReadFile(matches[0])
	edited := strings.Replace(string(data), "tls_schema: 1\n", "tls_schema: 1\ncampo_externo: añadido a mano\n", 1)
	_ = os.WriteFile(matches[0], []byte(edited), 0o644)
	status, _ := f.s.Folder.Status(context.Background(), f.ws)
	if mod, _ := status["modified_externally"].([]map[string]string); len(mod) != 1 {
		t.Fatalf("external edit not detected: %v", status["modified_externally"])
	}
	// Drop the projection rows (the rebuildable index) and rebuild from disk.
	for _, table := range []string{"biz_organization", "biz_contact", "biz_opportunity", "biz_decision"} {
		_, _ = f.s.Pool.Exec(context.Background(), "DELETE FROM "+table+" WHERE workspace_id=$1", f.ws)
	}
	res, err := f.s.Folder.Rebuild(context.Background(), f.ws, true)
	if err != nil {
		t.Fatal(err)
	}
	if res["applied"].(int) < 4 {
		t.Fatalf("rebuild applied %v", res["applied"])
	}
	after, err := rowMap(context.Background(), f.s.Pool, "opportunity", lead["id"].(string))
	if err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"title", "stage", "value_minor", "channel", "notes", "contact_id", "organization_id", "service_id", "version"} {
		if canon(before[k]) != canon(after[k]) {
			t.Errorf("field %s: before %v after %v", k, before[k], after[k])
		}
	}
	var attrs json.RawMessage
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT attrs FROM biz_organization WHERE workspace_id=$1`, f.ws).Scan(&attrs)
	if !strings.Contains(string(attrs), "añadido a mano") {
		t.Fatalf("unknown field lost: %s", attrs)
	}
	preview, _ := f.s.Folder.Rebuild(context.Background(), f.ws, false)
	if len(preview["missing_in_db"].([]map[string]any)) != 0 {
		t.Fatalf("records still missing after rebuild: %v", preview["missing_in_db"])
	}
	// Two files with the same id are a visible conflict, not a silent overwrite.
	_ = os.WriteFile(filepath.Join(dir, "copia.md"), []byte(edited), 0o644)
	status, _ = f.s.Folder.Status(context.Background(), f.ws)
	if d, _ := status["duplicate_ids"].([]map[string]any); len(d) != 1 {
		t.Fatalf("duplicate id not reported: %v", status["duplicate_ids"])
	}
}

func TestDecisionsAreAppendOnly(t *testing.T) {
	f := newFixture(t)
	d := f.must(owner, "decision.create", map[string]any{"area": "direccion", "title": "Precio", "decision": "90 €", "why": "Coste", "purpose": "Margen"})
	n := f.must(owner, "decision.supersede", map[string]any{"id": d["id"], "decision": "95 €", "why": "Coste real", "purpose": "Margen"})
	var old string
	_ = f.s.Pool.QueryRow(context.Background(), `SELECT status FROM biz_decision WHERE id=$1`, d["id"]).Scan(&old)
	if old != "superseded" || n["supersedes_id"] != d["id"] {
		t.Fatalf("correction did not keep the earlier decision: %s %v", old, n["supersedes_id"])
	}
	agent := f.agent("direccion")
	if _, err := f.run(agent, "decision.decide", map[string]any{"id": n["id"], "decision": "x", "why": "y", "purpose": "z"}); err == nil {
		t.Fatal("an agent took a decision")
	}
	_ = http.StatusOK
}
