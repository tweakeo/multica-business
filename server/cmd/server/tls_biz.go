package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgtype"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/multica-ai/multica/server/internal/biz"
	"github.com/multica-ai/multica/server/internal/events"
	"github.com/multica-ai/multica/server/internal/handler"
	"github.com/multica-ai/multica/server/internal/service"
	"github.com/multica-ai/multica/server/internal/util"
	db "github.com/multica-ai/multica/server/pkg/db/generated"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

// tlsBiz is the TLS business layer, built once per router and started from main.
var tlsBiz *biz.Service

func newTLSBiz(pool *pgxpool.Pool, queries *db.Queries, bus *events.Bus, h *handler.Handler) *biz.Service {
	publish := func(ws, typ, actorType, actorID string, payload any) {
		bus.Publish(events.Event{Type: typ, WorkspaceID: ws, ActorType: actorType, ActorID: actorID, Payload: payload})
	}
	parse := func(s string) pgtype.UUID {
		if s == "" {
			return pgtype.UUID{}
		}
		u, err := util.ParseUUID(s)
		if err != nil {
			return pgtype.UUID{}
		}
		return u
	}
	date := func(s string) pgtype.Date {
		if s == "" {
			return pgtype.Date{}
		}
		t, err := time.Parse("2006-01-02", s)
		if err != nil {
			return pgtype.Date{}
		}
		return pgtype.Date{Time: t, Valid: true}
	}
	text := func(s string) pgtype.Text { return pgtype.Text{String: s, Valid: s != ""} }
	owner := func(ctx context.Context, ws string) pgtype.UUID {
		var id string
		_ = pool.QueryRow(ctx, `SELECT user_id::text FROM member WHERE workspace_id=$1 ORDER BY (role='owner') DESC, created_at LIMIT 1`, ws).Scan(&id)
		return parse(id)
	}
	hooks := biz.Hooks{
		CreateProject: func(ctx context.Context, ws string, p biz.ProjectSpec) (string, error) {
			project, err := queries.CreateProject(ctx, db.CreateProjectParams{
				WorkspaceID: parse(ws), Title: p.Title, Description: text(p.Description), Icon: text(p.Icon), Status: p.Status,
				LeadType: text(p.LeadType), LeadID: parse(p.LeadID), Priority: "medium", StartDate: date(p.StartDate), DueDate: date(p.DueDate),
				WorkflowID: parse(p.WorkflowID),
			})
			if err != nil {
				return "", err
			}
			id := util.UUIDToString(project.ID)
			publish(ws, protocol.EventProjectCreated, "system", "", map[string]any{"project": map[string]any{"id": id, "title": project.Title}})
			return id, nil
		},
		CreateIssue: func(ctx context.Context, ws string, p biz.IssueSpec) (string, error) {
			creator := owner(ctx, ws)
			var prefix string
			_ = pool.QueryRow(ctx, `SELECT coalesce(issue_prefix,'') FROM workspace WHERE id=$1`, ws).Scan(&prefix)
			res, err := h.IssueService.Create(ctx, service.IssueCreateParams{
				WorkspaceID: parse(ws), Title: p.Title, Description: text(p.Description), Status: p.Status, Priority: p.Priority,
				AssigneeType: text(p.AssigneeType), AssigneeID: parse(p.AssigneeID), CreatorType: "member", CreatorID: creator,
				ProjectID: parse(p.ProjectID), ParentIssueID: parse(p.ParentID), StartDate: date(p.StartDate), DueDate: date(p.DueDate),
				AllowDuplicate: true,
			}, service.IssueCreateOpts{
				Platform: "tls",
				BroadcastPayload: func(issue db.Issue, _ []db.Attachment, _ []db.IssueLabel) map[string]any {
					return map[string]any{"issue": service.IssueToMapResolved(ctx, queries, issue, prefix)}
				},
			})
			if err != nil {
				return "", err
			}
			return util.UUIDToString(res.Issue.ID), nil
		},
	}
	svc := biz.NewService(pool, publish, hooks)
	// No new agent run starts while the company's kill switch or the agent's
	// area pause is on (DIR-11).
	h.TaskService.ClaimGate = func(ctx context.Context, ws, agentID string) bool {
		return !svc.KillSwitchOn(ctx, ws) && !svc.AgentAreaPaused(ctx, ws, agentID)
	}
	tlsBiz = svc
	return svc
}

// startTLSBiz replays pending folder writes and runs the event/ritual ticker.
func startTLSBiz(ctx context.Context) {
	if tlsBiz == nil {
		return
	}
	go func() {
		rows, err := tlsBiz.Pool.Query(ctx, `SELECT DISTINCT workspace_id::text FROM biz_journal WHERE state='intent'`)
		if err == nil {
			var ws []string
			for rows.Next() {
				var id string
				_ = rows.Scan(&id)
				ws = append(ws, id)
			}
			rows.Close()
			for _, id := range ws {
				tlsBiz.Folder.FlushPending(ctx, id)
			}
		}
		tlsBiz.Tick(ctx)
		ticker := time.NewTicker(time.Minute)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				tlsBiz.Tick(ctx)
			}
		}
	}()
}
