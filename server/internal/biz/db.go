package biz

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// Querier is satisfied by both the pool and a transaction.
type Querier interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// entityTables maps API entity names to their tables. Only these tables can
// be reached by the generic read and folder code.
var entityTables = map[string]string{
	"organization": "biz_organization",
	"contact":      "biz_contact",
	"opportunity":  "biz_opportunity",
	"service":      "biz_service",
	"offer":        "biz_offer_version",
	"invoice":      "biz_invoice",
	"payment":      "biz_payment",
	"account":      "biz_bank_account",
	"movement":     "biz_bank_movement",
	"period":       "biz_period",
	"kpi":          "biz_kpi",
	"objective":    "biz_objective",
	"decision":     "biz_decision",
	"content":      "biz_content",
	"conversation": "biz_conversation",
	"routine":      "biz_routine",
	"role":         "biz_role",
	"document":     "biz_document",
	"approval":     "biz_approval",
}

// listJSON returns rows of an arbitrary SELECT as one JSON array.
func listJSON(ctx context.Context, q Querier, sql string, args ...any) (json.RawMessage, error) {
	var out json.RawMessage
	err := q.QueryRow(ctx, fmt.Sprintf(`SELECT coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb) FROM (%s) x`, sql), args...).Scan(&out)
	return out, err
}

// oneJSON returns the single row of a SELECT as a JSON object.
func oneJSON(ctx context.Context, q Querier, sql string, args ...any) (json.RawMessage, error) {
	var out json.RawMessage
	err := q.QueryRow(ctx, fmt.Sprintf(`SELECT to_jsonb(x) FROM (%s) x`, sql), args...).Scan(&out)
	if err == pgx.ErrNoRows {
		return nil, errf(http.StatusNotFound, "not_found", "No encontrado")
	}
	return out, err
}

// rowMap reads one row as a generic map (for describe/effects and folder export).
func rowMap(ctx context.Context, q Querier, entityType, id string) (map[string]any, error) {
	table, ok := entityTables[entityType]
	if !ok {
		return nil, fmt.Errorf("unknown entity %s", entityType)
	}
	raw, err := oneJSON(ctx, q, fmt.Sprintf(`SELECT * FROM %s WHERE id=$1`, table), id)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	err = json.Unmarshal(raw, &m)
	return m, err
}

// requireRow checks that a referenced record exists in the same workspace —
// the application-level replacement for a foreign key.
func requireRow(ctx context.Context, q Querier, ws, entityType, id string) error {
	if id == "" {
		return nil
	}
	table, ok := entityTables[entityType]
	if !ok {
		return fmt.Errorf("unknown entity %s", entityType)
	}
	var exists bool
	if err := q.QueryRow(ctx, fmt.Sprintf(`SELECT EXISTS (SELECT 1 FROM %s WHERE id=$1 AND workspace_id=$2)`, table), id, ws).Scan(&exists); err != nil || !exists {
		return invalid("%s %s no existe en esta empresa", entityType, id)
	}
	return nil
}

func entityResult(entityType string, row json.RawMessage) map[string]any {
	var m map[string]any
	_ = json.Unmarshal(row, &m)
	if m == nil {
		m = map[string]any{}
	}
	m["entity_type"] = entityType
	return m
}

func nullable(s string) any {
	if s == "" {
		return nil
	}
	return s
}
