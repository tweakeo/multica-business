CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_biz_event_pending ON biz_event (next_attempt_at) WHERE status IN ('pending','failed');
