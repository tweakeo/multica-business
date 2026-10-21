/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { FolderOpen, OctagonPause, ShieldAlert, type LucideIcon } from "lucide-react";
import { api } from "@multica/core/api";
import {
  bizAuditOptions,
  bizExceptionsOptions,
  bizEventsOptions,
  bizFolderOptions,
  bizListOptions,
  bizMetaOptions,
  bizOverviewOptions,
  formatDate,
  formatDateTime,
  formatKpiValue,
  useBizFolder,
  type BizRow,
} from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { useCurrentWorkspace, useWorkspacePaths } from "@multica/core/paths";
import { useAuthStore } from "@multica/core/auth";
import { Button } from "@multica/ui/components/ui/button";
import { Switch } from "@multica/ui/components/ui/switch";
import { Tabs, TabsList, TabsTrigger } from "@multica/ui/components/ui/tabs";
import { Textarea } from "@multica/ui/components/ui/textarea";
import { cn } from "@multica/ui/lib/utils";
import { toast } from "sonner";
import { CollectionPageHeader } from "../layout/collection-page";
import { PAGE_GUTTER } from "../layout/page-header";
import { useNavigation } from "../navigation";
import { AreaPaceRow } from "./area-pace";
import { CashHero } from "./cash-chart";
import { ApprovalCard, ExceptionList } from "./blocks";
import { RecordSheet } from "./record-sheet";
import {
  AREAS,
  AreaDot,
  AreaTag,
  EmptyHint,
  ErrorBlock,
  InspectorProvider,
  ListRow,
  LoadingBlock,
  Pill,
  RecordLink,
  Section,
  str,
  useAction,
} from "./shared";
import { BizSearch, NewLeadDialog } from "./widgets";

export function EmpresaShell({ children, title, icon, actions }: { children: React.ReactNode; title: React.ReactNode; icon?: LucideIcon; actions?: React.ReactNode }) {
  const [target, setTarget] = useState<{ entity: string; id: string } | null>(null);
  return (
    <InspectorProvider value={setTarget}>
      <div className="flex h-full min-h-0 flex-col">
        <CollectionPageHeader icon={icon} title={title} actions={actions} />
        <ModeBanner />
        <div className="min-h-0 flex-1 overflow-y-auto">{children}</div>
      </div>
      <RecordSheet target={target} onClose={() => setTarget(null)} />
    </InspectorProvider>
  );
}

/** Always shows where you are (demo vs real) and whether controls are on. */
function ModeBanner() {
  const wsId = useWorkspaceId();
  const meta = useQuery(bizMetaOptions(wsId));
  const settings = Object.fromEntries((meta.data?.settings ?? []).map((s) => [str(s.key), s.value]));
  const demo = settings.mode === "demo";
  const kill = settings.kill_switch === true;
  const ro = settings.read_only === true;
  if (!demo && !kill && !ro) return null;
  return (
    <div className={cn(PAGE_GUTTER, "flex flex-wrap items-center gap-x-4 gap-y-1 py-1.5 text-caption", kill || ro ? "text-destructive" : "text-muted-foreground")}>
      {demo ? <span>Demo · datos ficticios</span> : null}
      {kill ? <span className="font-medium">Interruptor global activado: agentes y automatismos detenidos</span> : null}
      {ro ? <span className="font-medium">Modo lectura: no se admiten cambios</span> : null}
    </div>
  );
}

