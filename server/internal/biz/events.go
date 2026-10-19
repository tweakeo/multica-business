package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
)

var processMu sync.Mutex

type eventRow struct {
	ID, WS, Type, EntityType, EntityID string
	Payload                            json.RawMessage
	Attempts                           int
}

// ProcessEvents drains due events. Delivery is at-least-once: every handler
// is idempotent (unique links, existence checks, idempotency keys).
func (s *Service) ProcessEvents(ctx context.Context) {
	if !processMu.TryLock() {
		return
	}
	defer processMu.Unlock()
	for i := 0; i < 20; i++ {
		batch, err := s.claimEvents(ctx)
		if err != nil {
			s.Log.Warn("biz events claim failed", "error", err)
			return
		}
		if len(batch) == 0 {
			return
		}
		for _, e := range batch {
			err := s.handleEvent(ctx, e)
			if err == nil {
				_, _ = s.Pool.Exec(ctx, `UPDATE biz_event SET status='processed', processed_at=now(), leased_until=NULL, last_error='' WHERE id=$1`, e.ID)
				continue
			}
			status := "failed"
			if e.Attempts >= 8 {
				status = "dead"
			}
			backoff := time.Duration(math.Min(math.Pow(2, float64(e.Attempts))*10, 3600)) * time.Second
			_, _ = s.Pool.Exec(ctx, `UPDATE biz_event SET status=$2, last_error=$3, next_attempt_at=now()+$4::interval, leased_until=NULL WHERE id=$1`,
				e.ID, status, err.Error(), fmt.Sprintf("%d seconds", int(backoff.Seconds())))
			s.Log.Warn("biz event failed", "type", e.Type, "attempt", e.Attempts, "error", err)
		}
	}
}

