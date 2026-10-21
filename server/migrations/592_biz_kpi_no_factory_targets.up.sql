-- KPI targets are the company's, not the factory's. Production companies
-- lose the seeded targets nobody configured (version 1 = never edited), so
-- a KPI without a target shows "sin meta" instead of a verdict. The demo
-- keeps its targets: they are set by its seed.
UPDATE biz_kpi k SET target = NULL, alert = NULL, updated_at = now()
WHERE k.version = 1 AND (k.target IS NOT NULL OR k.alert IS NOT NULL)
  AND EXISTS (SELECT 1 FROM biz_setting s WHERE s.workspace_id = k.workspace_id AND s.key = 'mode' AND s.value #>> '{}' = 'produccion');