export function EmpresaPage() {
  const nav = useNavigation();
  const tab = nav.searchParams.get("tab") ?? "empresa";
  const ws = useCurrentWorkspace();
  const wsId = useWorkspaceId();
  const approvals = useQuery(bizListOptions(wsId, "approval", { status: "pending" }));
  const [leadOpen, setLeadOpen] = useState(false);
  const setTab = (v: string) => {
    const sp = new URLSearchParams(nav.searchParams);
    if (v === "empresa") sp.delete("tab");
    else sp.set("tab", v);
    const q = sp.toString();
    nav.replace(`${nav.pathname}${q ? `?${q}` : ""}`);
  };
  const pending = approvals.data?.length ?? 0;
  return (
    <EmpresaShell
      title={ws?.name ? `Empresa · ${ws.name}` : "Empresa"}
      actions={
        <div className="flex items-center gap-2">
          <BizSearch />
          <Button size="sm" variant="ghost" onClick={() => setLeadOpen(true)}>
            Nuevo interesado
          </Button>
        </div>
      }
    >
      <Tabs value={tab} onValueChange={setTab} className="gap-0">
        <div className={cn(PAGE_GUTTER, "py-1.5")}>
          <TabsList variant="line">
            <TabsTrigger value="empresa">Empresa</TabsTrigger>
            <TabsTrigger value="foco">Mi foco</TabsTrigger>
            <TabsTrigger value="aprobaciones">
              Aprobaciones{pending > 0 ? <span className="ml-1 tabular-nums text-muted-foreground">{pending}</span> : null}
            </TabsTrigger>
            <TabsTrigger value="excepciones">Excepciones</TabsTrigger>
            <TabsTrigger value="bitacora">Bitácora</TabsTrigger>
            <TabsTrigger value="controles">Controles y carpeta</TabsTrigger>
          </TabsList>
        </div>
        <div className={cn(PAGE_GUTTER, "py-6")}>
          {tab === "empresa" ? <CompanyView /> : null}
          {tab === "foco" ? <FocusView /> : null}
          {tab === "aprobaciones" ? <ApprovalsView /> : null}
          {tab === "excepciones" ? <ExceptionsView /> : null}
          {tab === "bitacora" ? <AuditView /> : null}
          {tab === "controles" ? <ControlsView /> : null}
        </div>
      </Tabs>
      <NewLeadDialog open={leadOpen} onOpenChange={setLeadOpen} />
    </EmpresaShell>
  );
}

