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
