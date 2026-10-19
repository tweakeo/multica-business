package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// Template is a service line's versioned delivery plan. Offsets are in
// working days from the project start; "planned" moves, "due" is the
// commitment (ENT-04).
type Template struct {
	ProjectDays int             `json:"project_days"`
	Phases      []TemplatePhase `json:"phases"`
	DoneWhen    string          `json:"done_when"`
}

type TemplatePhase struct {
	Name  string         `json:"name"`
	Tasks []TemplateTask `json:"tasks"`
}

type TemplateTask struct {
	Title       string `json:"title"`
	Description string `json:"description"`
	Status      string `json:"status"`
	Offset      int    `json:"offset"`
	Duration    int    `json:"duration"`
	DueSlack    int    `json:"due_slack"`
	// Assignee: "agent:<area>" for the area agent, "lead" for the project lead.
	Assignee   string `json:"assignee"`
	Acceptance string `json:"acceptance"`
}

func addWorkdays(t time.Time, n int) time.Time {
	for n > 0 {
		t = t.AddDate(0, 0, 1)
		if t.Weekday() != time.Saturday && t.Weekday() != time.Sunday {
			n--
		}
	}
	for t.Weekday() == time.Saturday || t.Weekday() == time.Sunday {
		t = t.AddDate(0, 0, 1)
	}
	return t
}

func (s *Service) areaAgent(ctx context.Context, q Querier, ws, area string) string {
	var id string
	_ = q.QueryRow(ctx, `SELECT g.agent_id FROM biz_agent g JOIN agent a ON a.id=g.agent_id WHERE g.workspace_id=$1 AND g.area=$2 AND a.archived_at IS NULL
		ORDER BY g.is_coordinator DESC, g.created_at LIMIT 1`, ws, area).Scan(&id)
	return id
}

// agentAvailable reports whether a new run for the area agent may start now.
func (s *Service) agentAvailable(ctx context.Context, ws, area string) (string, bool) {
	id := s.areaAgent(ctx, s.Pool, ws, area)
	if id == "" || s.KillSwitchOn(ctx, ws) || s.AgentAreaPaused(ctx, ws, id) {
		return id, false
	}
	return id, true
}

