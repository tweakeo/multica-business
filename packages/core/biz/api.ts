import { z } from "zod";
import { api } from "../api";
import { parseWithFallback } from "../api/schema";

// TLS business layer client. Records are rendered generically, so rows are
// validated as objects with passthrough fields; the shapes that drive logic
// (overview, KPI, exceptions, run results) get explicit schemas with
// defaults so an older server never breaks the screen.

export type BizRow = Record<string, unknown> & { id?: string };

const RowSchema = z.record(z.string(), z.unknown());
const RowsSchema = z.array(RowSchema);

export const KPI_STATUSES = ["ok", "warning", "alert", "no_data", "not_configured", "disabled", "stale", "partial"] as const;
export type KpiStatus = (typeof KPI_STATUSES)[number];

const KpiSchema = z.object({
  code: z.string(),
  area: z.string().default(""),
  name: z.string().default(""),
  unit: z.string().default(""),
  formula: z.string().default(""),
  direction: z.string().default("up"),
  period: z.string().default(""),
  value: z.number().nullable().default(null),
  target: z.number().nullable().default(null),
  alert: z.number().nullable().default(null),
  expected: z.number().nullable().optional(),
  status: z.string().catch("no_data"),
  explanation: z.string().default(""),
  coverage: z.string().optional(),
  source: z.string().default(""),
  enabled: z.boolean().default(true),
});
export type BizKpi = z.infer<typeof KpiSchema>;

const ExceptionSchema = z.object({
  area: z.string().default(""),
  kind: z.string().default(""),
  severity: z.string().default("media"),
  title: z.string().default(""),
  what: z.string().default(""),
  why: z.string().default(""),
  action: z.string().default(""),
  consequence: z.string().default(""),
  recommendation: z.string().default(""),
  entity_type: z.string().default(""),
  entity_id: z.string().default(""),
  capability: z.string().default(""),
  factors: z.record(z.string(), z.number()).nullable().default({}),
  score: z.number().default(0),
});
export type BizException = z.infer<typeof ExceptionSchema>;

const MaturitySchema = z.object({
  stage: z.number().default(1),
  label: z.string().default(""),
  evidence: z.array(z.string()).nullable().default([]),
  note: z.string().default(""),
});

const AreaHealthSchema = z.object({
  code: z.string(),
  name: z.string(),
  color: z.string().default(""),
  transforms: z.string().default(""),
  role: z.string().default(""),
  status: z.string().default("no_data"),
  explanation: z.string().default(""),
  kpis: z.array(KpiSchema).nullable().default([]),
  exceptions: z.number().default(0),
  paused: z.boolean().default(false),
  maturity: MaturitySchema.default({ stage: 1, label: "", evidence: [], note: "" }),
});
export type BizAreaHealth = z.infer<typeof AreaHealthSchema>;

const OverviewSchema = z.object({
  areas: z.array(AreaHealthSchema).default([]),
  bottleneck: z.string().default(""),
  exceptions: z.array(ExceptionSchema).default([]),
  exceptions_total: z.number().default(0),
  objectives: RowsSchema.nullable().default([]),
  open_decisions: RowsSchema.nullable().default([]),
  cash: z.number().nullable().default(null),
  cash_coverage: z.string().default(""),
  runway: z.number().nullable().default(null),
  runway_explanation: z.string().default(""),
  owner_dependency: z.object({ pending_approvals: z.number().default(0), open_tasks_on_people: z.number().default(0) }).default({ pending_approvals: 0, open_tasks_on_people: 0 }),
  controls: z.object({ kill_switch: z.boolean().default(false), read_only: z.boolean().default(false) }).default({ kill_switch: false, read_only: false }),
  mode: z.string().default(""),
  folder_pending: z.number().default(0),
});
export type BizOverview = z.infer<typeof OverviewSchema>;

const EMPTY_OVERVIEW: BizOverview = OverviewSchema.parse({});

const CapabilitySchema = z.object({
  code: z.string(),
  area: z.string(),
  name: z.string(),
  level: z.string().default(""),
  trigger: z.string().default(""),
  output: z.string().default(""),
  executor: z.string().default(""),
  requires: z.array(z.string()).nullable().optional(),
  status: z.string().default("pending"),
  ref: z.string().optional(),
  sensitive: z.boolean().default(false),
  mode: z.string().default("assisted"),
  mode_explicit: z.boolean().default(false),
});
export type BizCapability = z.infer<typeof CapabilitySchema>;

const AreaInfoSchema = z.object({ code: z.string(), name: z.string(), color: z.string(), transforms: z.string(), role: z.string() });
export type BizAreaInfo = z.infer<typeof AreaInfoSchema>;

const MetaSchema = z.object({
  areas: z.array(AreaInfoSchema).default([]),
  area_state: RowsSchema.nullable().default([]),
  capabilities: z.array(CapabilitySchema).default([]),
  stages: z.array(z.string()).default([]),
  stage_probability: z.record(z.string(), z.number()).default({}),
  actions: RowsSchema.default([]),
  settings: RowsSchema.nullable().default([]),
  actor: RowSchema.default({}),
});
export type BizMeta = z.infer<typeof MetaSchema>;

