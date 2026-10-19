package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

func eur(minor int64) string {
	sign := ""
	if minor < 0 {
		sign = "-"
		minor = -minor
	}
	whole := minor / 100
	s := fmt.Sprintf("%d", whole)
	var b strings.Builder
	for i, r := range s {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte('.')
		}
		b.WriteRune(r)
	}
	return fmt.Sprintf("%s%s,%02d €", sign, b.String(), minor%100)
}

type leadInput struct {
	OrganizationID string `json:"organization_id"`
	Organization   *struct {
		Name      string `json:"name"`
		Kind      string `json:"kind"`
		LegalForm string `json:"legal_form"`
		TaxID     string `json:"tax_id"`
		Sector    string `json:"sector"`
		City      string `json:"city"`
	} `json:"organization"`
	Contact struct {
		Name     string `json:"name"`
		Email    string `json:"email"`
		Phone    string `json:"phone"`
		Position string `json:"position"`
	} `json:"contact"`
	ServiceCode     string `json:"service_code"`
	ServiceID       string `json:"service_id"`
	Title           string `json:"title"`
	Channel         string `json:"channel"`
	SourceContentID string `json:"source_content_id"`
	OwnerType       string `json:"owner_type"`
	OwnerID         string `json:"owner_id"`
	Notes           string `json:"notes"`
	Origin          string `json:"origin"`
}

func (s *Service) serviceByCodeOrID(ctx context.Context, q Querier, ws, code, id string) (string, string, error) {
	var sid, name string
	var err error
	if id != "" {
		err = q.QueryRow(ctx, `SELECT id, name FROM biz_service WHERE workspace_id=$1 AND id=$2`, ws, id).Scan(&sid, &name)
	} else if code != "" {
		err = q.QueryRow(ctx, `SELECT id, name FROM biz_service WHERE workspace_id=$1 AND code=$2`, ws, code).Scan(&sid, &name)
	} else {
		return "", "", nil
	}
	if err != nil {
		return "", "", invalid("Servicio no encontrado")
	}
	return sid, name, nil
}

func activeOffer(ctx context.Context, q Querier, serviceID string) (id string, price int64, err error) {
	err = q.QueryRow(ctx, `SELECT id, price_minor FROM biz_offer_version WHERE service_id=$1 AND active ORDER BY version DESC LIMIT 1`, serviceID).Scan(&id, &price)
	return
}