function CompanyView() {
  const wsId = useWorkspaceId();
  const p = useWorkspacePaths();
  const nav = useNavigation();
  const q = useQuery(bizOverviewOptions(wsId));
  if (q.isLoading) return <LoadingBlock rows={8} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  const o = q.data;
  const objectives = (o.objectives ?? []) as BizRow[];
  const decisions = o.open_decisions ?? [];
  const openTab = (tab: string) => nav.replace(`${nav.pathname}?tab=${tab}`);
  const bottleneck = AREAS.find((a) => a.code === o.bottleneck)?.name;
  return (
    <div className="mx-auto max-w-3xl space-y-14 pb-16">
      <CashHero cash={o.cash} coverage={o.cash_coverage} />

      <section className="divide-y divide-border">
        <ListRow primary="Meses de caja" secondary="Caja frente a la salida mensual normalizada" value={formatKpiValue(o.runway, "meses")} />
        <ListRow primary="Cuello de botella" secondary="Área con más indicadores en alerta" value={bottleneck ?? "—"} onClick={o.bottleneck ? () => nav.push(p.empresaArea(o.bottleneck)) : undefined} />
        <ListRow primary="Esperan tu decisión" secondary={`${o.owner_dependency.open_tasks_on_people} tareas abiertas en personas`} value={o.owner_dependency.pending_approvals} onClick={() => openTab("aprobaciones")} />
      </section>

      <Section title="Áreas">
        <div className="divide-y divide-border">
          {o.areas.map((a) => (
            <AreaPaceRow key={a.code} area={a} onOpen={() => nav.push(p.empresaArea(a.code))} />
          ))}
        </div>
      </Section>

      <Section
        title="Requiere atención"
        actions={o.exceptions_total > 0 ? <button type="button" className="text-label text-muted-foreground hover:text-foreground" onClick={() => openTab("excepciones")}>Ver todas · {o.exceptions_total}</button> : null}
      >
        {o.exceptions.length === 0 ? <EmptyHint title="Nada requiere tu atención" /> : (
          <div className="divide-y divide-border">
            {o.exceptions.slice(0, 5).map((e, i) => (
              <ListRow key={`${e.kind}-${e.entity_id}-${i}`} primary={e.title} secondary={e.what} value={<AreaTag area={e.area} />} onClick={() => openTab("excepciones")} />
            ))}
          </div>
        )}
      </Section>

      <Section title="Decisiones abiertas">
        {decisions.length === 0 ? <EmptyHint title="Nada pendiente de decidir" /> : (
          <div className="divide-y divide-border">
            {decisions.map((d) => (
              <RecordLink key={str(d.id)} entity="decision" id={d.id} className="block w-full hover:no-underline">
                <ListRow primary={str(d.title)} secondary={AREAS.find((a) => a.code === str(d.area))?.name} value={<span className="text-caption text-muted-foreground">{formatDate(d.created_at)}</span>} />
              </RecordLink>
            ))}
          </div>
        )}
      </Section>

      <Section title="Objetivos del trimestre">
        {objectives.length === 0 ? <EmptyHint title="Sin objetivos este trimestre" next="Créalos en Dirección → Gestión." /> : (
          <div className="divide-y divide-border">
            {objectives.map((ob) => (
              <RecordLink key={str(ob.id)} entity="objective" id={ob.id} className="block w-full hover:no-underline">
                <ListRow
                  primary={str(ob.title)}
                  secondary={AREAS.find((a) => a.code === str(ob.area))?.name}
                  value={<span className="text-caption text-muted-foreground">{str(ob.status) === "active" ? "Activo" : str(ob.status)}</span>}
                />
              </RecordLink>
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function FocusView() {
  const wsId = useWorkspaceId();
  const user = useAuthStore((s) => s.user);
  const p = useWorkspacePaths();
  const nav = useNavigation();
  const approvals = useQuery(bizListOptions(wsId, "approval", { status: "pending" }));
  const today = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Madrid" });
  const routines = useQuery(bizListOptions(wsId, "routine", { kind: "day" }));
  const todayRoutine = (routines.data ?? []).find((r) => str(r.period_key) === today);
  const tasks = useQuery({
    queryKey: ["biz", wsId, "my-tasks", user?.id],
    queryFn: async () => {
      const res = await api.listIssues({ assignee_id: user?.id, limit: 50 } as Parameters<typeof api.listIssues>[0]);
      return ((res as { issues?: unknown[] }).issues ?? []) as BizRow[];
    },
    enabled: Boolean(user?.id),
  });
  const { exec, pending } = useAction();
  const [focus, setFocus] = useState("");
  const [verdict, setVerdict] = useState("");
  const openTasks = (tasks.data ?? []).filter((t) => !["done", "cancelled"].includes(str(t.status)));
  return (
    <div className="grid gap-6 xl:grid-cols-[1.2fr_1fr]">
      <div className="space-y-6">
        <Section title={`Hoy · ${formatDate(today)}`}>
          <div className="space-y-2 rounded-lg border p-3">
            <div className="text-caption"><span className="text-muted-foreground">Foco: </span>{str(todayRoutine?.focus) || <span className="text-muted-foreground">sin foco todavía (el agente de Dirección lo propone en la apertura del día)</span>}</div>
            {str(todayRoutine?.plan) ? <div className="whitespace-pre-wrap text-caption text-muted-foreground">{str(todayRoutine?.plan)}</div> : null}
            {todayRoutine?.closed_at ? (
              <div className="text-caption"><span className="text-muted-foreground">Veredicto: </span>{str(todayRoutine?.verdict)}</div>
            ) : (
              <div className="grid gap-2 md:grid-cols-2">
                <Textarea placeholder="Mi foco de hoy" value={focus} onChange={(e) => setFocus(e.target.value)} className="min-h-14 text-caption" />
                <Textarea placeholder="Veredicto al cerrar el día" value={verdict} onChange={(e) => setVerdict(e.target.value)} className="min-h-14 text-caption" />
                <Button size="sm" variant="outline" disabled={!focus.trim() || pending} onClick={() => exec("routine.save", { kind: "day", period_key: today, focus }, "Foco guardado").then(() => setFocus(""))}>Fijar foco</Button>
                <Button size="sm" disabled={!verdict.trim() || pending} onClick={() => exec("routine.save", { kind: "day", period_key: today, verdict, close: true }, "Día cerrado").then(() => setVerdict(""))}>Cerrar el día</Button>
              </div>
            )}
          </div>
        </Section>
        <Section title={`Mis tareas abiertas (${openTasks.length})`}>
          {openTasks.length === 0 ? <EmptyHint title="No tienes tareas abiertas" /> : (
            <ul className="divide-y rounded-lg border">
              {openTasks.slice(0, 25).map((t) => (
                <li key={str(t.id)} className="flex items-center gap-2 px-3 py-1.5 text-caption">
                  <button type="button" className="min-w-0 flex-1 truncate text-left hover:underline" onClick={() => nav.push(p.issueDetail(str(t.id)))}>{str(t.title)}</button>
                  <Pill>{str(t.status)}</Pill>
                  <span className={cn("text-micro", str(t.due_date) && str(t.due_date) < today ? "text-destructive" : "text-muted-foreground")}>{t.due_date ? `vence ${formatDate(t.due_date)}` : ""}</span>
                </li>
              ))}
            </ul>
          )}
        </Section>
      </div>
      <Section title={`Esperan tu decisión (${approvals.data?.length ?? 0})`}>
        {(approvals.data ?? []).length === 0 ? <EmptyHint title="Ninguna aprobación pendiente" /> : (
          <div className="space-y-2">{(approvals.data ?? []).map((a) => <ApprovalCard key={str(a.id)} approval={a} canDecide />)}</div>
        )}
      </Section>
    </div>
  );
}

function ApprovalsView() {
  const wsId = useWorkspaceId();
  const meta = useQuery(bizMetaOptions(wsId));
  const role = str(meta.data?.actor?.role);
  const canDecide = role === "owner" || role === "admin";
  const pending = useQuery(bizListOptions(wsId, "approval", { status: "pending" }));
  const all = useQuery(bizListOptions(wsId, "approval", { limit: "60" }));
  const decided = (all.data ?? []).filter((a) => str(a.status) !== "pending");
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <Section title={`Pendientes (${pending.data?.length ?? 0})`}>
        {pending.isLoading ? <LoadingBlock /> : (pending.data ?? []).length === 0 ? <EmptyHint title="Ninguna aprobación pendiente" next="Las acciones sensibles de agentes (enviar, emitir, cobrar, publicar) aparecerán aquí." /> : (
          <div className="space-y-2">{(pending.data ?? []).map((a) => <ApprovalCard key={str(a.id)} approval={a} canDecide={canDecide} />)}</div>
        )}
      </Section>
      <Section title="Decididas recientemente">
        {decided.length === 0 ? <EmptyHint title="Todavía no hay decisiones" /> : <div className="space-y-2">{decided.slice(0, 20).map((a) => <ApprovalCard key={str(a.id)} approval={a} canDecide={false} />)}</div>}
      </Section>
    </div>
  );
}

function ExceptionsView() {
  const wsId = useWorkspaceId();
  const q = useQuery(bizOverviewOptions(wsId));
  const [area, setArea] = useState("");
  const all = q.data?.exceptions ?? [];
  const full = useQuery(bizExceptionsOptions(wsId, ""));
  const items = (full.data ?? all).filter((e) => !area || e.area === area);
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-1.5">
        <Button size="xs" variant={area === "" ? "default" : "outline"} onClick={() => setArea("")}>Todas</Button>
        {AREAS.map((a) => (
          <Button key={a.code} size="xs" variant={area === a.code ? "default" : "outline"} onClick={() => setArea(a.code)}>
            <AreaDot area={a.code} /> {a.name}
          </Button>
        ))}
      </div>
      {full.isLoading ? <LoadingBlock /> : <ExceptionList items={items} showArea />}
    </div>
  );
}

function AuditView() {
  const wsId = useWorkspaceId();
  const [actor, setActor] = useState("");
  const [view, setView] = useState<"audit" | "events">("audit");
  const audit = useQuery(bizAuditOptions(wsId, actor));
  const events = useQuery({ ...bizEventsOptions(wsId, ""), enabled: view === "events" });
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-1.5">
        <Button size="xs" variant={view === "audit" ? "default" : "outline"} onClick={() => setView("audit")}>Bitácora de acciones</Button>
        <Button size="xs" variant={view === "events" ? "default" : "outline"} onClick={() => setView("events")}>Eventos de negocio</Button>
        {view === "audit" ? (
          <span className="ml-3 flex gap-1.5">
            {[["", "Todos"], ["agent", "Agentes"], ["member", "Personas"], ["system", "Sistema"]].map(([v, l]) => (
              <Button key={v} size="xs" variant={actor === v ? "secondary" : "ghost"} onClick={() => setActor(v!)}>{l}</Button>
            ))}
          </span>
        ) : null}
      </div>
      {view === "audit" ? (
        audit.isLoading ? <LoadingBlock /> : (
          <ul className="divide-y rounded-lg border">
            {(audit.data ?? []).map((a) => (
              <li key={str(a.id)} className="flex items-start gap-3 px-3 py-1.5 text-caption">
                <span className="w-28 shrink-0 text-micro text-muted-foreground">{formatDateTime(a.at)}</span>
                <span className="w-40 shrink-0 truncate font-medium">{str(a.actor_name)}</span>
                <span className="font-mono text-micro">{str(a.action)}</span>
                {str(a.capability) ? <Pill>{str(a.capability)}</Pill> : null}
                {str(a.entity_type) && str(a.entity_id) ? <RecordLink entity={str(a.entity_type)} id={a.entity_id} className="text-micro text-muted-foreground">{str(a.entity_type)}</RecordLink> : null}
                <span className={cn("ml-auto text-micro", str(a.result) === "ok" ? "text-muted-foreground" : "text-destructive")}>{str(a.result)}</span>
              </li>
            ))}
          </ul>
        )
      ) : events.isLoading ? <LoadingBlock /> : (
        <ul className="divide-y rounded-lg border">
          {(events.data ?? []).map((e) => (
            <li key={str(e.id)} className="flex items-center gap-3 px-3 py-1.5 text-caption">
              <span className="w-28 shrink-0 text-micro text-muted-foreground">{formatDateTime(e.occurred_at)}</span>
              <span className="font-mono text-micro">{str(e.type)}</span>
              <span className="truncate font-mono text-micro text-muted-foreground">{str(e.idempotency_key)}</span>
              <Pill className="ml-auto">{str(e.status)}{Number(e.attempts) > 1 ? ` · ${str(e.attempts)} intentos` : ""}</Pill>
              {str(e.last_error) ? <span className="max-w-xs truncate text-micro text-destructive" title={str(e.last_error)}>{str(e.last_error)}</span> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function ControlsView() {
  const wsId = useWorkspaceId();
  const meta = useQuery(bizMetaOptions(wsId));
  const folder = useQuery(bizFolderOptions(wsId));
  const folderOp = useBizFolder();
  const { exec, pending } = useAction();
  const [rebuild, setRebuild] = useState<BizRow | null>(null);
  const settings = Object.fromEntries((meta.data?.settings ?? []).map((s) => [str(s.key), s.value]));
  const areaState = Object.fromEntries((meta.data?.area_state ?? []).map((a) => [str(a.code), a]));
  const role = str(meta.data?.actor?.role);
  const admin = role === "owner" || role === "admin";
  const runFolder = async (op: "export" | "preview" | "apply") => {
    try {
      const res = await folderOp.mutateAsync({ op });
      if (op === "export") toast.success("Carpeta exportada");
      else setRebuild(res as BizRow);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err));
    }
  };
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <div className="space-y-6">
        <Section title="Controles globales">
          <div className="divide-y rounded-lg border">
            <label className="flex items-center gap-3 px-3 py-2.5">
              <OctagonPause className="size-4 text-destructive" />
              <span className="flex-1">
                <span className="block text-body font-medium">Interruptor global (DIR-11)</span>
                <span className="text-caption text-muted-foreground">Cancela las ejecuciones en cola y bloquea cualquier escritura de agentes y automatismos. Las personas siguen trabajando.</span>
              </span>
              <Switch checked={settings.kill_switch === true} disabled={!admin || pending} onCheckedChange={(v) => exec("settings.set", { key: "kill_switch", value: v }, v ? "Interruptor activado" : "Interruptor desactivado")} />
            </label>
            <label className="flex items-center gap-3 px-3 py-2.5">
              <ShieldAlert className="size-4 text-warning" />
              <span className="flex-1">
                <span className="block text-body font-medium">Modo lectura</span>
                <span className="text-caption text-muted-foreground">Nadie puede modificar datos de negocio mientras esté activo.</span>
              </span>
              <Switch checked={settings.read_only === true} disabled={!admin || pending} onCheckedChange={(v) => exec("settings.set", { key: "read_only", value: v }, v ? "Modo lectura activado" : "Modo lectura desactivado")} />
            </label>
          </div>
          {!admin ? <p className="text-caption text-muted-foreground">Solo propietarios y administradores cambian los controles.</p> : null}
        </Section>
        <Section title="Pausa por área">
          <div className="divide-y rounded-lg border">
            {AREAS.map((a) => (
              <label key={a.code} className="flex items-center gap-3 px-3 py-2">
                <AreaTag area={a.code} />
                <span className="flex-1 text-caption text-muted-foreground">{a.transforms}</span>
                <span className="text-caption">{areaState[a.code]?.paused ? "En pausa" : "Activa"}</span>
                <Switch checked={!areaState[a.code]?.paused} disabled={!admin || pending} onCheckedChange={(v) => exec("area.set", { code: a.code, paused: !v }, v ? `${a.name} reanudada` : `${a.name} en pausa`)} />
              </label>
            ))}
          </div>
        </Section>
      </div>
      <Section title="Carpeta portable de la empresa">
        {folder.isLoading ? <LoadingBlock /> : folder.data ? (
          <div className="space-y-3 rounded-lg border p-3 text-caption">
            <div className="flex items-center gap-2"><FolderOpen className="size-4 text-muted-foreground" /><span className="font-mono text-micro">{folder.data.root || "Sin carpeta configurada"}</span></div>
            <div className="grid grid-cols-2 gap-1">
              <span className="text-muted-foreground">Registros en la carpeta</span><span>{folder.data.files ?? "—"}</span>
              <span className="text-muted-foreground">Escrituras pendientes</span><span>{folder.data.pending_writes}</span>
              <span className="text-muted-foreground">Editados fuera de TLS</span><span>{folder.data.modified_externally?.length ?? 0}</span>
              <span className="text-muted-foreground">Ficheros desconocidos</span><span>{folder.data.unknown_files?.length ?? 0}</span>
              <span className="text-muted-foreground">IDs duplicados (conflicto)</span><span className={cn((folder.data.duplicate_ids?.length ?? 0) > 0 && "font-medium text-destructive")}>{folder.data.duplicate_ids?.length ?? 0}</span>
              <span className="text-muted-foreground">Errores de formato</span><span>{folder.data.parse_errors?.length ?? 0}</span>
            </div>
            {(folder.data.modified_externally ?? []).length > 0 ? (
              <div>
                <div className="font-medium">Editados fuera de TLS</div>
                {(folder.data.modified_externally ?? []).slice(0, 10).map((m) => <div key={str(m.path)} className="font-mono text-micro text-muted-foreground">{str(m.path)}</div>)}
              </div>
            ) : null}
            {(folder.data.duplicate_ids ?? []).length > 0 ? (
              <div>
                <div className="font-medium text-destructive">Conflictos de ID</div>
                {(folder.data.duplicate_ids ?? []).map((d) => <div key={str(d.id)} className="font-mono text-micro">{str(d.id)}: {(d.paths as string[]).join(" · ")}</div>)}
              </div>
            ) : null}
            <div className="flex flex-wrap gap-1.5">
              <Button size="xs" variant="outline" disabled={!admin || folderOp.isPending} onClick={() => runFolder("export")}>Exportar todo</Button>
              <Button size="xs" variant="outline" disabled={!admin || folderOp.isPending} onClick={() => runFolder("preview")}>Comparar carpeta y base de datos</Button>
              <Button size="xs" disabled={!admin || folderOp.isPending || !rebuild} onClick={() => runFolder("apply")} title="Primero compara">Reconstruir desde la carpeta</Button>
            </div>
            {rebuild ? (
              <div className="rounded-md bg-muted/40 p-2">
                <div className="font-medium">{str(rebuild.mode) === "apply" ? "Reconstrucción aplicada" : "Vista previa"}</div>
                <div>Ficheros: {str(rebuild.files)} · iguales campo a campo: {str(rebuild.equal)} · distintos: {(rebuild.different as unknown[] | undefined)?.length ?? 0} · ausentes en la base: {(rebuild.missing_in_db as unknown[] | undefined)?.length ?? 0} · conflictos: {(rebuild.duplicate_ids as unknown[] | undefined)?.length ?? 0}{str(rebuild.mode) === "apply" ? ` · aplicados: ${str(rebuild.applied)}` : ""}</div>
                {((rebuild.different as BizRow[] | undefined) ?? []).slice(0, 8).map((d) => (
                  <div key={str(d.id)} className="mt-1 font-mono text-micro text-muted-foreground">
                    {str(d.path)}: {((d.fields as BizRow[]) ?? []).map((f) => str(f.field)).join(", ")}
                  </div>
                ))}
              </div>
            ) : null}
            <p className="text-micro text-muted-foreground">La carpeta es la copia legible y duradera; la base de datos, la proyección consultable. Cada cambio se escribe con un diario de recuperación.</p>
          </div>
        ) : <ErrorBlock error={folder.error} />}
      </Section>
    </div>
  );
}
