/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Bot, ExternalLink } from "lucide-react";
import { bizAreaOptions, bizListOptions, bizMetaOptions, formatKpiValue, formatMinor, MODE_LABELS, type BizRow } from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { useWorkspacePaths } from "@multica/core/paths";
import { Button } from "@multica/ui/components/ui/button";
import { Input } from "@multica/ui/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@multica/ui/components/ui/tabs";
import { cn } from "@multica/ui/lib/utils";
import { PAGE_GUTTER } from "../layout/page-header";
import { useNavigation } from "../navigation";
import { ExceptionList, KpiGrid } from "./blocks";
import { EmpresaShell } from "./overview-page";
import { AreaAnalysis, AreaManagement } from "./area-views";
import { areaOf, AreaDot, EmptyHint, ErrorBlock, LoadingBlock, Pill, RecordLink, Section, StatusBadge, str, num, useAction } from "./shared";
import { AskAgentDialog, BizTable } from "./widgets";

export function EmpresaAreaPage({ area }: { area: string }) {
  const nav = useNavigation();
  const wsId = useWorkspaceId();
  const p = useWorkspacePaths();
  const info = areaOf(area);
  const tab = nav.searchParams.get("tab") ?? "resumen";
  const detail = useQuery(bizAreaOptions(wsId, area));
  const [ask, setAsk] = useState<{ open: boolean; text?: string }>({ open: false });
  const setTab = (v: string) => {
    const sp = new URLSearchParams(nav.searchParams);
    if (v === "resumen") sp.delete("tab");
    else sp.set("tab", v);
    for (const k of ["view", "stage", "filter"]) if (v !== tab) sp.delete(k);
    const q = sp.toString();
    nav.replace(`${nav.pathname}${q ? `?${q}` : ""}`);
  };
  const agent = (detail.data?.agents ?? []).find((a) => str(a.area) === area);
  const paused = Boolean(detail.data?.state && (detail.data.state as BizRow).paused);
  return (
    <EmpresaShell
      title={
        <span className="inline-flex items-center gap-2">
          <AreaDot area={area} className="size-2.5" /> {info.name}
          <span className="hidden text-caption font-normal text-muted-foreground md:inline">· {info.transforms}</span>
          {paused ? <StatusBadge status="paused" /> : null}
        </span>
      }
      actions={
        <div className="flex items-center gap-2">
          {agent ? (
            <Button size="sm" variant="ghost" onClick={() => nav.push(p.agentDetail(str(agent.agent_id)))}>
              <Bot className={info.text} /> {str(agent.name)}
            </Button>
          ) : null}
          <Button size="sm" variant="outline" onClick={() => setAsk({ open: true })} disabled={!agent}>
            Pedir al agente
          </Button>
        </div>
      }
    >
      <Tabs value={tab} onValueChange={setTab} className="gap-0">
        <div className={cn(PAGE_GUTTER, "border-b py-1.5")}>
          <TabsList variant="line">
            <TabsTrigger value="resumen">Resumen</TabsTrigger>
            <TabsTrigger value="gestion">Gestión</TabsTrigger>
            <TabsTrigger value="analisis">Análisis</TabsTrigger>
            <TabsTrigger value="sistemas">Sistemas</TabsTrigger>
          </TabsList>
        </div>
        <div className={cn(PAGE_GUTTER, "py-4")}>
          {detail.isLoading ? <LoadingBlock rows={6} /> : detail.error || !detail.data ? <ErrorBlock error={detail.error} retry={() => detail.refetch()} /> : (
            <>
              {tab === "resumen" ? (<>
                <div className="space-y-6">
                  <Section title="Indicadores">
                    <KpiGrid kpis={detail.data.kpis} />
                  </Section>
                  <div className="grid gap-6 xl:grid-cols-[1.4fr_1fr]">
                    <Section title={`Excepciones (${detail.data.exceptions.length})`}>
                      <ExceptionList items={detail.data.exceptions} onAskAgent={agent ? (e) => setAsk({ open: true, text: `${e.title}\n\n${e.what}\n\nQué hacer: ${e.action}` }) : undefined} />
                    </Section>
                    <Section title="Madurez estimada">
                      <div className="rounded-lg border p-3 text-caption">
                        <div className="text-body font-medium">Etapa {detail.data.maturity.stage} · {detail.data.maturity.label}</div>
                        <ul className="mt-1 list-disc pl-4 text-muted-foreground">
                          {(detail.data.maturity.evidence ?? []).map((e) => <li key={e}>{e}</li>)}
                        </ul>
                        <p className="mt-2 text-micro text-muted-foreground">{detail.data.maturity.note}</p>
                      </div>
                    </Section>
                  </div>
                </div>
              </>) : null}
              {tab === "gestion" ? <AreaManagement area={area} /> : null}
              {tab === "analisis" ? <AreaAnalysis area={area} /> : null}
              {tab === "sistemas" ? <AreaSystems area={area} /> : null}
            </>
          )}
        </div>
      </Tabs>
      <AskAgentDialog key={ask.text ?? "ask"} area={area} open={ask.open} initial={ask.text} onOpenChange={(o) => setAsk({ open: o })} />
    </EmpresaShell>
  );
}