func (s *Service) registerSales() {
	s.register(&Command{
		Action: "lead.create", Capability: "VEN-01", Area: "ventas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[leadInput](p)
			if err != nil {
				return nil, err
			}
			in.Contact.Name = strings.TrimSpace(in.Contact.Name)
			if in.Contact.Name == "" {
				return nil, invalid("El contacto necesita un nombre")
			}
			if in.Channel == "" {
				return nil, invalid("Indica el canal de entrada (atribución)")
			}
			origin := in.Origin
			if origin == "" {
				origin = map[bool]string{true: "agent", false: "app"}[a.Type == "agent"]
			}
			// Organization: reuse by id, by tax id or by exact name; never duplicate.
			orgID := in.OrganizationID
			if orgID != "" {
				if err := requireRow(ctx, tx, ws, "organization", orgID); err != nil {
					return nil, err
				}
			} else if in.Organization != nil && strings.TrimSpace(in.Organization.Name) != "" {
				o := in.Organization
				_ = tx.QueryRow(ctx, `SELECT id FROM biz_organization WHERE workspace_id=$1 AND archived_at IS NULL AND
					((tax_id<>'' AND tax_id=$2) OR lower(name)=lower($3)) LIMIT 1`, ws, o.TaxID, strings.TrimSpace(o.Name)).Scan(&orgID)
				if orgID == "" {
					kind := o.Kind
					if kind == "" {
						kind = "prospect"
					}
					if err := tx.QueryRow(ctx, `INSERT INTO biz_organization (workspace_id, name, kind, legal_form, tax_id, sector, city, source_channel, source_content_id, origin)
						VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING id`, ws, strings.TrimSpace(o.Name), kind, o.LegalForm, o.TaxID, o.Sector, o.City,
						in.Channel, nullable(in.SourceContentID), origin).Scan(&orgID); err != nil {
						return nil, err
					}
				}
			}
			// Contact: reuse by email inside the workspace.
			var contactID string
			duplicate := false
			if email := strings.ToLower(strings.TrimSpace(in.Contact.Email)); email != "" {
				_ = tx.QueryRow(ctx, `SELECT id FROM biz_contact WHERE workspace_id=$1 AND lower(email)=$2 AND archived_at IS NULL`, ws, email).Scan(&contactID)
				duplicate = contactID != ""
			}
			if contactID == "" {
				if err := tx.QueryRow(ctx, `INSERT INTO biz_contact (workspace_id, organization_id, name, email, phone, position, kind, source_channel, source_content_id, notes, origin)
					VALUES ($1,$2,$3,$4,$5,$6,'lead',$7,$8,$9,$10) RETURNING id`, ws, nullable(orgID), in.Contact.Name, strings.TrimSpace(in.Contact.Email),
					in.Contact.Phone, in.Contact.Position, in.Channel, nullable(in.SourceContentID), in.Notes, origin).Scan(&contactID); err != nil {
					return nil, err
				}
			}
			serviceID, serviceName, err := s.serviceByCodeOrID(ctx, tx, ws, in.ServiceCode, in.ServiceID)
			if err != nil {
				return nil, err
			}
			var value int64
			if serviceID != "" {
				_, value, _ = activeOffer(ctx, tx, serviceID)
			}
			title := in.Title
			if title == "" {
				title = strings.TrimSuffix(strings.TrimSpace(in.Contact.Name+" · "+serviceName), " ·")
			}
			ownerType, ownerID := in.OwnerType, in.OwnerID
			if ownerType == "" && a.Type == "member" {
				ownerType, ownerID = "member", a.UserID
			}
			var opp json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_opportunity (workspace_id, title, contact_id, organization_id, service_id, stage, value_minor,
					owner_type, owner_id, channel, probability, next_action, next_action_on, last_contact_at, origin, notes)
				VALUES ($1,$2,$3,$4,$5,'entrada',$6,$7,$8,$9,$10,'Cualificar y proponer sesión de diagnóstico',$11, now(), $12, $13)
				RETURNING to_jsonb(biz_opportunity.*)`, ws, title, contactID, nullable(orgID), nullable(serviceID), value,
				nullable(ownerType), nullable(ownerID), in.Channel, StageProbability["entrada"], today().AddDate(0, 0, 2), origin, in.Notes).Scan(&opp); err != nil {
				return nil, err
			}
			res := entityResult("opportunity", opp)
			if err := s.Emit(ctx, tx, ws, "contacto.creado", "contact", contactID, "lead:"+res["id"].(string), map[string]any{
				"contact_id": contactID, "organization_id": orgID, "opportunity_id": res["id"], "channel": in.Channel, "duplicate_contact": duplicate,
			}); err != nil {
				return nil, err
			}
			for _, j := range []struct{ t, id string }{{"organization", orgID}, {"contact", contactID}, {"opportunity", res["id"].(string)}} {
				s.Folder.Journal(ctx, tx, ws, j.t, j.id)
			}
			res["contact_id"], res["organization_id"], res["duplicate_contact"] = contactID, orgID, duplicate
			return res, nil
		},
	})

	s.register(&Command{
		Action: "contact.create", Capability: "VEN-01", Area: "ventas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				OrganizationID, Name, Email, Phone, Position, Kind, Notes string
			}](p)
			if err != nil {
				return nil, err
			}
			if strings.TrimSpace(in.Name) == "" {
				return nil, invalid("El contacto necesita un nombre")
			}
			if in.Kind == "" || in.Kind == "lead" {
				return nil, invalid("Para un interesado usa el alta comercial (lead.create); aquí solo clientes, proveedores, socios u otros")
			}
			if err := requireRow(ctx, tx, ws, "organization", in.OrganizationID); err != nil {
				return nil, err
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_contact (workspace_id, organization_id, name, email, phone, position, kind, notes)
				VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING to_jsonb(biz_contact.*)`, ws, nullable(in.OrganizationID), in.Name, in.Email, in.Phone, in.Position, in.Kind, in.Notes).Scan(&row); err != nil {
				return nil, err
			}
			res := entityResult("contact", row)
			s.Folder.Journal(ctx, tx, ws, "contact", res["id"].(string))
			return res, nil
		},
	})

	s.register(&Command{
		Action: "record.update", Capability: "VEN-03", Area: "ventas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			return s.updateRecord(ctx, tx, ws, p, map[string][]string{
				"organization": {"name", "kind", "legal_form", "tax_id", "sector", "city", "email", "phone", "notes"},
				"contact":      {"name", "email", "phone", "position", "kind", "notes", "opted_out", "organization_id"},
				"opportunity":  {"title", "value_minor", "owner_type", "owner_id", "channel", "probability", "next_action", "next_action_on", "notes", "service_id"},
			})
		},
	})

	s.register(&Command{
		Action: "opportunity.move", Capability: "VEN-03", Area: "ventas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID         string `json:"id"`
				Stage      string `json:"stage"`
				LostReason string `json:"lost_reason"`
				Version    *int   `json:"version"`
			}](p)
			if err != nil {
				return nil, err
			}
			var stage, ownerID, serviceID string
			var proposal json.RawMessage
			var version int
			if err := tx.QueryRow(ctx, `SELECT stage, coalesce(owner_id::text,''), coalesce(service_id::text,''), proposal, version FROM biz_opportunity
				WHERE id=$1 AND workspace_id=$2 FOR UPDATE`, in.ID, ws).Scan(&stage, &ownerID, &serviceID, &proposal, &version); err != nil {
				return nil, errf(404, "not_found", "Oportunidad no encontrada")
			}
			if in.Version != nil && *in.Version != version {
				return nil, errf(409, "version_conflict", "La oportunidad cambió mientras la editabas (versión %d)", version)
			}
			if err := validateStage(in.Stage, ownerID, serviceID, len(proposal) > 0 && string(proposal) != "null", in.LostReason); err != nil {
				return nil, err
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_opportunity SET stage=$3, probability=$4, lost_reason=CASE WHEN $3='perdida' THEN $5 ELSE lost_reason END,
				version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_opportunity.*)`,
				in.ID, ws, in.Stage, StageProbability[in.Stage], in.LostReason).Scan(&row); err != nil {
				return nil, err
			}
			if err := s.Emit(ctx, tx, ws, "oportunidad.etapa", "opportunity", in.ID, fmt.Sprintf("opp-stage:%s:%d", in.ID, version+1), map[string]any{"from": stage, "to": in.Stage}); err != nil {
				return nil, err
			}
			s.Folder.Journal(ctx, tx, ws, "opportunity", in.ID)
			return entityResult("opportunity", row), nil
		},
	})

	s.register(&Command{
		Action: "opportunity.proposal", Capability: "VEN-06", Area: "ventas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID             string `json:"id"`
				OfferVersionID string `json:"offer_version_id"`
				Quantity       int    `json:"quantity"`
				Notes          string `json:"notes"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.Quantity <= 0 {
				in.Quantity = 1
			}
			var serviceID, stage string
			if err := tx.QueryRow(ctx, `SELECT coalesce(service_id::text,''), stage FROM biz_opportunity WHERE id=$1 AND workspace_id=$2 FOR UPDATE`, in.ID, ws).Scan(&serviceID, &stage); err != nil {
				return nil, errf(404, "not_found", "Oportunidad no encontrada")
			}
			if serviceID == "" {
				return nil, invalid("La oportunidad necesita un servicio para generar la propuesta")
			}
			if stage == "ganada" || stage == "perdida" || stage == "aceptada" {
				return nil, invalid("No se genera propuesta en etapa %s", stage)
			}
			offerID := in.OfferVersionID
			if offerID == "" {
				if offerID, _, err = activeOffer(ctx, tx, serviceID); err != nil {
					return nil, invalid("El servicio no tiene una oferta vigente")
				}
			}
			var svcName, conditions, currency, unit string
			var price int64
			var taxBP, whBP, offerVersion int
			if err := tx.QueryRow(ctx, `SELECT s.name, o.conditions, o.currency, o.billing_unit, o.price_minor, o.tax_rate_bp, o.withholding_bp, o.version
				FROM biz_offer_version o JOIN biz_service s ON s.id=o.service_id WHERE o.id=$1 AND o.service_id=$2`, offerID, serviceID).
				Scan(&svcName, &conditions, &currency, &unit, &price, &taxBP, &whBP, &offerVersion); err != nil {
				return nil, invalid("La versión de oferta no pertenece al servicio")
			}
			base := price * int64(in.Quantity)
			tax := roundBP(base, taxBP)
			wh := roundBP(base, whBP)
			snapshot := map[string]any{
				"service": svcName, "offer_version_id": offerID, "offer_version": offerVersion, "unit_price_minor": price,
				"quantity": in.Quantity, "billing_unit": unit, "base_minor": base, "tax_rate_bp": taxBP, "tax_minor": tax,
				"withholding_bp": whBP, "withholding_minor": wh, "total_minor": base + tax - wh, "currency": currency,
				"conditions": conditions, "notes": in.Notes, "generated_at": time.Now().UTC(), "valid_until": today().AddDate(0, 0, 30).Format("2006-01-02"),
			}
			snap, _ := json.Marshal(snapshot)
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_opportunity SET proposal=$3, offer_version_id=$4, value_minor=$5, stage='propuesta', probability=$6,
				next_action='Seguimiento de la propuesta', next_action_on=$7, version=version+1, updated_at=now()
				WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_opportunity.*)`, in.ID, ws, snap, offerID, base, StageProbability["propuesta"], today().AddDate(0, 0, 5)).Scan(&row); err != nil {
				return nil, err
			}
			s.Folder.Journal(ctx, tx, ws, "opportunity", in.ID)
			return entityResult("opportunity", row), nil
		},
	})

	// Commercial acceptance is a contractual fact: agents may only propose it.
	s.register(&Command{
		Action: "opportunity.accept", Capability: "VEN-06", Area: "ventas", Sensitive: always(true),
		Describe: func(ctx context.Context, s *Service, ws string, p json.RawMessage) Description {
			id := string(jsonField(p, "id"))
			var oid string
			_ = json.Unmarshal([]byte(id), &oid)
			m, _ := rowMap(ctx, s.Pool, "opportunity", oid)
			return Description{Title: "Registrar aceptación: " + str(m["title"]), Summary: "La propuesta pasa a aceptada pendiente de cobro y se prepara la factura en borrador.",
				EntityType: "opportunity", EntityID: oid, Effects: []Effect{{Field: "etapa", Before: str(m["stage"]), After: "aceptada"}}}
		},
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID       string `json:"id"`
				Evidence string `json:"evidence"`
			}](p)
			if err != nil {
				return nil, err
			}
			var proposal json.RawMessage
			var stage string
			if err := tx.QueryRow(ctx, `SELECT proposal, stage FROM biz_opportunity WHERE id=$1 AND workspace_id=$2 FOR UPDATE`, in.ID, ws).Scan(&proposal, &stage); err != nil {
				return nil, errf(404, "not_found", "Oportunidad no encontrada")
			}
			if len(proposal) == 0 || string(proposal) == "null" {
				return nil, invalid("No hay propuesta que aceptar")
			}
			if stage != "propuesta" && stage != "negociacion" {
				return nil, invalid("Solo se acepta desde propuesta o negociación (etapa actual: %s)", stage)
			}
			if strings.TrimSpace(in.Evidence) == "" {
				return nil, invalid("Indica la evidencia de la aceptación (correo, firma, llamada…)")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_opportunity SET stage='aceptada', probability=$3, accepted_at=now(),
				notes=trim(notes || E'\nAceptación: ' || $4), next_action='Emitir factura y confirmar cobro', next_action_on=$5,
				version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_opportunity.*)`,
				in.ID, ws, StageProbability["aceptada"], in.Evidence, today().AddDate(0, 0, 1)).Scan(&row); err != nil {
				return nil, err
			}
			if err := s.Emit(ctx, tx, ws, "oportunidad.aceptada", "opportunity", in.ID, "opp-accepted:"+in.ID, map[string]any{"evidence": in.Evidence}); err != nil {
				return nil, err
			}
			s.Folder.Journal(ctx, tx, ws, "opportunity", in.ID)
			return entityResult("opportunity", row), nil
		},
	})

	s.register(&Command{
		Action: "contact.touch", Capability: "VEN-08", Area: "ventas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				OpportunityID string `json:"opportunity_id"`
				Summary       string `json:"summary"`
				NextAction    string `json:"next_action"`
				NextActionOn  string `json:"next_action_on"`
			}](p)
			if err != nil {
				return nil, err
			}
			if strings.TrimSpace(in.Summary) == "" {
				return nil, invalid("Resume el contacto realizado")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_opportunity SET last_contact_at=now(), next_action=coalesce(nullif($3,''), next_action),
				next_action_on=coalesce(nullif($4,'')::date, next_action_on), notes=trim(notes || E'\n' || to_char(now(),'YYYY-MM-DD') || ': ' || $5),
				version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_opportunity.*)`,
				in.OpportunityID, ws, in.NextAction, in.NextActionOn, in.Summary).Scan(&row); err != nil {
				return nil, errf(404, "not_found", "Oportunidad no encontrada")
			}
			_, _ = tx.Exec(ctx, `UPDATE biz_contact SET last_contact_at=now(), updated_at=now() WHERE id=(SELECT contact_id FROM biz_opportunity WHERE id=$1)`, in.OpportunityID)
			s.Folder.Journal(ctx, tx, ws, "opportunity", in.OpportunityID)
			return entityResult("opportunity", row), nil
		},
	})

	// Outbound communication is always reviewed before it is recorded as sent.
	// There is no mail integration in this build: execution records the message
	// as "ready to send manually" and never claims delivery.
	s.register(&Command{
		Action: "message.send", Capability: "VEN-08", Area: "ventas", Sensitive: always(true),
		Describe: func(ctx context.Context, s *Service, ws string, p json.RawMessage) Description {
			in, _ := decode[struct {
				OpportunityID, To, Subject, Body string
			}](p)
			return Description{Title: "Enviar mensaje a " + in.To, Summary: in.Subject + "\n\n" + in.Body, EntityType: "opportunity", EntityID: in.OpportunityID,
				Effects: []Effect{{Field: "destinatario", After: in.To}, {Field: "asunto", After: in.Subject}}}
		},
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				OpportunityID string `json:"opportunity_id"`
				To            string `json:"to"`
				Subject       string `json:"subject"`
				Body          string `json:"body"`
			}](p)
			if err != nil {
				return nil, err
			}
			var optedOut bool
			var contactID string
			if err := tx.QueryRow(ctx, `SELECT c.opted_out, c.id FROM biz_opportunity o JOIN biz_contact c ON c.id=o.contact_id WHERE o.id=$1 AND o.workspace_id=$2`, in.OpportunityID, ws).Scan(&optedOut, &contactID); err != nil {
				return nil, errf(404, "not_found", "Oportunidad sin contacto")
			}
			if optedOut {
				return nil, invalid("El contacto pidió no recibir comunicaciones")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_conversation (workspace_id, channel, handle, summary, contact_id, qualified)
				VALUES ($1,'email',$2,$3,$4,false) RETURNING to_jsonb(biz_conversation.*)`, ws, in.To,
				"Saliente (pendiente de envío manual, sin integración de correo): "+in.Subject+"\n\n"+in.Body, contactID).Scan(&row); err != nil {
				return nil, err
			}
			_, _ = tx.Exec(ctx, `UPDATE biz_opportunity SET last_contact_at=now(), version=version+1, updated_at=now() WHERE id=$1`, in.OpportunityID)
			return entityResult("conversation", row), nil
		},
	})
}

