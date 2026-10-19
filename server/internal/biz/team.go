package biz

import (
	"context"
	"encoding/json"
	"strings"

	"github.com/jackc/pgx/v5"
)

func (s *Service) registerTeam() {
	s.register(&Command{
		Action: "role.save", Capability: "EQU-01", Area: "equipo",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			in, err := decode[struct {
				ID           string   `json:"id"`
				Area         string   `json:"area"`
				Name         string   `json:"name"`
				Mission      string   `json:"mission"`
				Decisions    string   `json:"decisions"`
				Limits       string   `json:"limits"`
				KPICodes     []string `json:"kpi_codes"`
				Manual       string   `json:"manual"`
				OccupantType string   `json:"occupant_type"`
				OccupantID   string   `json:"occupant_id"`
			}](p)
			if err != nil {
				return nil, err
			}
			if in.KPICodes == nil {
				in.KPICodes = []string{}
			}
			var row json.RawMessage
			if in.ID == "" {
				if !IsArea(in.Area) || strings.TrimSpace(in.Name) == "" || strings.TrimSpace(in.Mission) == "" {
					return nil, invalid("El rol necesita área, nombre y misión (EQU-01)")
				}
				err = tx.QueryRow(ctx, `INSERT INTO biz_role (workspace_id, area, name, mission, decisions, limits, kpi_codes, manual, occupant_type, occupant_id)
					VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10) RETURNING to_jsonb(biz_role.*)`, ws, in.Area, in.Name, in.Mission, in.Decisions, in.Limits, in.KPICodes,
					in.Manual, nullable(in.OccupantType), nullable(in.OccupantID)).Scan(&row)
			} else {
				err = tx.QueryRow(ctx, `UPDATE biz_role SET mission=coalesce(nullif($3,''), mission), decisions=coalesce(nullif($4,''), decisions),
					limits=coalesce(nullif($5,''), limits), manual=coalesce(nullif($6,''), manual), occupant_type=$7, occupant_id=$8,
					version=version+1, updated_at=now() WHERE id=$1 AND workspace_id=$2 RETURNING to_jsonb(biz_role.*)`,
					in.ID, ws, in.Mission, in.Decisions, in.Limits, in.Manual, nullable(in.OccupantType), nullable(in.OccupantID)).Scan(&row)
			}
			if err != nil {
				return nil, invalid("No se pudo guardar el rol: %v", err)
			}
			res := entityResult("role", row)
			s.Folder.Journal(ctx, tx, ws, "role", str(res["id"]))
			return res, nil
		},
	})

	// Registering an agent as a business executor is a permission change.
	s.register(&Command{
		Action: "agent.assign", Capability: "EQU-04", Area: "equipo",
		Exec: func(ctx context.Context, tx pgx.Tx, s *Service, ws string, a Actor, p json.RawMessage) (any, error) {
			if a.Type != "member" || (a.Role != "owner" && a.Role != "admin") {
				return nil, errf(403, "forbidden", "Solo propietarios y administradores asignan agentes a un área")
			}
			in, err := decode[struct {
				AgentID            string `json:"agent_id"`
				Area               string `json:"area"`
				RoleID             string `json:"role_id"`
				IsCoordinator      bool   `json:"is_coordinator"`
				BudgetMonthlyMinor int64  `json:"budget_monthly_minor"`
				MaxDelegationDepth *int   `json:"max_delegation_depth"`
			}](p)
			if err != nil {
				return nil, err
			}
			if !IsArea(in.Area) {
				return nil, invalid("Área desconocida")
			}
			var ok bool
			_ = tx.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM agent WHERE id=$1 AND workspace_id=$2)`, in.AgentID, ws).Scan(&ok)
			if !ok {
				return nil, invalid("Agente no encontrado en esta empresa")
			}
			depth := 2
			if in.MaxDelegationDepth != nil {
				depth = *in.MaxDelegationDepth
			}
			if _, err := tx.Exec(ctx, `INSERT INTO biz_agent (agent_id, workspace_id, area, role_id, is_coordinator, budget_monthly_minor, max_delegation_depth)
				VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (agent_id) DO UPDATE SET area=EXCLUDED.area, role_id=EXCLUDED.role_id,
				is_coordinator=EXCLUDED.is_coordinator, budget_monthly_minor=EXCLUDED.budget_monthly_minor, max_delegation_depth=EXCLUDED.max_delegation_depth, updated_at=now()`,
				in.AgentID, ws, in.Area, nullable(in.RoleID), in.IsCoordinator, in.BudgetMonthlyMinor, depth); err != nil {
				return nil, err
			}
			if in.RoleID != "" {
				_, _ = tx.Exec(ctx, `UPDATE biz_role SET occupant_type='agent', occupant_id=$2, version=version+1, updated_at=now() WHERE id=$1 AND occupant_id IS NULL`, in.RoleID, in.AgentID)
			}
			return map[string]any{"entity_type": "agent", "id": in.AgentID, "area": in.Area}, nil
		},
	})
}