func (s *Service) claimEvents(ctx context.Context) ([]eventRow, error) {
	rows, err := s.Pool.Query(ctx, `UPDATE biz_event SET status='processing', attempts=attempts+1, leased_until=now()+interval '2 minutes'
		WHERE id IN (SELECT id FROM biz_event WHERE (status IN ('pending','failed') AND next_attempt_at<=now()) OR (status='processing' AND leased_until<now())
			ORDER BY occurred_at LIMIT 10 FOR UPDATE SKIP LOCKED)
		RETURNING id, workspace_id, type, entity_type, coalesce(entity_id::text,''), payload, attempts`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []eventRow
	for rows.Next() {
		var e eventRow
		if err := rows.Scan(&e.ID, &e.WS, &e.Type, &e.EntityType, &e.EntityID, &e.Payload, &e.Attempts); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Service) handleEvent(ctx context.Context, e eventRow) error {
	var p map[string]any
	_ = json.Unmarshal(e.Payload, &p)
	defer func() {
		if s.Publish != nil {
			s.Publish(e.WS, "biz:changed", "system", "", map[string]any{"action": "event." + e.Type})
		}
	}()
	switch e.Type {
	case "contacto.creado":
		if dup, _ := p["duplicate_contact"].(bool); dup {
			return nil
		}
		return s.onLeadCreated(ctx, e.WS, str(p["opportunity_id"]), e.ID)
	case "oportunidad.aceptada":
		return s.onOpportunityAccepted(ctx, e.WS, e.EntityID, e.ID)
	case "cobro.confirmado":
		if err := s.createProjectFromPayment(ctx, e.WS, str(p["opportunity_id"]), str(p["invoice_id"])); err != nil {
			return err
		}
		go s.ProcessEvents(context.Background())
		return nil
	case "proyecto.creado":
		return s.materializeProject(ctx, e.WS, str(p["project_id"]))
	case "proyecto.cerrado":
		return s.onProjectClosed(ctx, e.WS, e.EntityID, e.ID)
	case "periodo.preparado":
		year, quarter := int(num(p["year"])), int(num(p["quarter"]))
		return s.Folder.WritePeriodPackage(ctx, e.WS, year, quarter)
	case "ritual":
		return s.onRitual(ctx, e.WS, p, e.ID)
	}
	return nil
}

// agentTask creates a Multica task for an area agent (or unassigned when the
// agent cannot run now). The origin is recorded so the run is traceable to
// the business event.
func (s *Service) agentTask(ctx context.Context, ws, area, title, body, projectID string) error {
	// Importing history never re-triggers business effects (§19).
	if s.settingBool(ctx, s.Pool, ws, "import_mode") {
		return nil
	}
	agentID, ok := s.agentAvailable(ctx, ws, area)
	spec := IssueSpec{Title: title, Description: body, Status: "todo", Priority: "medium", ProjectID: projectID,
		StartDate: today().Format("2006-01-02"), DueDate: addWorkdays(today(), 2).Format("2006-01-02")}
	if ok {
		spec.AssigneeType, spec.AssigneeID = "agent", agentID
	} else if agentID != "" {
		spec.Description += "\n\n> No se asignó al agente porque el interruptor global o la pausa del área están activos."
	}
	_, err := s.Hooks.CreateIssue(ctx, ws, spec)
	return err
}

// alreadyDone makes side effects of an event idempotent across redelivery.
func (s *Service) alreadyDone(ctx context.Context, ws, key string) bool {
	tag, err := s.Pool.Exec(ctx, `INSERT INTO biz_setting (workspace_id, key, value) VALUES ($1, $2, 'true'::jsonb) ON CONFLICT DO NOTHING`, ws, "done:"+key)
	return err == nil && tag.RowsAffected() == 0
}

func (s *Service) onLeadCreated(ctx context.Context, ws, oppID, eventID string) error {
	if oppID == "" || s.alreadyDone(ctx, ws, "lead-task:"+oppID) {
		return nil
	}
	var title, contact, org, channel, service string
	_ = s.Pool.QueryRow(ctx, `SELECT o.title, coalesce(c.name,''), coalesce(org.name,''), o.channel, coalesce(sv.name,'')
		FROM biz_opportunity o LEFT JOIN biz_contact c ON c.id=o.contact_id LEFT JOIN biz_organization org ON org.id=o.organization_id
		LEFT JOIN biz_service sv ON sv.id=o.service_id WHERE o.id=$1`, oppID).Scan(&title, &contact, &org, &channel, &service)
	body := fmt.Sprintf(`Nuevo interesado entrado por **%s**.

- Contacto: %s
- Empresa: %s
- Servicio de interés: %s
- Oportunidad: %s

**Qué hacer (VEN-10, VEN-11):**
1. Lee la oportunidad: `+"`multica biz get /record/opportunity/%s`"+`
2. Valora el encaje con el cliente ideal de la gestoría y anota el resultado con `+"`contact.touch`"+` (resumen, siguiente acción y fecha).
3. Si encaja, pásala a cualificación (`+"`opportunity.move`"+` → cualificacion) y redacta el primer mensaje con `+"`message.send`"+`: quedará pendiente de aprobación humana.
4. Si no encaja, explica el motivo en el comentario final y no la muevas.

No inventes datos del interesado que no estén en la ficha.`, channel, contact, org, service, title, oppID)
	return s.agentTask(ctx, ws, "ventas", "Cualificar interesado: "+title, body, "")
}

func (s *Service) onOpportunityAccepted(ctx context.Context, ws, oppID, eventID string) error {
	var invoiceID string
	err := s.withTx(ctx, func(tx pgx.Tx) error {
		res, err := s.draftInvoiceFromOpportunity(ctx, tx, ws, oppID)
		if err != nil {
			return err
		}
		invoiceID = str(res["id"])
		s.audit(ctx, tx, ws, Actor{Type: "system"}, "invoice.draft", "FIN-02", "invoice", invoiceID, "", "ok", map[string]any{"from_event": eventID})
		return nil
	})
	if err != nil {
		return err
	}
	go s.Folder.FlushPending(context.Background(), ws)
	if s.alreadyDone(ctx, ws, "invoice-task:"+oppID) {
		return nil
	}
	var title string
	_ = s.Pool.QueryRow(ctx, `SELECT title FROM biz_opportunity WHERE id=$1`, oppID).Scan(&title)
	body := fmt.Sprintf(`La propuesta «%s» ha sido aceptada. Hay una factura en borrador preparada desde la instantánea de la propuesta.

**Qué hacer (FIN-02, FIN-03):**
1. Revisa el borrador: `+"`multica biz get /record/invoice/%s`"+`
2. Comprueba cliente, concepto e importes contra la propuesta aceptada.
3. Pide la emisión con `+"`multica biz run invoice.issue '{\"id\":\"%s\"}'`"+`. Quedará pendiente de aprobación: no la emitas por otra vía.
4. Deja un comentario con lo comprobado y cualquier discrepancia.

El proyecto de entrega se creará solo cuando el cobro esté confirmado (política de la empresa).`, title, invoiceID, invoiceID)
	return s.agentTask(ctx, ws, "finanzas", "Emitir factura: "+title, body, "")
}

func (s *Service) onProjectClosed(ctx context.Context, ws, projectID, eventID string) error {
	if s.alreadyDone(ctx, ws, "closed-tasks:"+projectID) {
		return nil
	}
	var title string
	_ = s.Pool.QueryRow(ctx, `SELECT title FROM project WHERE id=$1`, projectID).Scan(&title)
	if err := s.agentTask(ctx, ws, "ventas", "Pedir referido: "+title,
		"Proyecto cerrado. Redacta la petición de referido (VEN-12) con `message.send` sobre la oportunidad del proyecto. Quedará pendiente de aprobación.", projectID); err != nil {
		return err
	}
	return s.agentTask(ctx, ws, "marca", "Preparar caso de cliente: "+title,
		"Proyecto cerrado. Propón un caso de cliente (MAR-05) con `content.create` en pilar «Casos», con la cifra de resultado del cierre. No lo publiques: solo borrador.", projectID)
}

// --- Rituals (DIR-05/06/10, EQU-09) --------------------------------------

func madridNow() time.Time {
	loc, err := time.LoadLocation("Europe/Madrid")
	if err != nil {
		return time.Now()
	}
	return time.Now().In(loc)
}

// Tick runs every minute. Rituals for today are created once, even if the
// Mac was off at the scheduled time; past days are not back-filled.
func (s *Service) Tick(ctx context.Context) {
	now := madridNow()
	rows, err := s.Pool.Query(ctx, `SELECT workspace_id FROM biz_setting WHERE key='rituals_enabled' AND value='true'::jsonb`)
	if err != nil {
		return
	}
	var workspaces []string
	for rows.Next() {
		var ws string
		_ = rows.Scan(&ws)
		workspaces = append(workspaces, ws)
	}
	rows.Close()
	workday := now.Weekday() != time.Saturday && now.Weekday() != time.Sunday
	for _, ws := range workspaces {
		date := now.Format("2006-01-02")
		if workday && now.Hour() >= 8 {
			s.emitRitual(ctx, ws, "day", date)
		}
		if now.Weekday() == time.Monday && now.Hour() >= 8 {
			y, w := now.ISOWeek()
			s.emitRitual(ctx, ws, "week", fmt.Sprintf("%d-W%02d", y, w))
		}
		if now.Day() == 1 && now.Hour() >= 8 {
			s.emitRitual(ctx, ws, "month", now.Format("2006-01"))
			if int(now.Month())%3 == 1 {
				y, q := quarterOf(now.AddDate(0, -1, 0))
				s.emitRitual(ctx, ws, "quarter", fmt.Sprintf("%d-T%d", y, q))
			}
		}
	}
	s.ProcessEvents(ctx)
}

func (s *Service) emitRitual(ctx context.Context, ws, kind, key string) {
	_ = s.withTx(ctx, func(tx pgx.Tx) error {
		return s.Emit(ctx, tx, ws, "ritual", "", "", "ritual:"+kind+":"+key, map[string]any{"kind": kind, "key": key})
	})
}

func (s *Service) onRitual(ctx context.Context, ws string, p map[string]any, eventID string) error {
	kind, key := str(p["kind"]), str(p["key"])
	switch kind {
	case "day":
		return s.agentTask(ctx, ws, "direccion", "Apertura del día "+key, fmt.Sprintf(`Ritual diario (DIR-05).

1. Lee la vista general: `+"`multica biz get /overview`"+` y las excepciones: `+"`multica biz get /exceptions`"+`.
2. Propón **un único foco** para hoy con su motivo, apoyado en los datos.
3. Guárdalo con `+"`multica biz run routine.save '{\"kind\":\"day\",\"period_key\":\"%s\",\"focus\":\"...\",\"plan\":\"...\"}'`"+`.
4. El veredicto del cierre lo pone la persona responsable al final del día.`, key), "")
	case "week":
		return s.agentTask(ctx, ws, "direccion", "Planificación de la semana "+key,
			"Ritual semanal (DIR-06). Revisa capacidad (`/team`), proyectos en riesgo y objetivos, y propone el reparto de la semana con `routine.save` kind=week. No asignes trabajo por encima de la capacidad declarada.", "")
	case "month":
		return s.agentTask(ctx, ws, "equipo", "Rutina de equipo "+key,
			"Rutina mensual (EQU-09). Revisa la salud y el coste de los agentes (`/team`) y la bitácora (`/audit`). Responde por escrito: ¿qué rutina se cayó y a quién le falta una pieza? Guárdalo con `routine.save` kind=month.", "")
	case "quarter":
		if err := s.agentTask(ctx, ws, "finanzas", "Preparar paquete trimestral "+key,
			"Cierre de trimestre (FIN-09). Ejecuta `period.prepare` para el trimestre cerrado, revisa las excepciones del paquete y deja la lista concreta de lo que falta. No marques nada como enviado.", ""); err != nil {
			return err
		}
		return s.agentTask(ctx, ws, "direccion", "Revisión trimestral "+key,
			"Ritual trimestral (DIR-10). Prepara el balance de objetivos (meta, resultado, aprendizajes, aplazados con destino) y una propuesta de objetivos del siguiente trimestre como decisión abierta (`decision.create`). La decisión la toma la persona responsable.", "")
	}
	return nil
}