// validateStage enforces the fields each stage requires (VEN-03). "ganada"
// is reserved for the confirmed-payment event.
func validateStage(stage, ownerID, serviceID string, hasProposal bool, lostReason string) error {
	known := false
	for _, s := range OpportunityStages {
		known = known || s == stage
	}
	if !known {
		return invalid("Etapa desconocida: %s", stage)
	}
	switch stage {
	case "ganada":
		return invalid("Una oportunidad solo pasa a ganada cuando se confirma el cobro")
	case "aceptada":
		return invalid("Usa «Registrar aceptación» con su evidencia")
	case "perdida":
		if strings.TrimSpace(lostReason) == "" {
			return invalid("Indica el motivo de pérdida")
		}
	}
	idx := map[string]int{"entrada": 0, "cualificacion": 1, "diagnostico": 2, "propuesta": 3, "negociacion": 4}
	if i, ok := idx[stage]; ok {
		if i >= 1 && ownerID == "" {
			return invalid("Desde cualificación la oportunidad necesita responsable")
		}
		if i >= 2 && serviceID == "" {
			return invalid("Desde diagnóstico la oportunidad necesita servicio")
		}
		if i >= 3 && !hasProposal {
			return invalid("Genera la propuesta antes de pasar a %s", stage)
		}
	}
	return nil
}

