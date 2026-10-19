/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useMemo, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { ExternalLink, Plus, Upload } from "lucide-react";
import {
  bizKpisOptions,
  bizListOptions,
  bizOverviewOptions,
  bizProjectsOptions,
  bizTeamOptions,
  CONTENT_STATUS_LABELS,
  CONTENT_STATUS_ORDER,
  formatDate,
  formatDateTime,
  formatKpiValue,
  formatMinor,
  INVOICE_STATUS_LABELS,
  MOVEMENT_STATUS_LABELS,
  NATURE_LABELS,
  PERIOD_STATUS_LABELS,
  STAGE_LABELS,
  type BizRow,
} from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { useWorkspacePaths } from "@multica/core/paths";
import { Button } from "@multica/ui/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@multica/ui/components/ui/dialog";
import { Input } from "@multica/ui/components/ui/input";
import { Textarea } from "@multica/ui/components/ui/textarea";
import { cn } from "@multica/ui/lib/utils";
import { useNavigation } from "../navigation";
import { AREAS, AreaDot, EmptyHint, LoadingBlock, Pill, RecordLink, Section, StatusBadge, str, num, useAction, useInspector } from "./shared";
import { BizTable } from "./widgets";

// --- Small building blocks --------------------------------------------------

function SubNav({ value, options, onChange }: { value: string; options: [string, string][]; onChange: (v: string) => void }) {
  return (
    <div className="mb-3 flex flex-wrap gap-1.5" role="tablist">
      {options.map(([v, l]) => (
        <Button key={v} role="tab" aria-selected={value === v} size="xs" variant={value === v ? "default" : "outline"} onClick={() => onChange(v)}>
          {l}
        </Button>
      ))}
    </div>
  );
}

function useSubView(defaultView: string): [string, (v: string) => void] {
  const nav = useNavigation();
  const view = nav.searchParams.get("view") ?? defaultView;
  const set = (v: string) => {
    const sp = new URLSearchParams(nav.searchParams);
    sp.set("view", v);
    nav.replace(`${nav.pathname}?${sp.toString()}`);
  };
  return [view, set];
}

function Bars({ rows, format }: { rows: { label: ReactNode; value: number; hint?: string }[]; format?: (v: number) => string }) {
  const max = Math.max(1, ...rows.map((r) => Math.abs(r.value)));
  if (rows.length === 0) return <EmptyHint title="Sin datos para este análisis" />;
  return (
    <div className="space-y-1.5">
      {rows.map((r, i) => (
        <div key={i} className="grid grid-cols-[10rem_1fr_6rem] items-center gap-2 text-caption">
          <span className="truncate text-muted-foreground">{r.label}</span>
          <div className="h-2.5 rounded bg-muted">
            <div className={cn("h-2.5 rounded", r.value < 0 ? "bg-destructive/70" : "bg-brand/70")} style={{ width: `${(Math.abs(r.value) / max) * 100}%` }} />
          </div>
          <span className="text-right tabular-nums" title={r.hint}>{format ? format(r.value) : r.value}</span>
        </div>
      ))}
    </div>
  );
}

