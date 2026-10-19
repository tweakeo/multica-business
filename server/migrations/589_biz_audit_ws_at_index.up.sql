CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_biz_audit_ws_at ON biz_audit (workspace_id, at DESC);
