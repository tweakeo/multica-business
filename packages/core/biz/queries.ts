import { queryOptions } from "@tanstack/react-query";
import { bizApi } from "./api";

// Every key is under ["biz", wsId] so a single realtime `biz:` event can
// invalidate the whole business projection of a workspace.
export const bizKeys = {
  all: (wsId: string) => ["biz", wsId] as const,
  meta: (wsId: string) => [...bizKeys.all(wsId), "meta"] as const,
  overview: (wsId: string) => [...bizKeys.all(wsId), "overview"] as const,
  area: (wsId: string, area: string) => [...bizKeys.all(wsId), "area", area] as const,
  kpis: (wsId: string, area: string) => [...bizKeys.all(wsId), "kpis", area] as const,
  exceptions: (wsId: string, area: string) => [...bizKeys.all(wsId), "exceptions", area] as const,
  list: (wsId: string, entity: string, params: Record<string, string>) => [...bizKeys.all(wsId), "list", entity, params] as const,
  record: (wsId: string, entity: string, id: string) => [...bizKeys.all(wsId), "record", entity, id] as const,
  projects: (wsId: string) => [...bizKeys.all(wsId), "projects"] as const,
  team: (wsId: string) => [...bizKeys.all(wsId), "team"] as const,
  search: (wsId: string, q: string) => [...bizKeys.all(wsId), "search", q] as const,
  audit: (wsId: string, actorType: string) => [...bizKeys.all(wsId), "audit", actorType] as const,
  events: (wsId: string, status: string) => [...bizKeys.all(wsId), "events", status] as const,
  folder: (wsId: string) => [...bizKeys.all(wsId), "folder"] as const,
  systems: (wsId: string, area: string) => [...bizKeys.all(wsId), "systems", area] as const,
  documents: (wsId: string) => [...bizKeys.all(wsId), "documents"] as const,
  portals: (wsId: string) => [...bizKeys.all(wsId), "portal"] as const,
  portal: (wsId: string, slug: string, client: boolean) => [...bizKeys.all(wsId), "portal", slug, client] as const,
  databases: (wsId: string) => [...bizKeys.all(wsId), "databases"] as const,
  database: (wsId: string, key: string) => [...bizKeys.all(wsId), "databases", key] as const,
  databaseRow: (wsId: string, key: string, id: string) => [...bizKeys.all(wsId), "databases", key, "row", id] as const,
  ritmo: (wsId: string, period: string) => [...bizKeys.all(wsId), "ritmo", period] as const,
  pipeline: (wsId: string) => [...bizKeys.all(wsId), "pipeline"] as const,
  carga: (wsId: string) => [...bizKeys.all(wsId), "carga"] as const,
  planificacion: (wsId: string) => [...bizKeys.all(wsId), "planificacion"] as const,
};

export const bizMetaOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.meta(wsId), queryFn: bizApi.meta, staleTime: 30_000 });

export const bizOverviewOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.overview(wsId), queryFn: bizApi.overview });

export const bizAreaOptions = (wsId: string, area: string) =>
  queryOptions({ queryKey: bizKeys.area(wsId, area), queryFn: () => bizApi.area(area) });

export const bizExceptionsOptions = (wsId: string, area = "") =>
  queryOptions({ queryKey: bizKeys.exceptions(wsId, area), queryFn: () => bizApi.exceptions(area) });

export const bizKpisOptions = (wsId: string, area = "") =>
  queryOptions({ queryKey: bizKeys.kpis(wsId, area), queryFn: () => bizApi.kpis(area) });

export const bizListOptions = (wsId: string, entity: string, params: Record<string, string> = {}) =>
  queryOptions({ queryKey: bizKeys.list(wsId, entity, params), queryFn: () => bizApi.list(entity, params) });

export const bizRecordOptions = (wsId: string, entity: string, id: string) =>
  queryOptions({ queryKey: bizKeys.record(wsId, entity, id), queryFn: () => bizApi.record(entity, id), enabled: Boolean(id) });

export const bizProjectsOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.projects(wsId), queryFn: bizApi.projects });

export const bizTeamOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.team(wsId), queryFn: bizApi.team });

export const bizSearchOptions = (wsId: string, q: string) =>
  queryOptions({ queryKey: bizKeys.search(wsId, q), queryFn: () => bizApi.search(q), enabled: q.trim().length >= 2 });

export const bizAuditOptions = (wsId: string, actorType = "") =>
  queryOptions({ queryKey: bizKeys.audit(wsId, actorType), queryFn: () => bizApi.audit(actorType) });

export const bizEventsOptions = (wsId: string, status = "") =>
  queryOptions({ queryKey: bizKeys.events(wsId, status), queryFn: () => bizApi.events(status) });

export const bizFolderOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.folder(wsId), queryFn: bizApi.folderStatus });

export const bizSystemsOptions = (wsId: string, area: string) =>
  queryOptions({ queryKey: bizKeys.systems(wsId, area), queryFn: () => bizApi.systems(area), staleTime: 30_000 });

export const bizDocumentsOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.documents(wsId), queryFn: bizApi.documents, staleTime: 30_000 });

export const bizPortalsOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.portals(wsId), queryFn: bizApi.portals, staleTime: 15_000 });

export const bizPortalOptions = (wsId: string, slug: string, client: boolean) =>
  queryOptions({ queryKey: bizKeys.portal(wsId, slug, client), queryFn: () => bizApi.portal(slug, client), enabled: Boolean(slug), staleTime: 15_000 });

export const bizDatabasesOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.databases(wsId), queryFn: bizApi.databases, staleTime: 15_000 });

export const bizDatabaseOptions = (wsId: string, key: string) =>
  queryOptions({ queryKey: bizKeys.database(wsId, key), queryFn: () => bizApi.database(key), enabled: Boolean(key), staleTime: 15_000 });

export const bizDatabaseRowOptions = (wsId: string, key: string, id: string) =>
  queryOptions({ queryKey: bizKeys.databaseRow(wsId, key, id), queryFn: () => bizApi.databaseRow(key, id), enabled: Boolean(key && id), staleTime: 15_000 });

export const bizRitmoOptions = (wsId: string, period: string) =>
  queryOptions({ queryKey: bizKeys.ritmo(wsId, period), queryFn: () => bizApi.ritmo(period), staleTime: 15_000 });

export const bizPipelineOptions = (wsId: string) => queryOptions({ queryKey: bizKeys.pipeline(wsId), queryFn: bizApi.pipeline, staleTime: 15_000 });

export const bizCargaOptions = (wsId: string) => queryOptions({ queryKey: bizKeys.carga(wsId), queryFn: bizApi.carga, staleTime: 15_000 });

export const bizPlanificacionOptions = (wsId: string) =>
  queryOptions({ queryKey: bizKeys.planificacion(wsId), queryFn: bizApi.planificacion, staleTime: 15_000 });
