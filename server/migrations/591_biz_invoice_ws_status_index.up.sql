CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_biz_invoice_ws_status ON biz_invoice (workspace_id, status);