function Kanban({ columns, cards, render }: { columns: { key: string; label: string; hint?: string }[]; cards: BizRow[]; render: (c: BizRow) => ReactNode }) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-2">
      {columns.map((col) => {
        const items = cards.filter((c) => str(c.__col) === col.key);
        return (
          <div key={col.key} className="flex w-64 shrink-0 flex-col rounded-lg bg-muted/40 p-1.5">
            <div className="flex items-center gap-1.5 px-1.5 py-1 text-caption font-medium">
              {col.label}
              <span className="text-muted-foreground">{items.length}</span>
              {col.hint ? <span className="ml-auto text-micro font-normal text-muted-foreground">{col.hint}</span> : null}
            </div>
            <div className="flex flex-col gap-1.5">
              {items.length === 0 ? <p className="px-1.5 py-3 text-center text-micro text-muted-foreground">Vacío</p> : items.map(render)}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function Card({ onClick, children, className }: { onClick?: () => void; children: ReactNode; className?: string }) {
  return (
    <button type="button" onClick={onClick} className={cn("flex flex-col gap-1 rounded-md border bg-card p-2 text-left text-caption shadow-xs hover:bg-accent/40", className)}>
      {children}
    </button>
  );
}

// --- Dispatch ------------------------------------------------------------------

export function AreaManagement({ area }: { area: string }) {
  switch (area) {
    case "ventas": return <SalesManagement />;
    case "entrega": return <DeliveryManagement />;
    case "finanzas": return <FinanceManagement />;
    case "marca": return <BrandManagement />;
    case "equipo": return <TeamManagement />;
    default: return <DirectionManagement />;
  }
}

export function AreaAnalysis({ area }: { area: string }) {
  switch (area) {
    case "ventas": return <SalesAnalysis />;
    case "entrega": return <DeliveryAnalysis />;
    case "finanzas": return <FinanceAnalysis />;
    case "marca": return <BrandAnalysis />;
    case "equipo": return <TeamAnalysis />;
    default: return <DirectionAnalysis />;
  }
}

// --- Ventas ---------------------------------------------------------------------

const OPEN_STAGES = ["entrada", "cualificacion", "diagnostico", "propuesta", "negociacion", "aceptada"];

function SalesManagement() {
  const wsId = useWorkspaceId();
  const open = useInspector();
  const [view, setView] = useSubView("embudo");
  const [service, setService] = useState("");
  const opps = useQuery(bizListOptions(wsId, "opportunity", {}));
  const contacts = useQuery({ ...bizListOptions(wsId, "contact", {}), enabled: view === "contactos" });
  const orgs = useQuery({ ...bizListOptions(wsId, "organization", {}), enabled: view === "organizaciones" });
  const offers = useQuery({ ...bizListOptions(wsId, "offer", {}), enabled: view === "ofertas" });
  const rows = (opps.data ?? []).filter((o) => !service || str(o.service_code) === service);
  return (
    <div>
      <SubNav value={view} onChange={setView} options={[["embudo", "Embudo"], ["cerradas", "Ganadas y perdidas"], ["contactos", "Contactos"], ["organizaciones", "Organizaciones"], ["ofertas", "Ofertas y precios"]]} />
      {view === "embudo" ? (
        <>
          <div className="mb-2 flex gap-1.5">
            {[["", "Todos los servicios"], ["RENTA", "Renta"], ["TRIM", "Trimestrales"]].map(([v, l]) => (
              <Button key={v} size="xs" variant={service === v ? "secondary" : "ghost"} onClick={() => setService(v!)}>{l}</Button>
            ))}
          </div>
          {opps.isLoading ? <LoadingBlock /> : (
            <Kanban
              columns={OPEN_STAGES.map((s) => {
                const total = rows.filter((o) => str(o.stage) === s).reduce((a, o) => a + num(o.value_minor), 0);
                return { key: s, label: STAGE_LABELS[s]!, hint: total ? formatMinor(total) : undefined };
              })}
              cards={rows.map((o) => ({ ...o, __col: o.stage }))}
              render={(o) => {
                const stale = num(o.days_since_contact) > 14;
                const due = str(o.next_action_on) && str(o.next_action_on) < new Date().toISOString().slice(0, 10);
                return (
                  <Card key={str(o.id)} onClick={() => open({ entity: "opportunity", id: str(o.id) })}>
                    <span className="font-medium">{str(o.organization_name) || str(o.contact_name)}</span>
                    <span className="text-muted-foreground">{str(o.service_name)} · {formatMinor(num(o.value_minor))}</span>
                    {str(o.next_action) ? <span className={cn("line-clamp-2", due ? "text-destructive" : "text-muted-foreground")}>→ {str(o.next_action)} {o.next_action_on ? `(${formatDate(o.next_action_on)})` : ""}</span> : null}
                    <span className="flex flex-wrap gap-1">
                      <Pill>{str(o.channel)}</Pill>
                      {stale ? <Pill className="border-warning text-warning">{num(o.days_since_contact)} días sin contacto</Pill> : null}
                      {str(o.owner_name) ? <Pill>{str(o.owner_name)}</Pill> : null}
                    </span>
                  </Card>
                );
              }}
            />
          )}
        </>
      ) : null}
      {view === "cerradas" ? (
        <BizTable
          entity="opportunity"
          rows={(opps.data ?? []).filter((o) => ["ganada", "perdida", "pausada"].includes(str(o.stage)))}
          isLoading={opps.isLoading}
          columns={[
            { key: "title", label: "Oportunidad" },
            { key: "stage", label: "Etapa", render: (o) => STAGE_LABELS[str(o.stage)] },
            { key: "value_minor", label: "Valor", align: "right", render: (o) => formatMinor(num(o.value_minor)) },
            { key: "won_at", label: "Ganada", render: (o) => formatDate(o.won_at) },
            { key: "lost_reason", label: "Motivo de pérdida" },
          ]}
        />
      ) : null}
      {view === "contactos" ? (
        <BizTable entity="contact" rows={contacts.data} isLoading={contacts.isLoading} columns={[
          { key: "name", label: "Nombre" },
          { key: "organization_name", label: "Organización" },
          { key: "kind", label: "Tipo" },
          { key: "email", label: "Email" },
          { key: "source_channel", label: "Canal" },
          { key: "source_content_title", label: "Pieza de origen" },
          { key: "last_contact_at", label: "Último contacto", render: (c) => formatDate(c.last_contact_at) },
        ]} />
      ) : null}
      {view === "organizaciones" ? (
        <BizTable entity="organization" rows={orgs.data} isLoading={orgs.isLoading} columns={[
          { key: "name", label: "Nombre" },
          { key: "kind", label: "Tipo" },
          { key: "sector", label: "Sector" },
          { key: "city", label: "Ciudad" },
          { key: "contacts", label: "Contactos", align: "right" },
          { key: "opportunities", label: "Oportunidades", align: "right" },
          { key: "billed_minor", label: "Facturado", align: "right", render: (o) => formatMinor(num(o.billed_minor)) },
        ]} />
      ) : null}
      {view === "ofertas" ? (
        <>
          <BizTable entity="offer" rows={offers.data} isLoading={offers.isLoading} columns={[
            { key: "service_name", label: "Servicio" },
            { key: "version", label: "Versión", render: (o) => `v${str(o.version)}` },
            { key: "price_minor", label: "Precio", align: "right", render: (o) => formatMinor(num(o.price_minor)) },
            { key: "tax_rate_bp", label: "IVA", render: (o) => `${num(o.tax_rate_bp) / 100} %` },
            { key: "billing_unit", label: "Unidad" },
            { key: "active", label: "Vigente", render: (o) => (o.active ? "Sí" : "Histórica") },
            { key: "conditions", label: "Condiciones", className: "text-muted-foreground" },
          ]} />
          <p className="mt-2 text-caption text-muted-foreground">Un único precio vigente por servicio. Propuestas aceptadas y facturas guardan su propia instantánea.</p>
        </>
      ) : null}
    </div>
  );
}

function SalesAnalysis() {
  const wsId = useWorkspaceId();
  const opps = useQuery(bizListOptions(wsId, "opportunity", { archived: "true" }));
  const kpis = useQuery(bizKpisOptions(wsId, "ventas"));
  const rows = opps.data ?? [];
  const byStage = OPEN_STAGES.concat(["ganada", "perdida"]).map((s) => ({ label: STAGE_LABELS[s], value: rows.filter((o) => str(o.stage) === s).length }));
  const byChannel = Object.entries(rows.reduce<Record<string, number>>((a, o) => ({ ...a, [str(o.channel) || "—"]: (a[str(o.channel) || "—"] ?? 0) + 1 }), {})).map(([k, v]) => ({ label: k, value: v }));
  const weighted = rows.filter((o) => OPEN_STAGES.includes(str(o.stage))).reduce((a, o) => a + (num(o.value_minor) * num(o.probability)) / 100, 0);
  const lost = rows.filter((o) => str(o.stage) === "perdida");
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <Section title="Embudo por etapa (nº de oportunidades)"><Bars rows={byStage} /></Section>
      <Section title="Entradas por canal (atribución)"><Bars rows={byChannel} /></Section>
      <Section title="Previsión ponderada">
        <div className="rounded-lg border p-3">
          <div className="text-title font-semibold">{formatMinor(weighted)}</div>
          <p className="text-caption text-muted-foreground">Σ valor × probabilidad de etapa de las oportunidades abiertas. Es una previsión: no es venta aceptada, ni facturación, ni cobro.</p>
          <div className="mt-2 flex flex-wrap gap-3 text-caption">
            {(kpis.data ?? []).map((k) => <span key={k.code}>{k.name}: <strong>{formatKpiValue(k.value, k.unit)}</strong></span>)}
          </div>
        </div>
      </Section>
      <Section title="Motivos de pérdida">
        {lost.length === 0 ? <EmptyHint title="Sin pérdidas registradas" /> : (
          <ul className="space-y-1 text-caption">{lost.map((o) => <li key={str(o.id)}><RecordLink entity="opportunity" id={o.id} className="font-medium">{str(o.title)}</RecordLink>: {str(o.lost_reason)}</li>)}</ul>
        )}
      </Section>
    </div>
  );
}

// --- Entrega ----------------------------------------------------------------------

function DeliveryManagement() {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const services = useQuery(bizListOptions(wsId, "service", {}));
  const projects = useQuery(bizProjectsOptions(wsId));
  const [showClosed, setShowClosed] = useState(false);
  const today = new Date().toISOString().slice(0, 10);
  const all = projects.data ?? [];
  const other = all.filter((pr) => !pr.service_id);
  return (
    <div className="space-y-6">
      <div className="flex items-center gap-2">
        <Button size="xs" variant={showClosed ? "secondary" : "ghost"} onClick={() => setShowClosed((v) => !v)}>{showClosed ? "Ocultar cerrados" : "Mostrar cerrados"}</Button>
        <span className="text-caption text-muted-foreground">Cada servicio tiene su canvas: las columnas del tablero del proyecto son las etapas del proceso.</span>
      </div>
      {services.isLoading || projects.isLoading ? <LoadingBlock /> : (services.data ?? []).map((s) => {
        const list = all.filter((pr) => str(pr.service_id) === str(s.id) && (showClosed || ["planned", "in_progress"].includes(str(pr.status))));
        return (
          <Section key={str(s.id)} title={<span className="inline-flex items-center gap-2"><AreaDot area="entrega" /> {str(s.name)} <Pill>canvas propio</Pill> <Pill>{str(s.recurrence) === "quarterly" ? "trimestral" : str(s.recurrence) === "annual" ? "anual" : str(s.recurrence)}</Pill></span>}>
            {list.length === 0 ? <EmptyHint title="Sin proyectos activos" next="Los proyectos nacen al confirmarse el cobro de una oportunidad de este servicio." /> : (
              <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
                {list.map((pr) => {
                  const total = num(pr.tasks);
                  const done = num(pr.tasks_done);
                  const overdue = num(pr.tasks_overdue);
                  return (
                    <Card key={str(pr.id)} onClick={() => nav.push(p.projectDetail(str(pr.id)))} className={cn(overdue > 0 && "border-destructive/40")}>
                      <span className="flex items-center gap-2 font-medium">{str(pr.organization_name) || str(pr.title)} <ExternalLink className="ml-auto size-3 text-muted-foreground" /></span>
                      <div className="h-1.5 rounded bg-muted"><div className="h-1.5 rounded bg-area-entrega" style={{ width: `${total ? (done / total) * 100 : 0}%` }} /></div>
                      <span className="text-muted-foreground">{done}/{total} tareas · responsable {str(pr.lead_name) || "—"}</span>
                      <span className="flex flex-wrap gap-1">
                        <Pill>{str(pr.status) === "completed" ? "Cerrado" : str(pr.status) === "in_progress" ? "En curso" : str(pr.status)}</Pill>
                        {overdue > 0 ? <Pill className="border-destructive text-destructive">{overdue} vencidas</Pill> : null}
                        {pr.next_due ? <Pill className={cn(str(pr.next_due) < today && "text-destructive")}>próximo vencimiento {formatDate(pr.next_due)}</Pill> : null}
                      </span>
                    </Card>
                  );
                })}
              </div>
            )}
          </Section>
        );
      })}
      {other.length > 0 ? (
        <Section title="Otros proyectos (estratégicos o sin servicio)">
          <BizTable rows={other} onRowClick={(r) => nav.push(p.projectDetail(str(r.id)))} columns={[
            { key: "title", label: "Proyecto" },
            { key: "kind", label: "Tipo", render: (r) => str(r.kind) || "sin vincular" },
            { key: "objective_title", label: "Objetivo", render: (r) => str(r.objective_title) || <span className="text-destructive">Sin objetivo</span> },
            { key: "status", label: "Estado" },
          ]} />
        </Section>
      ) : null}
    </div>
  );
}

function DeliveryAnalysis() {
  const wsId = useWorkspaceId();
  const projects = useQuery(bizProjectsOptions(wsId));
  const kpis = useQuery(bizKpisOptions(wsId, "entrega"));
  const team = useQuery(bizTeamOptions(wsId));
  const active = (projects.data ?? []).filter((pr) => pr.service_id && pr.status === "in_progress");
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <Section title="Indicadores">
        <div className="flex flex-wrap gap-3 text-caption">{(kpis.data ?? []).map((k) => <span key={k.code} className="inline-flex items-center gap-1">{k.name}: <strong>{formatKpiValue(k.value, k.unit)}</strong> <StatusBadge status={k.status} /></span>)}</div>
      </Section>
      <Section title="Avance de proyectos en curso (% tareas hechas)">
        <Bars rows={active.map((pr) => ({ label: str(pr.organization_name) || str(pr.title), value: num(pr.tasks) ? Math.round((num(pr.tasks_done) / num(pr.tasks)) * 100) : 0 }))} format={(v) => `${v} %`} />
      </Section>
      <Section title="Ocupación: personas (tareas abiertas)">
        <Bars rows={(team.data?.members ?? []).map((m) => ({ label: str(m.name), value: num(m.open_tasks) }))} />
      </Section>
      <Section title="Ocupación: agentes (ejecuciones activas)">
        <Bars rows={(team.data?.agents ?? []).filter((a) => a.area).map((a) => ({ label: str(a.name), value: num(a.active_runs) }))} />
        <p className="text-micro text-muted-foreground">Horas humanas y ejecuciones de agentes son unidades distintas: no se suman.</p>
      </Section>
    </div>
  );
}

// --- Finanzas ---------------------------------------------------------------------

function FinanceManagement() {
  const wsId = useWorkspaceId();
  const [view, setView] = useSubView("emitidas");
  const issued = useQuery({ ...bizListOptions(wsId, "invoice", { direction: "issued" }), enabled: view === "emitidas" });
  const received = useQuery({ ...bizListOptions(wsId, "invoice", { direction: "received" }), enabled: view === "recibidas" });
  const [movStatus, setMovStatus] = useState("");
  const movements = useQuery({ ...bizListOptions(wsId, "movement", movStatus ? { status: movStatus } : {}), enabled: view === "bancos" });
  const accounts = useQuery({ ...bizListOptions(wsId, "account", {}), enabled: view === "bancos" });
  const periods = useQuery({ ...bizListOptions(wsId, "period", {}), enabled: view === "trimestres" });
  const { exec, pending } = useAction();
  const [importOpen, setImportOpen] = useState(false);
  const invoiceColumns = (dir: "issued" | "received") => [
    { key: "number", label: "Número", render: (i: BizRow) => str(i.number) || <span className="text-muted-foreground">Borrador</span> },
    { key: "organization_name", label: dir === "issued" ? "Cliente" : "Proveedor" },
    { key: "issue_date", label: "Fecha", render: (i: BizRow) => formatDate(i.issue_date) },
    { key: "due_date", label: "Vence", render: (i: BizRow) => <span className={cn(num(i.days_overdue) > 0 && ["issued", "partially_paid"].includes(str(i.status)) && "text-destructive")}>{formatDate(i.due_date)}</span> },
    { key: "total_minor", label: "Total", align: "right" as const, render: (i: BizRow) => formatMinor(num(i.total_minor)) },
    { key: "paid_minor", label: dir === "issued" ? "Cobrado" : "Pagado", align: "right" as const, render: (i: BizRow) => formatMinor(num(i.paid_minor)) },
    { key: "status", label: "Estado", render: (i: BizRow) => INVOICE_STATUS_LABELS[str(i.status)] ?? str(i.status) },
    ...(dir === "received" ? [{ key: "document_path", label: "Justificante", render: (i: BizRow) => (str(i.document_path) ? "Adjunto" : <span className="text-destructive">Falta</span>) }] : []),
  ];
  return (
    <div>
      <SubNav value={view} onChange={setView} options={[["emitidas", "Facturas emitidas"], ["recibidas", "Facturas recibidas"], ["bancos", "Bancos y conciliación"], ["trimestres", "Trimestres"]]} />
      {view === "emitidas" ? <BizTable entity="invoice" rows={issued.data} isLoading={issued.isLoading} columns={invoiceColumns("issued")} /> : null}
      {view === "recibidas" ? <BizTable entity="invoice" rows={received.data} isLoading={received.isLoading} columns={invoiceColumns("received")} /> : null}
      {view === "bancos" ? (
        <div className="space-y-4">
          <div className="grid gap-2 md:grid-cols-2">
            {(accounts.data ?? []).map((a) => (
              <div key={str(a.id)} className="rounded-lg border p-3 text-caption">
                <div className="font-medium">{str(a.name)}</div>
                <div className="text-muted-foreground">{str(a.iban_masked)} · {num(a.movements)} movimientos</div>
                <div className="mt-1">Saldo según banco: <strong>{a.last_balance_minor === null || a.last_balance_minor === undefined ? "desconocido" : formatMinor(num(a.last_balance_minor))}</strong></div>
              </div>
            ))}
          </div>
          <div className="flex flex-wrap items-center gap-1.5">
            {[["", "Todos"], ["proposed", "Propuestos"], ["unreconciled", "Sin conciliar"], ["reconciled", "Conciliados"], ["ignored", "Sin factura"]].map(([v, l]) => (
              <Button key={v} size="xs" variant={movStatus === v ? "secondary" : "ghost"} onClick={() => setMovStatus(v!)}>{l}</Button>
            ))}
            <Button size="xs" className="ml-auto" variant="outline" onClick={() => setImportOpen(true)}><Upload /> Importar extracto CSV</Button>
          </div>
          <BizTable entity="movement" rows={movements.data} isLoading={movements.isLoading} columns={[
            { key: "booked_on", label: "Fecha", render: (m) => formatDate(m.booked_on) },
            { key: "description", label: "Concepto" },
            { key: "amount_minor", label: "Importe", align: "right", render: (m) => <span className={cn(num(m.amount_minor) < 0 && "text-destructive")}>{formatMinor(num(m.amount_minor))}</span> },
            { key: "nature", label: "Naturaleza", render: (m) => NATURE_LABELS[str(m.nature)] ?? str(m.nature) },
            { key: "status", label: "Conciliación", render: (m) => <span>{MOVEMENT_STATUS_LABELS[str(m.status)]}{str(m.invoice_number) ? ` · ${str(m.invoice_number)}` : ""}</span> },
            {
              key: "actions", label: "", render: (m) => str(m.status) === "proposed" ? (
                <Button size="xs" disabled={pending} onClick={(e) => { e.stopPropagation(); void exec("payment.confirm", { invoice_id: str(m.invoice_id), movement_id: str(m.id) }, "Conciliado y confirmado"); }}>Confirmar</Button>
              ) : null,
            },
          ]} />
          <ImportStatementDialog open={importOpen} onOpenChange={setImportOpen} accounts={accounts.data ?? []} />
        </div>
      ) : null}
      {view === "trimestres" ? (
        <>
          <div className="mb-2 flex gap-2">
            <Button size="xs" variant="outline" disabled={pending} onClick={() => { const d = new Date(); const q = Math.floor(d.getMonth() / 3) + 1; void exec("period.prepare", { year: d.getFullYear(), quarter: q }, "Paquete del trimestre en curso preparado"); }}>
              <Plus /> Preparar trimestre en curso
            </Button>
          </div>
          <BizTable entity="period" rows={periods.data} isLoading={periods.isLoading} columns={[
            { key: "year", label: "Periodo", render: (r) => `${str(r.year)} T${str(r.quarter)}` },
            { key: "status", label: "Estado", render: (r) => PERIOD_STATUS_LABELS[str(r.status)] },
            { key: "summary", label: "Excepciones", render: (r) => { const e = ((r.summary as BizRow)?.exceptions as BizRow[] | undefined) ?? []; return e.length ? e.map((x) => `${str(x.message)}: ${str(x.count)}`).join(" · ") : "Ninguna"; } },
            { key: "package_path", label: "Paquete", render: (r) => <span className="font-mono text-micro">{str(r.package_path)}</span> },
            { key: "updated_at", label: "Actualizado", render: (r) => formatDateTime(r.updated_at) },
          ]} />
          <p className="mt-2 text-caption text-muted-foreground">Abierto → preparado → aprobado para envío → enviado → presentado con justificante → justificantes archivados → liquidación verificada. Nada se marca enviado o presentado sin evidencia.</p>
        </>
      ) : null}
    </div>
  );
}

function ImportStatementDialog({ open, onOpenChange, accounts }: { open: boolean; onOpenChange: (o: boolean) => void; accounts: BizRow[] }) {
  const { exec, pending } = useAction();
  const [account, setAccount] = useState("");
  const [csv, setCsv] = useState("");
  const [result, setResult] = useState<BizRow | null>(null);
  const submit = async () => {
    const res = await exec("bank.import", { account_id: account || str(accounts[0]?.id), csv });
    setResult((res.result as BizRow) ?? null);
  };
  return (
    <Dialog open={open} onOpenChange={(o) => { onOpenChange(o); if (!o) { setResult(null); setCsv(""); } }}>
      <DialogContent className="sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>Importar extracto bancario</DialogTitle>
          <DialogDescription>CSV con punto y coma: fecha;fecha_valor;concepto;importe;saldo (decimales con coma). Reimportar el mismo extracto no duplica movimientos.</DialogDescription>
        </DialogHeader>
        <select className="h-8 rounded-md border bg-transparent px-2 text-body" value={account || str(accounts[0]?.id)} onChange={(e) => setAccount(e.target.value)} aria-label="Cuenta">
          {accounts.map((a) => <option key={str(a.id)} value={str(a.id)}>{str(a.name)}</option>)}
        </select>
        <Input type="file" accept=".csv,text/csv" onChange={async (e) => { const f = e.target.files?.[0]; if (f) setCsv(await f.text()); }} />
        <Textarea value={csv} onChange={(e) => setCsv(e.target.value)} className="min-h-32 font-mono text-micro" placeholder="o pega aquí el contenido del CSV" />
        {result ? (
          <p className="rounded-md bg-muted/50 p-2 text-caption">
            {str(result.inserted)} nuevos · {str(result.duplicates)} duplicados ignorados · {str(result.proposed_matches)} conciliaciones propuestas
            {(result.errors as string[] | undefined)?.length ? ` · errores: ${(result.errors as string[]).join("; ")}` : ""}
          </p>
        ) : null}
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cerrar</Button>
          <Button disabled={!csv.trim() || pending || accounts.length === 0} onClick={submit}>Importar</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function FinanceAnalysis() {
  const wsId = useWorkspaceId();
  const movements = useQuery(bizListOptions(wsId, "movement", { limit: "1000" }));
  const overview = useQuery(bizOverviewOptions(wsId));
  const invoices = useQuery(bizListOptions(wsId, "invoice", { direction: "issued" }));
  const byMonth = useMemo(() => {
    const m: Record<string, { in: number; out: number }> = {};
    for (const x of movements.data ?? []) {
      if (["internal_transfer"].includes(str(x.nature))) continue;
      const k = str(x.booked_on).slice(0, 7);
      m[k] ??= { in: 0, out: 0 };
      if (num(x.amount_minor) > 0) m[k].in += num(x.amount_minor);
      else m[k].out += num(x.amount_minor);
    }
    return Object.entries(m).sort(([a], [b]) => a.localeCompare(b));
  }, [movements.data]);
  const today = new Date().toISOString().slice(0, 10);
  const ar = (invoices.data ?? []).filter((i) => ["issued", "partially_paid"].includes(str(i.status)));
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <Section title="Caja y runway">
        <div className="rounded-lg border p-3 text-caption">
          <div>Caja: <strong>{formatKpiValue(overview.data?.cash, "EUR")}</strong> · {overview.data?.cash_coverage}</div>
          <div>Runway: <strong>{formatKpiValue(overview.data?.runway, "meses")}</strong></div>
          <p className="text-muted-foreground">{overview.data?.runway_explanation}</p>
          <p className="mt-1 text-micro text-muted-foreground">Caja = bancos. El margen se calcula por devengo (facturas). Son cifras distintas y se rotulan así.</p>
        </div>
      </Section>
      <Section title="Entradas y salidas de caja por mes (sin traspasos internos)">
        <Bars rows={byMonth.flatMap(([k, v]) => [{ label: `${k} entradas`, value: v.in }, { label: `${k} salidas`, value: v.out }])} format={(v) => formatMinor(v)} />
      </Section>
      <Section title="Cobros pendientes">
        {ar.length === 0 ? <EmptyHint title="Nada pendiente de cobro" /> : (
          <ul className="space-y-1 text-caption">
            {ar.map((i) => (
              <li key={str(i.id)} className="flex gap-2">
                <RecordLink entity="invoice" id={i.id} className="font-medium">{str(i.number) || "Borrador"}</RecordLink>
                <span>{str(i.organization_name)}</span>
                <span className={cn("ml-auto", str(i.due_date) < today && "text-destructive")}>{formatMinor(num(i.total_minor) - num(i.paid_minor))} · vence {formatDate(i.due_date)}</span>
              </li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  );
}

// --- Marca -------------------------------------------------------------------------

function BrandManagement() {
  const wsId = useWorkspaceId();
  const open = useInspector();
  const [view, setView] = useSubView("calendario");
  const contents = useQuery(bizListOptions(wsId, "content", {}));
  const conversations = useQuery({ ...bizListOptions(wsId, "conversation", {}), enabled: view === "conversaciones" });
  const { exec, pending } = useAction();
  const [f, setF] = useState({ title: "", pillar: "Autónomos al día", channel: "instagram" });
  return (
    <div>
      <SubNav value={view} onChange={setView} options={[["calendario", "Contenidos"], ["conversaciones", "Conversaciones"]]} />
      {view === "calendario" ? (
        <>
          <div className="mb-3 flex flex-wrap gap-1.5">
            <Input className="h-8 w-72 text-caption" placeholder="Nueva idea de contenido" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} />
            <select className="h-8 rounded-md border bg-transparent px-2 text-caption" value={f.pillar} onChange={(e) => setF({ ...f, pillar: e.target.value })} aria-label="Pilar">
              {["Renta sin sustos", "Autónomos al día", "Casos", "Calendario fiscal"].map((x) => <option key={x}>{x}</option>)}
            </select>
            <select className="h-8 rounded-md border bg-transparent px-2 text-caption" value={f.channel} onChange={(e) => setF({ ...f, channel: e.target.value })} aria-label="Canal">
              {["instagram", "linkedin", "blog", "newsletter"].map((x) => <option key={x}>{x}</option>)}
            </select>
            <Button size="sm" disabled={!f.title.trim() || pending} onClick={() => exec("content.create", f, "Idea creada").then(() => setF({ ...f, title: "" }))}><Plus /> Añadir</Button>
          </div>
          {contents.isLoading ? <LoadingBlock /> : (
            <Kanban
              columns={CONTENT_STATUS_ORDER.map((s) => ({ key: s, label: CONTENT_STATUS_LABELS[s]! }))}
              cards={(contents.data ?? []).map((c) => ({ ...c, __col: c.status }))}
              render={(c) => (
                <Card key={str(c.id)} onClick={() => open({ entity: "content", id: str(c.id) })}>
                  <span className="font-medium">{str(c.title)}</span>
                  <span className="text-muted-foreground">{str(c.pillar)} · {str(c.channel)} · {str(c.format)}</span>
                  {num(c.conversations) + num(c.contacts) > 0 ? <span className="text-muted-foreground">{num(c.conversations)} conversaciones · {num(c.contacts)} contactos</span> : null}
                  {c.scheduled_at ? <span className="text-muted-foreground">Programado {formatDateTime(c.scheduled_at)}</span> : null}
                </Card>
              )}
            />
          )}
        </>
      ) : (
        <BizTable entity="conversation" rows={conversations.data} isLoading={conversations.isLoading} columns={[
          { key: "occurred_at", label: "Fecha", render: (v) => formatDate(v.occurred_at) },
          { key: "channel", label: "Canal" },
          { key: "handle", label: "Quién" },
          { key: "summary", label: "Resumen", className: "max-w-md" },
          { key: "content_title", label: "Pieza de origen" },
          { key: "qualified", label: "Ventas", render: (v) => (v.qualified ? `Cualificada → ${str(v.contact_name)}` : "Pendiente") },
        ]} />
      )}
    </div>
  );
}

function BrandAnalysis() {
  const wsId = useWorkspaceId();
  const contents = useQuery(bizListOptions(wsId, "content", {}));
  const contacts = useQuery(bizListOptions(wsId, "contact", {}));
  const byChannel = Object.entries((contacts.data ?? []).reduce<Record<string, number>>((a, c) => ({ ...a, [str(c.source_channel) || "—"]: (a[str(c.source_channel) || "—"] ?? 0) + 1 }), {}));
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <Section title="Atribución: contactos y conversaciones por pieza">
        <Bars rows={(contents.data ?? []).filter((c) => num(c.conversations) + num(c.contacts) > 0).map((c) => ({ label: str(c.title), value: num(c.contacts), hint: `${num(c.conversations)} conversaciones` }))} />
        <p className="text-micro text-muted-foreground">Marca mide conversaciones útiles y su contribución; alcance y seguidores son auxiliares.</p>
      </Section>
      <Section title="Contactos por canal de origen"><Bars rows={byChannel.map(([k, v]) => ({ label: k, value: v }))} /></Section>
    </div>
  );
}

// --- Equipo --------------------------------------------------------------------------

function agentHealth(a: BizRow): { status: string; label: string } {
  if (a.area_paused) return { status: "paused", label: "En pausa" };
  if (str(a.runtime_status) !== "online") return { status: "stale", label: "Sin señal" };
  if (num(a.active_runs) > 0) return { status: "ok", label: "Trabajando" };
  if (num(a.waiting_approval) > 0) return { status: "warning", label: "Esperando autorización" };
  if (str(a.last_status) === "failed") return { status: "alert", label: "Fallido" };
  return { status: "ok", label: "Disponible" };
}

function TeamManagement() {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const team = useQuery(bizTeamOptions(wsId));
  if (team.isLoading) return <LoadingBlock />;
  const t = team.data;
  return (
    <div className="space-y-6">
      <Section title="Personas">
        <BizTable rows={t?.members ?? []} onRowClick={(m) => nav.push(p.memberDetail(str(m.id)))} columns={[
          { key: "name", label: "Nombre" },
          { key: "role", label: "Rol en la app", render: (m) => ({ owner: "Propietario", admin: "Administrador", member: "Miembro" } as Record<string, string>)[str(m.role)] ?? str(m.role) },
          { key: "roles", label: "Roles de negocio", render: (m) => ((m.roles as string[] | null) ?? []).join(", ") || "—" },
          { key: "open_tasks", label: "Tareas abiertas", align: "right" },
        ]} />
      </Section>
      <Section title="Agentes">
        <BizTable rows={(t?.agents ?? []).filter((a) => a.area)} onRowClick={(a) => nav.push(p.agentDetail(str(a.id)))} columns={[
          { key: "name", label: "Agente", render: (a) => <span className="inline-flex items-center gap-1.5"><AreaDot area={str(a.area)} /> {str(a.name)}</span> },
          { key: "health", label: "Salud", render: (a) => { const h = agentHealth(a); return <StatusBadge status={h.status} label={h.label} />; } },
          { key: "last_run_at", label: "Última ejecución", render: (a) => `${formatDateTime(a.last_run_at)} ${str(a.last_status) ? `· ${str(a.last_status)}` : ""}` },
          { key: "runs_month", label: "Ejecuciones mes", align: "right" },
          { key: "tokens_month", label: "Tokens mes", align: "right", render: (a) => num(a.tokens_month).toLocaleString("es-ES") },
          { key: "cost", label: "Coste mes", align: "right", render: (a) => (a.cost_ticks_month === null || a.cost_ticks_month === undefined ? "no informado" : `${(num(a.cost_ticks_month) / 1e10).toFixed(2)} USD`) },
          { key: "budget_monthly_minor", label: "Presupuesto", align: "right", render: (a) => formatMinor(num(a.budget_monthly_minor)) },
        ]} />
      </Section>
      <Section title="Organigrama por responsabilidades">
        <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-3">
          {AREAS.map((a) => {
            const roles = (t?.roles ?? []).filter((r) => str(r.area) === a.code);
            return (
              <div key={a.code} className={cn("rounded-lg border border-l-4 p-3 text-caption", a.border)}>
                <div className="font-medium">{a.name}</div>
                {roles.length === 0 ? <p className="text-muted-foreground">Sin roles</p> : roles.map((r) => (
                  <div key={str(r.id)} className="flex items-center gap-2">
                    <RecordLink entity="role" id={r.id}>{str(r.name)}</RecordLink>
                    <span className={cn("ml-auto", !r.occupant_id && "text-destructive")}>{str(r.occupant_name) || "Vacante"}</span>
                  </div>
                ))}
              </div>
            );
          })}
        </div>
        <p className="text-caption text-muted-foreground">Una persona puede llevar varios sombreros sin crear varios usuarios. La responsabilidad de negocio es distinta del rol de la aplicación.</p>
      </Section>
    </div>
  );
}

function TeamAnalysis() {
  const wsId = useWorkspaceId();
  const team = useQuery(bizTeamOptions(wsId));
  const agents = (team.data?.agents ?? []).filter((a) => a.area);
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <Section title="Ejecuciones por agente (mes)"><Bars rows={agents.map((a) => ({ label: str(a.name), value: num(a.runs_month) }))} /></Section>
      <Section title="Tokens por agente (mes)"><Bars rows={agents.map((a) => ({ label: str(a.name), value: num(a.tokens_month) }))} format={(v) => v.toLocaleString("es-ES")} /></Section>
    </div>
  );
}

// --- Dirección -------------------------------------------------------------------------

function DirectionManagement() {
  const wsId = useWorkspaceId();
  const [view, setView] = useSubView("objetivos");
  const objectives = useQuery({ ...bizListOptions(wsId, "objective", {}), enabled: view === "objetivos" });
  const decisions = useQuery({ ...bizListOptions(wsId, "decision", {}), enabled: view === "decisiones" });
  const routines = useQuery({ ...bizListOptions(wsId, "routine", {}), enabled: view === "rituales" });
  const { exec, pending } = useAction();
  const [obj, setObj] = useState({ area: "ventas", title: "", kpi_code: "", target: "", period: "" });
  const [dec, setDec] = useState({ area: "direccion", title: "", context: "" });
  const year = new Date().getFullYear();
  const q = Math.floor(new Date().getMonth() / 3) + 1;
  return (
    <div>
      <SubNav value={view} onChange={setView} options={[["objetivos", "Objetivos"], ["decisiones", "Decisiones"], ["rituales", "Rituales"]]} />
      {view === "objetivos" ? (
        <div className="space-y-3">
          <div className="flex flex-wrap gap-1.5 rounded-lg border p-2">
            <select className="h-8 rounded-md border bg-transparent px-2 text-caption" value={obj.area} onChange={(e) => setObj({ ...obj, area: e.target.value })} aria-label="Área">
              {AREAS.map((a) => <option key={a.code} value={a.code}>{a.name}</option>)}
            </select>
            <Input className="h-8 w-72 text-caption" placeholder="Objetivo con número comprobable" value={obj.title} onChange={(e) => setObj({ ...obj, title: e.target.value })} />
            <Input className="h-8 w-28 text-caption" placeholder="KPI (código)" value={obj.kpi_code} onChange={(e) => setObj({ ...obj, kpi_code: e.target.value })} />
            <Input className="h-8 w-20 text-caption" placeholder="Meta" value={obj.target} onChange={(e) => setObj({ ...obj, target: e.target.value })} />
            <Button size="sm" disabled={!obj.title.trim() || pending} onClick={() => exec("objective.save", { area: obj.area, title: obj.title, kpi_code: obj.kpi_code, target: obj.target ? Number(obj.target) : undefined, kind: obj.kpi_code ? "level" : "compliance", period: obj.period || `${year}-T${q}` }, "Objetivo creado").then(() => setObj({ ...obj, title: "", kpi_code: "", target: "" }))}>
              <Plus /> Crear
            </Button>
          </div>
          <BizTable entity="objective" rows={objectives.data} isLoading={objectives.isLoading} columns={[
            { key: "period", label: "Periodo" },
            { key: "area", label: "Área", render: (o) => <span className="inline-flex items-center gap-1.5"><AreaDot area={str(o.area)} /> {AREAS.find((a) => a.code === o.area)?.name}</span> },
            { key: "title", label: "Objetivo" },
            { key: "kind", label: "Tipo", render: (o) => ({ cumulative: "Acumulativo", level: "Nivel", compliance: "Cumplimiento", service: "Servicio" } as Record<string, string>)[str(o.kind)] },
            { key: "kpi_code", label: "KPI" },
            { key: "target", label: "Meta", align: "right" },
            { key: "status", label: "Estado", render: (o) => ({ active: "Activo", achieved: "Conseguido", missed: "No conseguido", deferred: `Aplazado → ${str(o.deferred_to)}`, draft: "Borrador" } as Record<string, string>)[str(o.status)] },
          ]} />
        </div>
      ) : null}
      {view === "decisiones" ? (
        <div className="space-y-3">
          <div className="space-y-1.5 rounded-lg border p-2">
            <div className="flex flex-wrap gap-1.5">
              <select className="h-8 rounded-md border bg-transparent px-2 text-caption" value={dec.area} onChange={(e) => setDec({ ...dec, area: e.target.value })} aria-label="Área">
                {AREAS.map((a) => <option key={a.code} value={a.code}>{a.name}</option>)}
              </select>
              <Input className="h-8 flex-1 text-caption" placeholder="Decisión abierta a preparar" value={dec.title} onChange={(e) => setDec({ ...dec, title: e.target.value })} />
              <Button size="sm" disabled={!dec.title.trim() || pending} onClick={() => exec("decision.create", dec, "Decisión abierta registrada").then(() => setDec({ ...dec, title: "", context: "" }))}><Plus /> Abrir</Button>
            </div>
            <Textarea className="min-h-14 text-caption" placeholder="Contexto: opciones, datos, quién se ve afectado" value={dec.context} onChange={(e) => setDec({ ...dec, context: e.target.value })} />
          </div>
          <BizTable entity="decision" rows={decisions.data} isLoading={decisions.isLoading} columns={[
            { key: "created_at", label: "Fecha", render: (d) => formatDate(d.created_at) },
            { key: "area", label: "Área", render: (d) => <AreaDot area={str(d.area)} /> },
            { key: "title", label: "Decisión" },
            { key: "status", label: "Estado", render: (d) => ({ open: "Abierta", decided: "Decidida", superseded: "Sustituida" } as Record<string, string>)[str(d.status)] },
            { key: "why", label: "Por qué", className: "max-w-xs text-muted-foreground" },
            { key: "author_name", label: "Autor" },
          ]} />
          <p className="text-caption text-muted-foreground">Las decisiones no se borran ni se editan: una corrección es una decisión nueva que sustituye a la anterior.</p>
        </div>
      ) : null}
      {view === "rituales" ? (
        <BizTable entity="routine" rows={routines.data} isLoading={routines.isLoading} columns={[
          { key: "kind", label: "Ritual", render: (r) => ({ day: "Día", week: "Semana", month: "Mes", quarter: "Trimestre" } as Record<string, string>)[str(r.kind)] },
          { key: "period_key", label: "Periodo" },
          { key: "focus", label: "Foco / plan", render: (r) => str(r.focus) || str(r.plan) },
          { key: "verdict", label: "Veredicto / balance", render: (r) => str(r.verdict) || str(r.review) },
          { key: "closed_at", label: "Cerrado", render: (r) => (r.closed_at ? formatDateTime(r.closed_at) : "Abierto") },
        ]} />
      ) : null}
    </div>
  );
}

function DirectionAnalysis() {
  const wsId = useWorkspaceId();
  const overview = useQuery(bizOverviewOptions(wsId));
  return (
    <div className="grid gap-6 xl:grid-cols-2">
      <Section title="Madurez estimada por área (1 validación … 6 empresa)">
        <Bars rows={(overview.data?.areas ?? []).map((a) => ({ label: <span className="inline-flex items-center gap-1.5"><AreaDot area={a.code} /> {a.name}</span>, value: a.maturity.stage, hint: (a.maturity.evidence ?? []).join(" · ") }))} format={(v) => `etapa ${v}`} />
        <p className="text-micro text-muted-foreground">Estimación con evidencias (procesos escritos, responsables, automatización, delegación); no cuenta agentes. Revísala en la revisión trimestral.</p>
      </Section>
      <Section title="Salud de las áreas">
        <ul className="space-y-1.5 text-caption">
          {(overview.data?.areas ?? []).map((a) => (
            <li key={a.code} className="flex items-center gap-2"><AreaDot area={a.code} /> <span className="w-24">{a.name}</span> <StatusBadge status={a.status} /> <span className="text-muted-foreground">{a.explanation}</span></li>
          ))}
        </ul>
        <p className="mt-2 text-micro text-muted-foreground">Un exceso en un indicador no compensa una alerta en otro.</p>
      </Section>
    </div>
  );
}
