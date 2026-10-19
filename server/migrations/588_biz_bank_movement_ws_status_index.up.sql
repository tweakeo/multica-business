CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_biz_bank_movement_ws_status ON biz_bank_movement (workspace_id, status);