const AreaDetailSchema = z.object({
  area: AreaInfoSchema,
  state: RowSchema.nullable().default(null),
  kpis: z.array(KpiSchema).default([]),
  exceptions: z.array(ExceptionSchema).default([]),
  roles: RowsSchema.nullable().default([]),
  agents: RowsSchema.nullable().default([]),
  capabilities: z.array(CapabilitySchema.omit({ mode: true, mode_explicit: true })).default([]),
  maturity: MaturitySchema.default({ stage: 1, label: "", evidence: [], note: "" }),
});
export type BizAreaDetail = z.infer<typeof AreaDetailSchema>;

const RecordSchema = z.object({
  entity_type: z.string(),
  record: RowSchema,
  related: z.record(z.string(), RowsSchema.nullable()).default({}),
});
export type BizRecord = z.infer<typeof RecordSchema>;

const RunResultSchema = z.object({
  status: z.enum(["executed", "approval_required"]).catch("executed"),
  result: z.unknown().optional(),
  approval: RowSchema.optional(),
});
export type BizRunResult = z.infer<typeof RunResultSchema>;

const TeamSchema = z.object({
  members: RowsSchema.nullable().default([]),
  agents: RowsSchema.nullable().default([]),
  roles: RowsSchema.nullable().default([]),
  kill_switch: z.boolean().default(false),
});
export type BizTeam = z.infer<typeof TeamSchema>;

const FolderStatusSchema = z.object({
  root: z.string().default(""),
  configured: z.boolean().default(false),
  pending_writes: z.number().default(0),
  files: z.number().optional(),
  modified_externally: RowsSchema.nullable().optional(),
  unknown_files: RowsSchema.nullable().optional(),
  duplicate_ids: RowsSchema.nullable().optional(),
  parse_errors: RowsSchema.nullable().optional(),
});
export type BizFolderStatus = z.infer<typeof FolderStatusSchema>;

const opts = (endpoint: string) => ({ endpoint });

export const bizApi = {
  meta: async () => parseWithFallback(await api.bizGet("/meta"), MetaSchema, MetaSchema.parse({}), opts("GET /api/biz/meta")),
  overview: async () => parseWithFallback(await api.bizGet("/overview"), OverviewSchema, EMPTY_OVERVIEW, opts("GET /api/biz/overview")),
  area: async (area: string) =>
    parseWithFallback(await api.bizGet(`/areas/${encodeURIComponent(area)}`), AreaDetailSchema, null as BizAreaDetail | null, opts("GET /api/biz/areas/:area")),
  kpis: async (area?: string) =>
    parseWithFallback(await api.bizGet(`/kpis${area ? `?area=${encodeURIComponent(area)}` : ""}`), z.array(KpiSchema), [] as BizKpi[], opts("GET /api/biz/kpis")),
  exceptions: async (area?: string) =>
    parseWithFallback(await api.bizGet(`/exceptions${area ? `?area=${encodeURIComponent(area)}` : ""}`), z.array(ExceptionSchema), [] as BizException[], opts("GET /api/biz/exceptions")),
  list: async (entity: string, params: Record<string, string> = {}) => {
    const q = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== "")).toString();
    return parseWithFallback(await api.bizGet(`/list/${entity}${q ? `?${q}` : ""}`), RowsSchema, [] as BizRow[], opts(`GET /api/biz/list/${entity}`)) as BizRow[];
  },
  record: async (entity: string, id: string) =>
    parseWithFallback(await api.bizGet(`/record/${entity}/${encodeURIComponent(id)}`), RecordSchema, null as BizRecord | null, opts("GET /api/biz/record")),
  projects: async () => parseWithFallback(await api.bizGet("/projects"), RowsSchema, [], opts("GET /api/biz/projects")) as BizRow[],
  team: async () => parseWithFallback(await api.bizGet("/team"), TeamSchema, TeamSchema.parse({}), opts("GET /api/biz/team")),
  search: async (q: string) => parseWithFallback(await api.bizGet(`/search?q=${encodeURIComponent(q)}`), RowsSchema, [], opts("GET /api/biz/search")) as BizRow[],
  audit: async (actorType = "") =>
    parseWithFallback(await api.bizGet(`/audit${actorType ? `?actor_type=${actorType}` : ""}`), RowsSchema, [], opts("GET /api/biz/audit")) as BizRow[],
  events: async (status = "") =>
    parseWithFallback(await api.bizGet(`/events${status ? `?status=${status}` : ""}`), RowsSchema, [], opts("GET /api/biz/events")) as BizRow[],
  folderStatus: async () => parseWithFallback(await api.bizGet("/folder/status"), FolderStatusSchema, FolderStatusSchema.parse({}), opts("GET /api/biz/folder/status")),
  run: async (action: string, payload: unknown) =>
    parseWithFallback(await api.bizPost(`/run/${action}`, payload), RunResultSchema, { status: "executed" } as BizRunResult, opts("POST /api/biz/run")),
  decide: async (id: string, approve: boolean, reason: string) =>
    parseWithFallback(await api.bizPost(`/approvals/${id}/decide`, { approve, reason }), RowSchema, {}, opts("POST /api/biz/approvals/:id/decide")),
  folderExport: async () => api.bizPost("/folder/export", {}),
  folderRebuild: async (apply: boolean) => parseWithFallback(await api.bizPost("/folder/rebuild", { apply }), RowSchema, {}, opts("POST /api/biz/folder/rebuild")),
};