// createProjectFromPayment is ENT-01/VEN-07: exactly one project per
// opportunity, guarded by biz_project_link.opportunity_id UNIQUE.
func (s *Service) createProjectFromPayment(ctx context.Context, ws, oppID, invoiceID string) error {
	if oppID == "" {
		return nil
	}
	var exists bool
	_ = s.Pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM biz_project_link WHERE opportunity_id=$1)`, oppID).Scan(&exists)
	if exists {
		return nil
	}
	var title, orgID, serviceID, orgName, svcName, workflowID, ownerType, ownerID string
	var templateVersion int
	if err := s.Pool.QueryRow(ctx, `SELECT o.title, coalesce(o.organization_id::text,''), coalesce(o.service_id::text,''), coalesce(org.name, c.name, ''), coalesce(s.name,''),
			coalesce(s.workflow_id::text,''), coalesce(s.template_version,1), coalesce(o.owner_type,''), coalesce(o.owner_id::text,'')
		FROM biz_opportunity o LEFT JOIN biz_organization org ON org.id=o.organization_id LEFT JOIN biz_contact c ON c.id=o.contact_id
		LEFT JOIN biz_service s ON s.id=o.service_id
		WHERE o.id=$1 AND o.workspace_id=$2`, oppID, ws).Scan(&title, &orgID, &serviceID, &orgName, &svcName, &workflowID, &templateVersion, &ownerType, &ownerID); err != nil {
		return fmt.Errorf("opportunity %s: %w", oppID, err)
	}
	if s.Hooks.CreateProject == nil {
		return fmt.Errorf("project hook not configured")
	}
	// The project lead is the accountable person: the occupant of the
	// delivery role, else the opportunity owner, else the workspace owner.
	// Agents assist on the tasks the template assigns to them.
	leadType, leadID := "member", ""
	_ = s.Pool.QueryRow(ctx, `SELECT occupant_id::text FROM biz_role WHERE workspace_id=$1 AND area='entrega' AND occupant_type='member' AND archived_at IS NULL LIMIT 1`, ws).Scan(&leadID)
	if leadID == "" && ownerType == "member" {
		leadID = ownerID
	}
	if leadID == "" {
		_ = s.Pool.QueryRow(ctx, `SELECT user_id::text FROM member WHERE workspace_id=$1 ORDER BY (role='owner') DESC, created_at LIMIT 1`, ws).Scan(&leadID)
	}
	start := today()
	name := strings.TrimSpace(svcName + " · " + orgName)
	if name == "·" || name == "" {
		name = title
	}
	projectID, err := s.Hooks.CreateProject(ctx, ws, ProjectSpec{
		Title: name, Description: fmt.Sprintf("Proyecto de servicio creado al confirmarse el cobro.\n\nOportunidad: %s", title),
		Icon: "📁", Status: "in_progress", LeadType: leadType, LeadID: leadID, StartDate: start.Format("2006-01-02"), WorkflowID: workflowID,
	})
	if err != nil {
		return err
	}
	return s.withTx(ctx, func(tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `INSERT INTO biz_project_link (project_id, workspace_id, service_id, organization_id, opportunity_id, kind, period_key, template_version)
			VALUES ($1,$2,$3,$4,$5,'service',$6,$7) ON CONFLICT (opportunity_id) DO NOTHING`,
			projectID, ws, nullable(serviceID), nullable(orgID), oppID, fmt.Sprintf("%d", start.Year()), templateVersion)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			// A concurrent delivery won the race; archive the orphan project.
			_, err = tx.Exec(ctx, `UPDATE project SET status='cancelled' WHERE id=$1`, projectID)
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE biz_opportunity SET stage='ganada', probability=100, won_at=now(), project_id=$3, next_action='', version=version+1, updated_at=now()
			WHERE id=$1 AND workspace_id=$2`, oppID, ws, projectID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE biz_organization SET kind='client', version=version+1, updated_at=now() WHERE id=$1 AND kind='prospect'`, nullable(orgID)); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE biz_contact SET kind='client', version=version+1, updated_at=now() WHERE id=(SELECT contact_id FROM biz_opportunity WHERE id=$1) AND kind='lead'`, oppID); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE biz_invoice SET project_id=$2 WHERE id=$1`, nullable(invoiceID), projectID); err != nil {
			return err
		}
		s.Folder.Journal(ctx, tx, ws, "opportunity", oppID)
		return s.Emit(ctx, tx, ws, "proyecto.creado", "project", projectID, "project-created:"+projectID, map[string]any{"project_id": projectID, "service_id": serviceID, "opportunity_id": oppID})
	})
}

// materializeProject creates the template tasks once (ENT-02/03/04).
func (s *Service) materializeProject(ctx context.Context, ws, projectID string) error {
	var count int
	_ = s.Pool.QueryRow(ctx, `SELECT count(*) FROM issue WHERE project_id=$1`, projectID).Scan(&count)
	if count > 0 {
		return nil
	}
	var raw json.RawMessage
	var leadType, leadID string
	var startDate *time.Time
	err := s.Pool.QueryRow(ctx, `SELECT s.template, coalesce(p.lead_type,''), coalesce(p.lead_id::text,''), p.start_date
		FROM biz_project_link l JOIN biz_service s ON s.id=l.service_id JOIN project p ON p.id=l.project_id WHERE l.project_id=$1 AND l.workspace_id=$2`,
		projectID, ws).Scan(&raw, &leadType, &leadID, &startDate)
	if err != nil {
		return nil // strategic projects have no template
	}
	var tpl Template
	if err := json.Unmarshal(raw, &tpl); err != nil {
		return fmt.Errorf("template: %w", err)
	}
	start := today()
	if startDate != nil {
		start = *startDate
	}
	importing := s.settingBool(ctx, s.Pool, ws, "import_mode")
	for _, phase := range tpl.Phases {
		for _, t := range phase.Tasks {
			planned := addWorkdays(start, t.Offset)
			due := addWorkdays(planned, max(t.Duration, 1)+t.DueSlack)
			assigneeType, assigneeID := "", ""
			switch {
			case strings.HasPrefix(t.Assignee, "agent:") && importing && leadID != "":
				// History is not re-run by agents: the accountable person owns it.
				assigneeType, assigneeID = leadType, leadID
			case strings.HasPrefix(t.Assignee, "agent:"):
				if id, ok := s.agentAvailable(ctx, ws, strings.TrimPrefix(t.Assignee, "agent:")); ok {
					assigneeType, assigneeID = "agent", id
				}
			case t.Assignee == "lead" && leadID != "":
				assigneeType, assigneeID = leadType, leadID
			}
			desc := t.Description
			if t.Acceptance != "" {
				desc += "\n\n**Criterio de terminado:** " + t.Acceptance
			}
			desc += "\n\n_Fase: " + phase.Name + "_"
			status := t.Status
			if status == "" {
				status = "todo"
			}
			if _, err := s.Hooks.CreateIssue(ctx, ws, IssueSpec{
				Title: t.Title, Description: desc, Status: status, Priority: "medium", AssigneeType: assigneeType, AssigneeID: assigneeID,
				ProjectID: projectID, StartDate: planned.Format("2006-01-02"), DueDate: due.Format("2006-01-02"),
			}); err != nil {
				return err
			}
		}
	}
	return nil
}

func (s *Service) registerDelivery() {
	s.register(&Command{
		Action: "project.close", Capability: "ENT-05", Area: "entrega",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ProjectID string `json:"project_id"`
				Outcome   string `json:"outcome"`
				Evidence  string `json:"evidence"`
			}](p)
			if err != nil {
				return nil, err
			}
			if strings.TrimSpace(in.Outcome) == "" || strings.TrimSpace(in.Evidence) == "" {
				return nil, invalid("El cierre exige resultado y evidencia de entrega, no solo un adjunto")
			}
			var open int
			if err := tx.QueryRow(ctx, `SELECT count(*) FROM issue i LEFT JOIN issue_status st ON st.workspace_id=i.workspace_id AND st.key=i.status
				WHERE i.project_id=$1 AND i.workspace_id=$2 AND coalesce(st.category, 'unstarted') NOT IN ('done','closed')`,
				in.ProjectID, ws).Scan(&open); err != nil {
				return nil, err
			}
			if open > 0 {
				return nil, invalid("Quedan %d tareas abiertas en el proyecto", open)
			}
			if _, err := tx.Exec(ctx, `UPDATE project SET status='completed', description=coalesce(description,'') || E'\n\n**Cierre:** ' || $3 || E'\n**Evidencia:** ' || $4, updated_at=now()
				WHERE id=$1 AND workspace_id=$2`, in.ProjectID, ws, in.Outcome, in.Evidence); err != nil {
				return nil, err
			}
			if err := s.Emit(ctx, tx, ws, "proyecto.cerrado", "project", in.ProjectID, "project-closed:"+in.ProjectID, map[string]any{"outcome": in.Outcome}); err != nil {
				return nil, err
			}
			return map[string]any{"entity_type": "project", "id": in.ProjectID, "status": "completed"}, nil
		},
	})

	s.register(&Command{
		Action: "project.create", Capability: "DIR-03", Area: "direccion",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				Title       string `json:"title"`
				Description string `json:"description"`
				Kind        string `json:"kind"`
				ObjectiveID string `json:"objective_id"`
				DueDate     string `json:"due_date"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.Kind != "strategic" && in.Kind != "compliance" {
				return nil, invalid("Los proyectos de servicio nacen del cobro; aquí solo estratégicos o de cumplimiento")
			}
			if in.Kind == "strategic" && in.ObjectiveID == "" {
				return nil, invalid("Un proyecto estratégico cuelga de un objetivo (DIR-03)")
			}
			if err := requireRow(ctx, tx, ws, "objective", in.ObjectiveID); err != nil {
				return nil, err
			}
			id, err := s.Hooks.CreateProject(ctx, ws, ProjectSpec{Title: in.Title, Description: in.Description, Icon: "🎯", Status: "planned",
				LeadType: map[bool]string{true: "member"}[a.Type == "member"], LeadID: a.UserID, StartDate: today().Format("2006-01-02"), DueDate: in.DueDate})
			if err != nil {
				return nil, err
			}
			if _, err := tx.Exec(ctx, `INSERT INTO biz_project_link (project_id, workspace_id, objective_id, kind) VALUES ($1,$2,$3,$4)`, id, ws, nullable(in.ObjectiveID), in.Kind); err != nil {
				return nil, err
			}
			return map[string]any{"entity_type": "project", "id": id}, nil
		},
	})

	s.register(&Command{
		Action: "service.save", Capability: "ENT-02", Area: "entrega",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			if a.Type != "member" {
				return nil, errf(403, "forbidden", "Los servicios y sus plantillas los define una persona")
			}
			in, err := decode[struct {
				ID          string          `json:"id"`
				Code        string          `json:"code"`
				Name        string          `json:"name"`
				Description string          `json:"description"`
				Recurrence  string          `json:"recurrence"`
				WorkflowID  string          `json:"workflow_id"`
				Template    json.RawMessage `json:"template"`
			}](p)
			if err != nil {
				return nil, err
			}
			if len(in.Template) > 0 {
				var tpl Template
				if err := json.Unmarshal(in.Template, &tpl); err != nil || len(tpl.Phases) == 0 {
					return nil, invalid("Plantilla no válida: necesita al menos una fase con tareas")
				}
			}
			var row json.RawMessage
			if in.ID == "" {
				if in.Code == "" || in.Name == "" {
					return nil, invalid("El servicio necesita código y nombre")
				}
				if len(in.Template) == 0 {
					in.Template = json.RawMessage(`{}`)
				}
				err = tx.QueryRow(ctx, `INSERT INTO biz_service (workspace_id, code, name, description, recurrence, workflow_id, template)
					VALUES ($1,$2,$3,$4,coalesce(nullif($5,''),'one_off'),$6,$7) RETURNING to_jsonb(biz_service.*)`,
					ws, in.Code, in.Name, in.Description, in.Recurrence, nullable(in.WorkflowID), in.Template).Scan(&row)
			} else {
				// A template change is a new template version; running projects keep theirs.
				err = tx.QueryRow(ctx, `UPDATE biz_service SET name=coalesce(nullif($3,''), name), description=coalesce(nullif($4,''), description),
					workflow_id=coalesce($5, workflow_id), template=coalesce($6, template),
					template_version=template_version + CASE WHEN $6::jsonb IS NOT NULL AND $6::jsonb <> template THEN 1 ELSE 0 END,
					version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_service.*)`,
					in.ID, ws, in.Name, in.Description, nullable(in.WorkflowID), nullableJSON(in.Template)).Scan(&row)
			}
			if err != nil {
				return nil, invalid("No se pudo guardar el servicio: %v", err)
			}
			res := entityResult("service", row)
			s.Folder.Journal(ctx, tx, ws, "service", str(res["id"]))
			return res, nil
		},
	})

	// A new offer version becomes the single current price; accepted
	// proposals and issued invoices keep their own snapshot.
	s.register(&Command{
		Action: "offer.version", Capability: "VEN-06", Area: "ventas",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ServiceID     string `json:"service_id"`
				PriceMinor    int64  `json:"price_minor"`
				TaxRateBP     *int   `json:"tax_rate_bp"`
				WithholdingBP *int   `json:"withholding_bp"`
				BillingUnit   string `json:"billing_unit"`
				Conditions    string `json:"conditions"`
			}](p)
			if err != nil {
				return nil, err
			}
			if err := requireRow(ctx, tx, ws, "service", in.ServiceID); err != nil {
				return nil, err
			}
			if in.PriceMinor <= 0 {
				return nil, invalid("Precio no válido")
			}
			var prevTax, prevWh int
			var prevUnit, prevCond string
			var version int
			_ = tx.QueryRow(ctx, `SELECT coalesce(max(version),0) FROM biz_offer_version WHERE service_id=$1`, in.ServiceID).Scan(&version)
			_ = tx.QueryRow(ctx, `SELECT tax_rate_bp, withholding_bp, billing_unit, conditions FROM biz_offer_version WHERE service_id=$1 AND active ORDER BY version DESC LIMIT 1`, in.ServiceID).
				Scan(&prevTax, &prevWh, &prevUnit, &prevCond)
			if in.TaxRateBP == nil {
				in.TaxRateBP = &prevTax
			}
			if in.WithholdingBP == nil {
				in.WithholdingBP = &prevWh
			}
			if in.BillingUnit == "" {
				in.BillingUnit = prevUnit
			}
			if in.Conditions == "" {
				in.Conditions = prevCond
			}
			if _, err := tx.Exec(ctx, `UPDATE biz_offer_version SET active=false WHERE service_id=$1`, in.ServiceID); err != nil {
				return nil, err
			}
			var row json.RawMessage
			if err := tx.QueryRow(ctx, `INSERT INTO biz_offer_version (workspace_id, service_id, version, price_minor, tax_rate_bp, withholding_bp, billing_unit, conditions)
				VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING to_jsonb(biz_offer_version.*)`, ws, in.ServiceID, version+1, in.PriceMinor, *in.TaxRateBP, *in.WithholdingBP,
				coalesceStr(in.BillingUnit, "servicio"), in.Conditions).Scan(&row); err != nil {
				return nil, err
			}
			res := entityResult("offer", row)
			s.Folder.Journal(ctx, tx, ws, "offer", str(res["id"]))
			return res, nil
		},
	})
}

func nullableJSON(v json.RawMessage) any {
	if len(v) == 0 {
		return nil
	}
	return string(v)
}

func coalesceStr(v, d string) string {
	if v == "" {
		return d
	}
	return v
}