// roundBP applies basis points with half-up rounding on integer cents.
func roundBP(base int64, bp int) int64 {
	n := base * int64(bp)
	if n >= 0 {
		return (n + 5000) / 10000
	}
	return -((-n + 5000) / 10000)
}

func str(v any) string {
	if v == nil {
		return ""
	}
	if s, ok := v.(string); ok {
		return s
	}
	return fmt.Sprint(v)
}

// updateRecord patches whitelisted fields of a CRM record with optimistic
// version checking.
func (s *Service) updateRecord(ctx context.Context, tx pgx.Tx, ws string, p json.RawMessage, allowed map[string][]string) (any, error) {
	in, err := decode[struct {
		Entity  string         `json:"entity"`
		ID      string         `json:"id"`
		Version *int           `json:"version"`
		Fields  map[string]any `json:"fields"`
	}](p)
	if err != nil {
		return nil, err
	}
	fields, ok := allowed[in.Entity]
	if !ok {
		return nil, invalid("No se puede editar %s con esta acción", in.Entity)
	}
	table := entityTables[in.Entity]
	sets := []string{}
	args := []any{in.ID, ws}
	for _, f := range fields {
		v, present := in.Fields[f]
		if !present {
			continue
		}
		if sv, ok := v.(string); ok && sv == "" && (strings.HasSuffix(f, "_id") || strings.HasSuffix(f, "_on") || f == "owner_type") {
			v = nil
		}
		args = append(args, v)
		sets = append(sets, fmt.Sprintf("%s=$%d", f, len(args)))
	}
	if len(sets) == 0 {
		return nil, invalid("Nada que actualizar")
	}
	where := "id=$1 AND workspace_id=$2"
	if in.Version != nil {
		args = append(args, *in.Version)
		where += fmt.Sprintf(" AND version=$%d", len(args))
	}
	var row json.RawMessage
	err = tx.QueryRow(ctx, fmt.Sprintf(`UPDATE %s SET %s, version=version+1, updated_at=now() WHERE %s RETURNING to_jsonb(%s.*)`, table, strings.Join(sets, ", "), where, table), args...).Scan(&row)
	if err == pgx.ErrNoRows {
		return nil, errf(409, "version_conflict", "El registro no existe o cambió mientras lo editabas")
	}
	if err != nil {
		return nil, invalid("No se pudo guardar: %v", err)
	}
	s.Folder.Journal(ctx, tx, ws, in.Entity, in.ID)
	return entityResult(in.Entity, row), nil
}
