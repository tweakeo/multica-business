package biz

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var contentFlow = map[string][]string{
	"idea":       {"borrador"},
	"borrador":   {"revision", "idea"},
	"revision":   {"aprobado", "borrador"},
	"aprobado":   {"programado", "publicado", "borrador"},
	"programado": {"publicado", "fallido", "aprobado"},
	"fallido":    {"programado", "borrador"},
	"publicado":  {},
}

func (s *Service) registerBrand() {
	s.register(&Command{
		Action: "content.create", Capability: "MAR-03", Area: "marca",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Title         string `json:"title"`
				Pillar        string `json:"pillar"`
				Channel       string `json:"channel"`
				Format        string `json:"format"`
				Body          string `json:"body"`
				DerivedFromID string `json:"derived_from_id"`
			}](p)
			if err != nil {
				return nil, err
			}
			if strings.TrimSpace(in.Title) == "" {
				return nil, invalid("La pieza necesita título")
			}
			status := "idea"
			if strings.TrimSpace(in.Body) != "" {
				status = "borrador"
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_content (workspace_id, title, pillar, channel, format, body, status, derived_from_id)
				VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING to_jsonb(biz_content.*)`, ws, in.Title, in.Pillar, in.Channel, in.Format, in.Body, status, nullable(in.DerivedFromID)).Scan(&row); err != nil {
				return nil, err
			}
			res := entityResult("content", row)
			s.Folder.Journal(ctx, tx, ws, "content", str(res["id"]))
			return res, nil
		},
	})

	s.register(&Command{
		Action: "content.update", Capability: "MAR-03", Area: "marca",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			return s.updateRecord(ctx, tx, ws, p, map[string][]string{"content": {"title", "pillar", "channel", "format", "body", "notes", "scheduled_at"}})
		},
	})

	// Publishing is an external effect: it needs the platform's confirmation
	// or manual evidence, and agents must have it approved.
	s.register(&Command{
		Action: "content.move", Capability: "MAR-03", Area: "marca",
		Sensitive: func(p json.RawMessage) bool {
			var in struct {
				Status string `json:"status"`
			}
			_ = json.Unmarshal(p, &in)
			return in.Status == "publicado" || in.Status == "programado"
		},
		Describe: func(ctx context.Context, s *Service, ws string, p json.RawMessage) Description {
			var in struct {
				ID          string `json:"id"`
				Status      string `json:"status"`
				EvidenceURL string `json:"evidence_url"`
			}
			_ = json.Unmarshal(p, &in)
			m, _ := rowMap(ctx, s.Pool, "content", in.ID)
			return Description{Title: "Contenido «" + str(m["title"]) + "» → " + in.Status, Summary: str(m["body"]), EntityType: "content", EntityID: in.ID,
				Effects: []Effect{{Field: "estado", Before: str(m["status"]), After: in.Status}, {Field: "canal", After: str(m["channel"])}}}
		},
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID            string `json:"id"`
				Status        string `json:"status"`
				ScheduledAt   string `json:"scheduled_at"`
				EvidenceURL   string `json:"evidence_url"`
				FailureReason string `json:"failure_reason"`
			}](p)
			if err != nil {
				return nil, err
			}
			var current string
			if err := tx.QueryRow(ctx, `SELECT status FROM biz_content WHERE id=$1 AND workspace_id=$2 FOR UPDATE`, in.ID, ws).Scan(&current); err != nil {
				return nil, errf(404, "not_found", "Contenido no encontrado")
			}
			ok := false
			for _, next := range contentFlow[current] {
				ok = ok || next == in.Status
			}
			if !ok {
				return nil, invalid("De %s no se pasa a %s", current, in.Status)
			}
			var scheduled any
			if in.Status == "programado" {
				t, err := time.Parse(time.RFC3339, in.ScheduledAt)
				if err != nil {
					if d, derr := parseDate(in.ScheduledAt); derr == nil {
						t = d.Add(9 * time.Hour)
					} else {
						return nil, invalid("Indica la fecha de publicación prevista")
					}
				}
				scheduled = t
			}
			if in.Status == "publicado" && strings.TrimSpace(in.EvidenceURL) == "" {
				return nil, invalid("Publicado exige la confirmación de la plataforma o un enlace de evidencia")
			}
			if in.Status == "fallido" && strings.TrimSpace(in.FailureReason) == "" {
				return nil, invalid("Indica por qué falló la publicación")
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `UPDATE biz_content SET status=$3, scheduled_at=coalesce($4, scheduled_at),
				published_at=CASE WHEN $3='publicado' THEN now() ELSE published_at END, evidence_url=CASE WHEN $5<>'' THEN $5 ELSE evidence_url END,
				failure_reason=$6, version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_content.*)`,
				in.ID, ws, in.Status, scheduled, in.EvidenceURL, in.FailureReason).Scan(&row); err != nil {
				return nil, err
			}
			if in.Status == "publicado" {
				_ = s.Emit(ctx, tx, ws, "contenido.publicado", "content", in.ID, "content-published:"+in.ID, map[string]any{})
			}
			s.Folder.Journal(ctx, tx, ws, "content", in.ID)
			return entityResult("content", row), nil
		},
	})

	s.register(&Command{
		Action: "conversation.create", Capability: "MAR-06", Area: "marca",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Channel   string `json:"channel"`
				Handle    string `json:"handle"`
				Summary   string `json:"summary"`
				ContentID string `json:"content_id"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.Channel == "" || strings.TrimSpace(in.Summary) == "" {
				return nil, invalid("La conversación necesita canal y resumen")
			}
			if err := requireRow(ctx, tx, ws, "content", in.ContentID); err != nil {
				return nil, err
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_conversation (workspace_id, channel, handle, summary, content_id) VALUES ($1,$2,$3,$4,$5)
				RETURNING to_jsonb(biz_conversation.*)`, ws, in.Channel, in.Handle, in.Summary, nullable(in.ContentID)).Scan(&row); err != nil {
				return nil, err
			}
			res := entityResult("conversation", row)
			s.Folder.Journal(ctx, tx, ws, "conversation", str(res["id"]))
			return res, nil
		},
	})

	// MAR-07: a qualified conversation becomes a lead with its real origin.
	// Marca keeps attribution; Ventas owns the commercial fit afterwards.
	s.register(&Command{
		Action: "conversation.qualify", Capability: "MAR-07", Area: "marca",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID          string `json:"id"`
				Name        string `json:"name"`
				Email       string `json:"email"`
				Phone       string `json:"phone"`
				Company     string `json:"company"`
				ServiceCode string `json:"service_code"`
			}](p)
			if err != nil {
				return nil, err
			}
			var channel, contentID, summary string
			var qualified bool
			if err := tx.QueryRow(ctx, `SELECT channel, coalesce(content_id::text,''), summary, qualified FROM biz_conversation WHERE id=$1 AND workspace_id=$2 FOR UPDATE`, in.ID, ws).
				Scan(&channel, &contentID, &summary, &qualified); err != nil {
				return nil, errf(404, "not_found", "Conversación no encontrada")
			}
			if qualified {
				return nil, invalid("La conversación ya pasó a Ventas")
			}
			lead := map[string]any{
				"contact": map[string]any{"name": in.Name, "email": in.Email, "phone": in.Phone}, "service_code": in.ServiceCode,
				"channel": channel, "source_content_id": contentID, "notes": "Desde conversación: " + summary, "origin": "marca",
			}
			if in.Company != "" {
				lead["organization"] = map[string]any{"name": in.Company}
			}
			lp, _ := json.Marshal(lead)
			res, err := s.commands["lead.create"].Exec(ctx, tx, s, ws, Actor{Type: "system"}, lp)
			if err != nil {
				return nil, err
			}
			m := res.(map[string]any)
			if _, err := tx.Exec(ctx, `UPDATE biz_conversation SET qualified=true, contact_id=$3, version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2`, in.ID, ws, m["contact_id"]); err != nil {
				return nil, err
			}
			s.Folder.Journal(ctx, tx, ws, "conversation", in.ID)
			return m, nil
		},
	})
}
