CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_biz_approval_ws_status ON biz_approval (workspace_id, status);