const STATUS_LABEL: Record<string, string> = { implemented: "Implementada", partial: "Parcial", simulated: "Simulada", pending: "Pendiente" };

function AreaSystems({ area }: { area: string }) {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const meta = useQuery(bizMetaOptions(wsId));
  const detail = useQuery(bizAreaOptions(wsId, area));
  const kpis = useQuery(bizListOptions(wsId, "kpi", { area }));
  const services = useQuery({ ...bizListOptions(wsId, "service", {}), enabled: area === "entrega" || area === "ventas" });
  const { exec, pending } = useAction();
  const role = str(meta.data?.actor?.role);
  const admin = role === "owner" || role === "admin";
  const caps = (meta.data?.capabilities ?? []).filter((c) => c.area === area);
  const [edit, setEdit] = useState<Record<string, string>>({});
  return (
    <div className="space-y-6">
      <Section title={`Capacidades (${caps.length}) · modo de ejecución`}>
        <BizTable
          rows={caps as unknown as BizRow[]}
          columns={[
            { key: "code", label: "Código", className: "w-20 font-mono" },
            { key: "name", label: "Capacidad", render: (c) => <span title={`${str(c.trigger)} → ${str(c.output)}`}>{str(c.name)}</span> },
            { key: "level", label: "Nivel", className: "w-14", render: (c) => ({ E: "Esencial", R: "Recom.", O: "Opcional" } as Record<string, string>)[str(c.level)] ?? str(c.level) },
            { key: "executor", label: "Ejecutor", className: "w-20" },
            { key: "status", label: "En esta build", className: "w-28", render: (c) => <Pill>{STATUS_LABEL[str(c.status)] ?? str(c.status)}</Pill> },
            {
              key: "mode", label: "Modo", className: "w-52",
              render: (c) => (
                <select
                  aria-label={`Modo de ${str(c.code)}`}
                  className="h-7 w-full rounded-md border bg-transparent px-1 text-caption"
                  value={str(c.mode)}
                  disabled={!admin || pending}
                  onClick={(e) => e.stopPropagation()}
                  onChange={(e) => exec("policy.set", { capability: str(c.code), mode: e.target.value }, `${str(c.code)}: ${MODE_LABELS[e.target.value]}`)}
                >
                  {Object.entries(MODE_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                </select>
              ),
            },
            { key: "sensitive", label: "Sensible", className: "w-16", render: (c) => (c.sensitive ? "Sí" : "") },
          ]}
        />
        <p className="text-caption text-muted-foreground">
          Manual: solo personas. Asistido: el agente prepara borradores. Supervisado: las acciones sensibles piden aprobación. Autónomo: ejecuta dentro de los límites aprobados. Un agente nunca cambia estos modos.
        </p>
      </Section>

      <div className="grid gap-6 xl:grid-cols-2">
        <Section title="Roles del área">
          {(detail.data?.roles ?? []).length === 0 ? <EmptyHint title="Sin roles definidos" /> : (
            <div className="space-y-2">
              {(detail.data?.roles ?? []).map((r) => (
                <div key={str(r.id)} className="rounded-lg border p-3 text-caption">
                  <div className="flex items-center gap-2">
                    <RecordLink entity="role" id={r.id} className="text-body font-medium">{str(r.name)}</RecordLink>
                    <Pill className="ml-auto">{str(r.occupant_name) || "Vacante"} {str(r.occupant_type) === "agent" ? "· agente" : str(r.occupant_type) === "member" ? "· persona" : ""}</Pill>
                  </div>
                  <p className="mt-1">{str(r.mission)}</p>
                  <p className="text-muted-foreground"><span className="font-medium">Decide:</span> {str(r.decisions)} · <span className="font-medium">Límites:</span> {str(r.limits)}</p>
                  {(r.kpi_codes as string[] | undefined)?.length ? <p className="text-muted-foreground">KPI: {(r.kpi_codes as string[]).join(", ")}</p> : null}
                </div>
              ))}
            </div>
          )}
        </Section>
        <Section title="Agente del área">
          {(detail.data?.agents ?? []).filter((a) => str(a.area) === area).map((a) => (
            <div key={str(a.agent_id)} className="rounded-lg border p-3 text-caption">
              <div className="flex items-center gap-2">
                <Bot className={cn("size-4", areaOf(area).text)} />
                <span className="text-body font-medium">{str(a.name)}</span>
                {a.is_coordinator ? <Pill>Coordinador</Pill> : null}
                <Button size="xs" variant="ghost" className="ml-auto" onClick={() => nav.push(p.agentDetail(str(a.agent_id)))}>
                  Instrucciones <ExternalLink />
                </Button>
              </div>
              <p className="mt-1 text-muted-foreground">{str(a.description)}</p>
              <p className="mt-1">Presupuesto mensual {formatMinor(num(a.budget_monthly_minor))} · profundidad de delegación {str(a.max_delegation_depth)} · máx. {str(a.max_steps)} pasos</p>
            </div>
          ))}
          {(detail.data?.agents ?? []).filter((a) => str(a.area) === area).length === 0 ? <EmptyHint title="Sin agente asignado" next="Asigna uno desde Equipo." /> : null}
        </Section>
      </div>

      {(area === "entrega" || area === "ventas") && (services.data ?? []).length > 0 ? (
        <Section title="Servicios y procesos">
          <div className="grid gap-3 xl:grid-cols-2">
            {(services.data ?? []).map((s) => {
              const tpl = (s.template as { phases?: { name: string; tasks: { title: string; assignee?: string }[] }[]; done_when?: string }) ?? {};
              const offer = s.offer as BizRow | null;
              return (
                <div key={str(s.id)} className="rounded-lg border p-3 text-caption">
                  <div className="flex items-center gap-2">
                    <RecordLink entity="service" id={s.id} className="text-body font-medium">{str(s.name)}</RecordLink>
                    <Pill>{str(s.recurrence)}</Pill>
                    <Pill>plantilla v{str(s.template_version)}</Pill>
                    {offer ? <Pill className="ml-auto">{formatMinor(num(offer.price_minor))} / {str(offer.billing_unit)} · oferta v{str(offer.version)}</Pill> : null}
                  </div>
                  <p className="mt-1 text-muted-foreground">Canvas: {str(s.workflow_name)}</p>
                  <ol className="mt-1 space-y-0.5">
                    {(tpl.phases ?? []).map((ph) => (
                      <li key={ph.name}>
                        <span className="font-medium">{ph.name}:</span>{" "}
                        <span className="text-muted-foreground">{ph.tasks.map((t) => `${t.title}${t.assignee?.startsWith("agent:") ? " (agente)" : " (persona)"}`).join(" · ")}</span>
                      </li>
                    ))}
                  </ol>
                  {tpl.done_when ? <p className="mt-1"><span className="font-medium">Terminado cuando:</span> {tpl.done_when}</p> : null}
                </div>
              );
            })}
          </div>
        </Section>
      ) : null}

      <Section title="Definición de indicadores">
        <BizTable
          rows={kpis.data}
          isLoading={kpis.isLoading}
          columns={[
            { key: "code", label: "Código", className: "w-24 font-mono" },
            { key: "name", label: "Indicador" },
            { key: "formula", label: "Fórmula", className: "text-muted-foreground" },
            { key: "unit", label: "Unidad", className: "w-16" },
            {
              key: "target", label: "Meta", className: "w-28",
              render: (k) => (
                <Input
                  className="h-7 w-24 text-caption"
                  disabled={!admin}
                  defaultValue={k.target === null || k.target === undefined ? "" : str(k.target)}
                  onClick={(e) => e.stopPropagation()}
                  onChange={(e) => setEdit((x) => ({ ...x, [str(k.code)]: e.target.value }))}
                  onBlur={() => {
                    const v = edit[str(k.code)];
                    if (v !== undefined && v !== "" && !Number.isNaN(Number(v))) exec("kpi.update", { code: str(k.code), target: Number(v) }, "Meta actualizada");
                  }}
                />
              ),
            },
            { key: "alert", label: "Alerta", className: "w-20", render: (k) => (k.alert === null || k.alert === undefined ? "—" : formatKpiValue(Number(k.alert), str(k.unit))) },
          ]}
        />
      </Section>
    </div>
  );
}

/** Route entry: reads the area from `/{slug}/empresa/{area}` via the platform navigation adapter. */
export function EmpresaAreaRoute() {
  const nav = useNavigation();
  const area = nav.pathname.split("/").filter(Boolean)[2] ?? "direccion";
  return <EmpresaAreaPage key={area} area={area} />;
}
