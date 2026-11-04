/* eslint-disable i18next/no-literal-string, no-restricted-syntax -- TLS "Empresa" module ships Spanish copy only (labels and aria text included); see docs/tls/DECISIONES.md */
"use client";

import { useMemo, useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { Line, LineChart, ReferenceLine, Tooltip, XAxis, YAxis } from "recharts";
import {
  bizCargaOptions,
  bizExceptionsOptions,
  bizOverviewOptions,
  bizPipelineOptions,
  bizPlanificacionOptions,
  bizRitmoOptions,
  formatDate,
  formatKpiValue,
  STAGE_LABELS,
  type BizAreaHealth,
  type BizPipelineCard,
  type BizRitmoBucket,
  type BizWorkload,
} from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { useWorkspacePaths } from "@multica/core/paths";
import { ChartContainer, type ChartConfig } from "@multica/ui/components/ui/chart";
import { cn } from "@multica/ui/lib/utils";
import { useNavigation } from "../navigation";
import { AreaPaceRow } from "./area-pace";
import { AreaDot, EmptyHint, ErrorBlock, ListRow, LoadingBlock, Section, StatusBadge, str } from "./shared";

// --- Formatting ---------------------------------------------------------------------

const eurFmt = new Intl.NumberFormat("es-ES", { style: "currency", currency: "EUR", maximumFractionDigits: 0 });
const eurFull = new Intl.NumberFormat("es-ES", { style: "currency", currency: "EUR", minimumFractionDigits: 2, maximumFractionDigits: 2 });
const pctFmt = new Intl.NumberFormat("es-ES", { maximumFractionDigits: 0, signDisplay: "always" });

/** Unknown is a word, never a zero. */
export function euros(v: number | null | undefined, full = false): string {
  if (v === null || v === undefined) return "Sin datos";
  return (full ? eurFull : eurFmt).format(v);
}

/** Change against the previous period; null when either side is unknown. */
export function compare(cur: number | null, prev: number | null): { delta: number; pct: number | null } | null {
  if (cur === null || prev === null) return null;
  const delta = cur - prev;
  return { delta, pct: prev === 0 ? null : (delta / Math.abs(prev)) * 100 };
}

/**
 * The period in progress is compared with the previous one at the same point
 * (same number of days elapsed), not with the whole of it.
 */
export function previousAtSamePoint(cur: BizRitmoBucket, prev: BizRitmoBucket, today: string): number | null {
  if (!cur.current) return prev.invoiced;
  if (prev.invoiced === null) return null;
  const elapsed = Math.round((Date.parse(today) - Date.parse(cur.start)) / 86_400_000);
  const cut = new Date(Date.parse(prev.start) + elapsed * 86_400_000).toISOString().slice(0, 10);
  const items = (prev.items ?? []).filter((it) => it.date <= cut);
  if (items.some((it) => it.amount === null)) return null;
  return Math.round(items.reduce((a, it) => a + (it.amount ?? 0), 0) * 100) / 100;
}

const todayISO = () => new Date().toISOString().slice(0, 10);

function Segmented<T extends string>({ value, options, onChange, label }: { value: T; options: [T, string][]; onChange: (v: T) => void; label: string }) {
  return (
    <div role="tablist" aria-label={label} className="flex gap-1">
      {options.map(([v, l]) => (
        <button
          key={v}
          type="button"
          role="tab"
          aria-selected={value === v}
          onClick={() => onChange(v)}
          className={cn(
            "rounded-full px-3 py-1 text-label font-medium transition-colors",
            value === v ? "bg-secondary text-foreground" : "text-muted-foreground hover:text-foreground",
          )}
        >
          {l}
        </button>
      ))}
    </div>
  );
}

function Stat({ label, value, hint, tone }: { label: string; value: ReactNode; hint?: ReactNode; tone?: "muted" | "good" | "bad" }) {
  return (
    <div className="min-w-0">
      <p className="text-caption text-muted-foreground">{label}</p>
      <p className={cn("mt-0.5 text-title font-semibold tabular-nums", tone === "muted" && "text-muted-foreground", tone === "good" && "text-success", tone === "bad" && "text-destructive")}>{value}</p>
      {hint ? <p className="text-caption text-muted-foreground">{hint}</p> : null}
    </div>
  );
}

function Source({ children }: { children: ReactNode }) {
  return <p className="text-micro text-muted-foreground">{children}</p>;
}

function useOpenRow() {
  const nav = useNavigation();
  const p = useWorkspacePaths();
  return (db: string, id: string) => nav.push(`${p.basesDb(db)}?fila=${encodeURIComponent(id)}`);
}

// --- Ritmo: invoicing by week, month and quarter ------------------------------------

type Period = "semana" | "mes" | "trimestre";
const PERIOD_OPTIONS: [Period, string][] = [["semana", "Semana"], ["mes", "Mes"], ["trimestre", "Trimestre"]];
const PERIOD_WORD: Record<Period, string> = { semana: "la semana", mes: "el mes", trimestre: "el trimestre" };

/** Vertical bars, one per period; unknown periods are hatched and say so. */
function PeriodBars({ buckets, target, selected, onSelect }: { buckets: BizRitmoBucket[]; target: number | null; selected: string; onSelect: (k: string) => void }) {
  const values = buckets.map((b) => b.invoiced ?? 0);
  const max = Math.max(1, target ?? 0, ...values);
  const min = Math.min(0, ...values);
  const span = max - min;
  const zero = (max / span) * 100; // % from the top where 0 sits
  const [hover, setHover] = useState<string | null>(null);
  return (
    <div>
      <div className="relative h-56">
        {target !== null ? (
          <div className="pointer-events-none absolute inset-x-0 z-10 border-t border-dashed border-foreground/40" style={{ top: `${((max - target) / span) * 100}%` }}>
            <span className="absolute -top-4 right-0 text-micro text-muted-foreground">Meta {euros(target)}</span>
          </div>
        ) : null}
        <div className="absolute inset-x-0 border-t border-border" style={{ top: `${zero}%` }} />
        <div className="absolute inset-0 flex items-stretch gap-1">
          {buckets.map((b) => {
            const v = b.invoiced;
            const h = v === null ? 0 : (Math.abs(v) / span) * 100;
            const active = selected === b.key;
            return (
              <button
                key={b.key}
                type="button"
                aria-label={`${b.label}: ${v === null ? `sin datos (${b.reason})` : euros(v, true)}`}
                onClick={() => onSelect(b.key)}
                onMouseEnter={() => setHover(b.key)}
                onMouseLeave={() => setHover(null)}
                className="group relative flex-1 rounded-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                {v === null ? (
                  <span
                    className="absolute inset-x-0.5 rounded-sm bg-[repeating-linear-gradient(135deg,var(--muted)_0_4px,transparent_4px_8px)]"
                    style={{ top: `${zero - 18}%`, height: "18%" }}
                  />
                ) : (
                  <span
                    className={cn(
                      "absolute inset-x-0.5 transition-opacity",
                      v < 0 ? "rounded-b bg-destructive/70" : "rounded-t bg-chart-1",
                      !active && !b.current && "opacity-55",
                      hover === b.key && "opacity-100",
                    )}
                    style={v < 0 ? { top: `${zero}%`, height: `${h}%` } : { top: `${zero - h}%`, height: `${Math.max(h, v === 0 ? 0 : 0.8)}%` }}
                  />
                )}
                {hover === b.key ? (
                  <span className="pointer-events-none absolute bottom-full left-1/2 z-20 mb-1 w-max max-w-56 -translate-x-1/2 rounded-md border bg-popover px-2 py-1 text-left text-caption shadow-md">
                    <span className="block font-medium tabular-nums">{v === null ? "Sin datos" : euros(v, true)}</span>
                    <span className="block text-muted-foreground">{b.label} · {b.invoices} {b.invoices === 1 ? "factura" : "facturas"}</span>
                    {v === null ? <span className="block text-muted-foreground">{b.reason}</span> : null}
                    {b.partial ? <span className="block text-warning">{b.no_amount} sin importe: cifra parcial</span> : null}
                  </span>
                ) : null}
              </button>
            );
          })}
        </div>
      </div>
      <div className="mt-1 flex gap-1">
        {buckets.map((b) => (
          <span key={b.key} className={cn("flex-1 truncate text-center text-micro", b.key === selected ? "font-medium text-foreground" : "text-muted-foreground")}>
            {b.label.replace(/ \d{4}$/, "")}
          </span>
        ))}
      </div>
    </div>
  );
}

const cumulativeConfig = { value: { label: "Acumulado" } } satisfies ChartConfig;

/** Running total over the visible periods; it stops where data stops. */
function Cumulative({ buckets, target }: { buckets: BizRitmoBucket[]; target: number | null }) {
  let run = 0;
  let known = false;
  const data = buckets.map((b, i) => {
    if (b.invoiced !== null) {
      run += b.invoiced;
      known = true;
    }
    return { label: b.label, value: known && b.invoiced !== null ? run : null, goal: target === null ? null : target * (i + 1) };
  });
  if (!data.some((d) => d.value !== null)) return <EmptyHint title="Sin datos para dibujar la progresión." />;
  return (
    <div className="h-44">
      <ChartContainer config={cumulativeConfig} className="aspect-auto h-full w-full" initialDimension={{ width: 720, height: 176 }}>
        <LineChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
          <XAxis dataKey="label" tickLine={false} axisLine={false} tick={{ fontSize: 11, fill: "var(--muted-foreground)" }} interval="preserveStartEnd" />
          <YAxis hide domain={["dataMin", "dataMax"]} />
          <ReferenceLine y={0} stroke="var(--border)" />
          <Tooltip
            cursor={{ stroke: "var(--border)", strokeWidth: 1 }}
            content={({ active, payload }) => {
              const pt = active ? (payload?.[0]?.payload as { label: string; value: number | null; goal: number | null } | undefined) : undefined;
              return pt ? (
                <div className="rounded-md border bg-popover px-2 py-1 text-caption shadow-md">
                  <div className="font-medium tabular-nums">{euros(pt.value, true)}</div>
                  <div className="text-muted-foreground">acumulado a {pt.label}</div>
                  {pt.goal !== null ? <div className="text-muted-foreground">meta acumulada {euros(pt.goal)}</div> : null}
                </div>
              ) : null;
            }}
          />
          {target !== null ? <Line type="linear" dataKey="goal" stroke="var(--muted-foreground)" strokeDasharray="4 4" strokeWidth={1.5} dot={false} isAnimationActive={false} /> : null}
          <Line type="monotone" dataKey="value" stroke="var(--chart-1)" strokeWidth={2} dot={{ r: 3, strokeWidth: 0, fill: "var(--chart-1)" }} connectNulls={false} isAnimationActive={false} />
        </LineChart>
      </ChartContainer>
    </div>
  );
}

export function RitmoView() {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const period = (["semana", "mes", "trimestre"].includes(nav.searchParams.get("periodo") ?? "") ? nav.searchParams.get("periodo") : "mes") as Period;
  const setPeriod = (v: Period) => {
    const sp = new URLSearchParams(nav.searchParams);
    if (v === "mes") sp.delete("periodo");
    else sp.set("periodo", v);
    nav.replace(`${nav.pathname}?${sp.toString()}`);
  };
  const q = useQuery(bizRitmoOptions(wsId, period));
  const overview = useQuery(bizOverviewOptions(wsId));
  const openRow = useOpenRow();
  const buckets = q.data?.buckets ?? [];
  const [picked, setPicked] = useState("");
  const selIndex = Math.max(0, buckets.findIndex((b) => b.key === picked) === -1 ? buckets.length - 1 : buckets.findIndex((b) => b.key === picked));
  const sel = buckets[selIndex];
  const prev = selIndex > 0 ? buckets[selIndex - 1] : undefined;
  const prevValue = sel && prev ? previousAtSamePoint(sel, prev, todayISO()) : null;
  const cmp = sel && prev ? compare(sel.invoiced, prevValue) : null;
  const target = q.data?.target ?? null;
  const vsTarget = sel && sel.invoiced !== null && target ? Math.round((sel.invoiced / target) * 100) : null;

  if (q.isLoading) return <LoadingBlock rows={6} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  return (
    <div className="space-y-10">
      <section className="space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <Segmented label="Periodo" value={period} options={PERIOD_OPTIONS} onChange={(v) => { setPeriod(v); setPicked(""); }} />
          <span className="text-caption text-muted-foreground">Pulsa una barra para comparar ese periodo con el anterior.</span>
        </div>
        {sel ? (
          <div>
            <p className="text-body text-muted-foreground">Facturado · {sel.label}{sel.current ? " (en curso)" : ""}</p>
            <p className={cn("mt-1 text-hero tabular-nums", sel.invoiced === null && "text-muted-foreground")}>{euros(sel.invoiced)}</p>
            <p className="mt-1 text-body">
              {sel.invoiced === null ? (
                <span className="text-muted-foreground">{sel.reason}</span>
              ) : cmp === null ? (
                <span className="text-muted-foreground">Sin comparación: {prev ? `${prev.label} no tiene datos` : "no hay periodo anterior en la vista"}.</span>
              ) : (
                <span className={cn("tabular-nums", cmp.delta > 0 ? "text-success" : cmp.delta < 0 ? "text-destructive" : "text-muted-foreground")}>
                  {cmp.delta >= 0 ? "+" : "−"}{euros(Math.abs(cmp.delta))}
                  {cmp.pct !== null ? ` (${pctFmt.format(cmp.pct)} %)` : ""}
                  <span className="text-muted-foreground"> frente a {prev?.label}{sel.current ? " a la misma altura" : ""} ({euros(prevValue)})</span>
                </span>
              )}
            </p>
            <p className="mt-1 text-caption text-muted-foreground">
              {target !== null ? (vsTarget !== null ? `${vsTarget} % de la meta de ${PERIOD_WORD[period]} (${euros(target)}).` : `Meta de ${PERIOD_WORD[period]}: ${euros(target)}.`) : q.data.target_note}
              {sel.partial ? ` · ${sel.no_amount} ${sel.no_amount === 1 ? "factura" : "facturas"} sin importe: cifra parcial.` : ""}
            </p>
          </div>
        ) : null}
        <PeriodBars buckets={buckets} target={target} selected={sel?.key ?? ""} onSelect={setPicked} />
      </section>

      <Section title="Progresión acumulada">
        <Cumulative buckets={buckets} target={target} />
        <p className="text-caption text-muted-foreground">Suma de lo facturado desde el primer periodo de la vista. {target !== null ? "La línea discontinua es la meta acumulada." : ""}</p>
      </Section>

      <Section title="Periodo a periodo">
        <div className="overflow-x-auto">
          <table className="w-full text-caption">
            <thead>
              <tr className="border-b text-left text-muted-foreground">
                <th className="py-2 pr-3 font-normal">Periodo</th>
                <th className="py-2 pr-3 text-right font-normal">Facturas</th>
                <th className="py-2 pr-3 text-right font-normal">Facturado</th>
                <th className="py-2 pr-3 text-right font-normal">Frente al anterior</th>
                <th className="py-2 font-normal">Detalle</th>
              </tr>
            </thead>
            <tbody>
              {[...buckets].reverse().map((b) => {
                const i = buckets.indexOf(b);
                const c = i > 0 ? compare(b.invoiced, previousAtSamePoint(b, buckets[i - 1]!, todayISO())) : null;
                return (
                  <tr key={b.key} className={cn("border-b align-top", b.key === sel?.key && "bg-muted/40")}>
                    <td className="py-2 pr-3">{b.label}{b.current ? " · en curso" : ""}</td>
                    <td className="py-2 pr-3 text-right tabular-nums">{b.invoices}</td>
                    <td className={cn("py-2 pr-3 text-right tabular-nums", b.invoiced === null && "text-muted-foreground")}>{euros(b.invoiced, true)}{b.partial ? " *" : ""}</td>
                    <td className={cn("py-2 pr-3 text-right tabular-nums", c && c.delta > 0 && "text-success", c && c.delta < 0 && "text-destructive", !c && "text-muted-foreground")}>
                      {c ? `${c.delta >= 0 ? "+" : "−"}${euros(Math.abs(c.delta))}${b.current ? " ¹" : ""}` : "—"}
                    </td>
                    <td className="py-2 text-muted-foreground">
                      {b.invoiced === null ? b.reason : null}
                      {(b.items ?? []).map((it, j) => (
                        <span key={it.id}>
                          {j > 0 || b.invoiced === null ? " · " : ""}
                          <button type="button" className="hover:text-foreground hover:underline" onClick={() => openRow("facturas", it.id)}>
                            {it.number || it.party} {it.amount === null ? "(sin importe)" : euros(it.amount, true)}
                          </button>
                        </span>
                      ))}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
        <Source>
          {q.data.source} {q.data.first_record ? `Primera factura con fecha: ${formatDate(q.data.first_record)}.` : ""}
          {q.data.undated ? ` ${q.data.undated} sin fecha conocida no se cuentan.` : ""} * = cifra parcial (hay facturas sin importe). ¹ = el periodo en curso se compara con el anterior a la misma altura (mismos días transcurridos).
        </Source>
      </Section>

      <Section title="Ritmo frente a objetivos">
        {(q.data.objectives ?? []).length > 0 ? (
          <div className="divide-y">
            {(q.data.objectives ?? []).map((o) => (
              <ListRow
                key={str(o.id)}
                primary={<span className="inline-flex items-center gap-2"><AreaDot area={str(o.area)} /> {str(o.title)}</span>}
                secondary={`${str(o.period)} · ${str(o.kpi_code) || "sin indicador"}`}
                value={o.target === null || o.target === undefined ? "—" : str(o.target)}
                detail={({ active: "Activo", achieved: "Conseguido", missed: "No conseguido" } as Record<string, string>)[str(o.status)] ?? str(o.status)}
              />
            ))}
          </div>
        ) : (
          <p className="text-caption text-muted-foreground">Sin objetivos registrados para este trimestre (Dirección › Gestión › Objetivos). Debajo, el ritmo de cada área frente a las metas de sus indicadores.</p>
        )}
        <div className="divide-y">
          {(overview.data?.areas ?? []).map((a) => <AreaPaceRow key={a.code} area={a} onOpen={() => nav.push(`${nav.pathname.split("/").slice(0, 3).join("/")}/${a.code}`)} />)}
        </div>
      </Section>
    </div>
  );
}

// --- Situación: Dirección, Ventas and Entrega in one view ----------------------------

function AreaColumn({ area, children }: { area: BizAreaHealth | undefined; children: ReactNode }) {
  const nav = useNavigation();
  const wsId = useWorkspaceId();
  const exceptions = useQuery(bizExceptionsOptions(wsId, area?.code ?? ""));
  if (!area) return null;
  const kpis = (area.kpis ?? []).filter((k) => k.enabled !== false);
  const base = nav.pathname.split("/").slice(0, 3).join("/");
  return (
    <section className="min-w-0 space-y-3">
      <button type="button" onClick={() => nav.push(`${base}/${area.code}`)} className="flex w-full items-baseline gap-2 text-left hover:opacity-70">
        <AreaDot area={area.code} className="self-center" />
        <h2 className="text-title font-semibold tracking-tight">{area.name}</h2>
        <StatusBadge status={area.paused ? "paused" : area.status} />
      </button>
      <p className="text-caption text-muted-foreground">{area.explanation}</p>
      <div className="divide-y">{children}</div>
      <div>
        <p className="text-caption font-medium">Indicadores</p>
        <ul className="mt-1 space-y-1 text-caption">
          {kpis.length === 0 ? <li className="text-muted-foreground">Sin indicadores</li> : kpis.slice(0, 5).map((k) => (
            <li key={k.code} className="flex items-baseline gap-2">
              <span className="min-w-0 flex-1 truncate text-muted-foreground" title={k.explanation}>{k.name}</span>
              <span className="tabular-nums">{formatKpiValue(k.value, k.unit)}</span>
              <StatusBadge status={k.status} />
            </li>
          ))}
        </ul>
      </div>
      <div>
        <p className="text-caption font-medium">Excepciones</p>
        {(exceptions.data ?? []).length === 0 ? <p className="text-caption text-muted-foreground">Ninguna abierta.</p> : (
          <ul className="mt-1 space-y-1 text-caption">
            {(exceptions.data ?? []).slice(0, 3).map((e, i) => <li key={`${e.kind}-${i}`} className="line-clamp-2"><span className={cn(e.severity === "alta" ? "text-destructive" : "text-warning")}>●</span> {e.title}</li>)}
            {(exceptions.data ?? []).length > 3 ? <li className="text-muted-foreground">y {(exceptions.data ?? []).length - 3} más</li> : null}
          </ul>
        )}
      </div>
    </section>
  );
}

export function SituacionView() {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const overview = useQuery(bizOverviewOptions(wsId));
  const month = useQuery(bizRitmoOptions(wsId, "mes"));
  const pipe = useQuery(bizPipelineOptions(wsId));
  const carga = useQuery(bizCargaOptions(wsId));
  const plan = useQuery(bizPlanificacionOptions(wsId));
  if (overview.isLoading) return <LoadingBlock rows={6} />;
  if (overview.error || !overview.data) return <ErrorBlock error={overview.error} retry={() => overview.refetch()} />;
  const area = (c: string) => overview.data.areas.find((a) => a.code === c);
  const mb = month.data?.buckets ?? [];
  const cur = mb[mb.length - 1];
  const prev = mb[mb.length - 2];
  const cmp = cur && prev ? compare(cur.invoiced, previousAtSamePoint(cur, prev, todayISO())) : null;
  const people = carga.data?.people ?? [];
  const openItems = people.reduce((a, w) => a + (w.assigned ?? 0), 0);
  const overloaded = people.filter((w) => w.load !== null && w.load > 100);
  const unknown = people.filter((w) => w.assigned === null).length;
  const activeInternal = (plan.data?.projects ?? []).filter((p) => !p.closed);
  const go = (tab: string, areaCode = "direccion") => nav.push(`${nav.pathname.split("/").slice(0, 3).join("/")}/${areaCode}?tab=${tab}`);
  return (
    <div className="space-y-6">
      <div className="grid gap-x-10 gap-y-8 lg:grid-cols-3">
        <AreaColumn area={area("direccion")}>
          <ListRow onClick={() => go("ritmo")} primary="Facturado este mes" secondary={cmp ? `${cmp.delta >= 0 ? "+" : "−"}${euros(Math.abs(cmp.delta))} frente a ${prev?.label} a la misma altura` : cur?.reason || "Sin comparación con el mes anterior"} value={euros(cur?.invoiced ?? null)} />
          <ListRow onClick={() => go("planificacion")} primary="Proyectos internos en curso" secondary={activeInternal[0] ? activeInternal[0].title : "Ninguno registrado"} value={plan.data ? activeInternal.length : "—"} />
          <ListRow primary="Decisiones abiertas" value={(overview.data.open_decisions ?? []).length} />
        </AreaColumn>
        <AreaColumn area={area("ventas")}>
          <ListRow onClick={() => go("pipeline", "ventas")} primary="Oportunidades abiertas" secondary={pipe.data ? `${pipe.data.archived + pipe.data.lost} cerradas sin venta · ${pipe.data.won} ganadas` : ""} value={pipe.data?.open ?? "—"} />
          <ListRow onClick={() => go("pipeline", "ventas")} primary="Importe en cartera" secondary={pipe.data?.open_no_amount ? `${pipe.data.open_no_amount} sin importe` : "Todas con importe"} value={euros(pipe.data?.open_amount ?? null)} />
          <ListRow onClick={() => go("pipeline", "ventas")} primary="Tasa de cierre" secondary="Ganadas sobre ganadas y perdidas" value={pipe.data?.win_rate === null || pipe.data?.win_rate === undefined ? "Sin datos" : `${pipe.data.win_rate} %`} />
        </AreaColumn>
        <AreaColumn area={area("entrega")}>
          <ListRow onClick={() => go("carga", "entrega")} primary="Trabajo abierto asignado" secondary={unknown ? `${unknown} sin datos (agentes en Multica)` : "Personas y agentes"} value={carga.data ? openItems : "—"} />
          <ListRow onClick={() => go("carga", "entrega")} primary="Por encima de su capacidad" secondary={carga.data?.has_capacity ? overloaded.map((w) => w.name).join(", ") || "Nadie" : "Capacidad sin definir"} value={carga.data?.has_capacity ? overloaded.length : "—"} />
          <ListRow primary="Proyectos activos" value={formatKpiValue((area("entrega")?.kpis ?? []).find((k) => k.code === "ENT-ACTIVE")?.value ?? null, "")} />
        </AreaColumn>
      </div>
      <Source>Cada columna lee lo mismo que su área: indicadores con las metas de «Metas.md», excepciones abiertas, facturas de Fiscal, la BBDD de Oportunidades y la carga de Entrega.</Source>
    </div>
  );
}

// --- Planificación interna --------------------------------------------------------------

const monthKey = (d: string) => d.slice(0, 7);
function addMonths(key: string, n: number) {
  const [y, m] = key.split("-").map(Number) as [number, number];
  const d = new Date(Date.UTC(y, m - 1 + n, 1));
  return d.toISOString().slice(0, 7);
}
const MONTHS = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"];

export function PlanificacionView() {
  const wsId = useWorkspaceId();
  const q = useQuery(bizPlanificacionOptions(wsId));
  const openRow = useOpenRow();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const [showClosed, setShowClosed] = useState(false);
  const today = new Date().toISOString().slice(0, 10);
  const all = q.data?.projects ?? [];
  const list = all.filter((x) => showClosed || !x.closed);
  const months = useMemo(() => {
    const dated = list.flatMap((x) => [x.start, x.end].filter(Boolean)).map(monthKey);
    const lo = [monthKey(today), ...dated].sort()[0]!;
    const hi = [addMonths(monthKey(today), 2), ...dated].sort().reverse()[0]!;
    const out: string[] = [];
    for (let k = lo; k <= hi && out.length < 24; k = addMonths(k, 1)) out.push(k);
    return out;
  }, [list, today]);
  if (q.isLoading) return <LoadingBlock rows={5} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  const pos = (d: string, end = false) => {
    const k = monthKey(d);
    const i = months.indexOf(k);
    if (i < 0) return k < months[0]! ? 0 : 100;
    const [y, m] = k.split("-").map(Number) as [number, number];
    const days = new Date(Date.UTC(y, m, 0)).getUTCDate();
    const day = d.length >= 10 ? Number(d.slice(8, 10)) : end ? days : 1;
    return ((i + (end ? day : day - 1) / days) / months.length) * 100;
  };
  const closedCount = all.filter((x) => x.closed).length;
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center gap-3">
        <p className="text-caption text-muted-foreground">Proyectos internos de The Last: lo que mejora la empresa, no un encargo de cliente.</p>
        {closedCount > 0 ? (
          <button type="button" className="ml-auto text-caption text-muted-foreground hover:text-foreground" onClick={() => setShowClosed((v) => !v)}>
            {showClosed ? "Ocultar cerrados" : `Mostrar cerrados (${closedCount})`}
          </button>
        ) : null}
      </div>
      {list.length === 0 ? (
        <EmptyHint title={all.length ? "No hay proyectos internos en curso." : "Aún no hay proyectos internos registrados."} next={q.data.fill} />
      ) : (
        <>
          <section aria-label="Calendario" className="overflow-x-auto">
            <div className="min-w-[36rem]">
              <div className="ml-48 flex border-b pb-1">
                {months.map((m) => (
                  <span key={m} className={cn("flex-1 text-micro text-muted-foreground", m === monthKey(today) && "font-medium text-foreground")}>
                    {MONTHS[Number(m.slice(5)) - 1]}{m.endsWith("-01") || m === months[0] ? ` ${m.slice(2, 4)}` : ""}
                  </span>
                ))}
              </div>
              {list.map((x) => {
                const has = Boolean(x.start || x.end);
                const left = x.start ? pos(x.start) : x.end ? Math.max(0, pos(x.end, true) - 4) : 0;
                const right = x.end ? pos(x.end, true) : x.start ? Math.min(100, pos(today, true)) : 0;
                const late = !x.closed && x.end && x.end < today;
                return (
                  <div key={x.id} className="flex items-center border-b py-2">
                    <span className="w-48 shrink-0 truncate pr-3 text-caption" title={x.title}>{x.title}</span>
                    <div className="relative h-5 flex-1">
                      <div className="absolute inset-y-0 w-px bg-foreground/30" style={{ left: `${pos(today)}%` }} aria-hidden="true" />
                      {has ? (
                        <div
                          className={cn("absolute inset-y-1 rounded-sm", x.closed ? "bg-muted-foreground/30" : late ? "bg-destructive/70" : "bg-chart-1/80")}
                          style={{ left: `${left}%`, width: `${Math.max(1.5, right - left)}%` }}
                          title={`${x.start ? formatDate(x.start) : "sin inicio"} → ${x.end ? formatDate(x.end) : "sin fin"}`}
                        />
                      ) : <span className="text-micro text-muted-foreground">Sin fechas</span>}
                    </div>
                  </div>
                );
              })}
              <p className="mt-1 text-micro text-muted-foreground">La línea vertical es hoy. En rojo, lo que pasó su fecha de fin sin cerrarse.</p>
            </div>
          </section>
          <div className="divide-y">
            {list.map((x) => (
              <ListRow
                key={x.id}
                onClick={() => (x.entity_id ? nav.push(p.projectDetail(x.entity_id)) : x.db ? openRow(x.db, x.id) : undefined)}
                primary={<span className="inline-flex items-center gap-2"><AreaDot area={x.area} /> {x.title}</span>}
                secondary={[x.status || "Sin estado", x.owner ? `lo lleva ${x.owner}` : "sin responsable", x.next ? `siguiente: ${x.next}` : "", x.origin].filter(Boolean).join(" · ")}
                value={x.steps ? `${x.done}/${x.steps}` : "—"}
                detail={<span className={cn(!x.closed && x.end && x.end < today ? "text-destructive" : "text-muted-foreground")}>{x.end ? `fin ${formatDate(x.end)}` : "sin fecha de fin"}</span>}
              />
            ))}
          </div>
        </>
      )}
      <Source>Se leen de «{q.data.folder}/»{q.data.folder_exists ? "" : " (aún no existe)"}, de los expedientes marcados como internos y de los proyectos estratégicos de la app. {all.length ? q.data.fill : ""}</Source>
    </div>
  );
}

// --- Ventas · Pipeline -------------------------------------------------------------------

const OPEN_STAGE_KEYS = ["entrada", "cualificacion", "diagnostico", "propuesta", "negociacion", "aceptada"];
const OUTCOME_LABEL: Record<string, string> = { ganada: "Ganada", perdida: "Perdida", archivada: "Archivada" };

function PipeCard({ c, onOpen }: { c: BizPipelineCard; onOpen: () => void }) {
  return (
    <button type="button" onClick={onOpen} className="flex w-full flex-col gap-0.5 rounded-md border bg-card p-2 text-left text-caption hover:bg-accent/40">
      <span className="font-medium">{c.title}</span>
      {c.client && c.client !== c.title ? <span className="text-muted-foreground">{c.client}</span> : null}
      <span className={cn("tabular-nums", c.amount === null && "text-muted-foreground")}>{c.amount === null ? "Sin importe" : euros(c.amount, true)}</span>
      <span className="text-micro text-muted-foreground">{[c.status || null, c.owner || null, c.date ? formatDate(c.date) : null].filter(Boolean).join(" · ")}</span>
    </button>
  );
}

export function PipelineView() {
  const wsId = useWorkspaceId();
  const q = useQuery(bizPipelineOptions(wsId));
  const openRow = useOpenRow();
  const [view, setView] = useState<"embudo" | "kanban">("embudo");
  if (q.isLoading) return <LoadingBlock rows={6} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  const d = q.data;
  const open = d.cards.filter((c) => !c.outcome);
  const closed = d.cards.filter((c) => c.outcome);
  const maxReached = Math.max(1, ...d.stages.map((s) => s.reached));
  const open1 = (c: BizPipelineCard) => openRow("oportunidades", c.id);
  return (
    <div className="space-y-8">
      <div className="grid grid-cols-2 gap-6 md:grid-cols-4">
        <Stat label="Abiertas" value={d.open} hint={`${d.cards.length} en la BBDD`} />
        <Stat label="Importe en cartera" value={euros(d.open_amount)} tone={d.open_amount === null ? "muted" : undefined} hint={d.open_no_amount ? `${d.open_no_amount} sin importe` : d.open ? "Todas con importe" : "Nada abierto"} />
        <Stat label="Cerradas" value={d.won + d.lost + d.archived} hint={`${d.won} ganadas · ${d.lost} perdidas · ${d.archived} archivadas`} />
        <Stat label="Tasa de cierre" value={d.win_rate === null ? "Sin datos" : `${d.win_rate} %`} tone={d.win_rate === null ? "muted" : undefined} hint="Ganadas sobre ganadas y perdidas (las archivadas no cuentan)" />
      </div>

      <Segmented label="Vista del pipeline" value={view} options={[["embudo", "Embudo"], ["kanban", "Por etapas"]]} onChange={setView} />

      {view === "embudo" ? (
        <Section title="Embudo y conversión">
          <div className="space-y-2">
            {d.stages.map((s, i) => (
              <div key={s.key} className="grid grid-cols-[9rem_1fr_2rem_9rem] items-center gap-3 text-caption md:grid-cols-[11rem_1fr_2.5rem_12rem]">
                <span className="truncate">{STAGE_LABELS[s.key] ?? s.key}</span>
                <div className="h-5 rounded-sm bg-muted/50" title={`${s.reached} llegaron a esta etapa`}>
                  <div className="h-5 rounded-sm bg-chart-1/80" style={{ width: `${(s.reached / maxReached) * 100}%` }} />
                </div>
                <span className="text-right tabular-nums">{s.reached}</span>
                <span className="text-right tabular-nums text-muted-foreground">
                  {i === 0 ? "—" : s.conversion === null ? "sin datos" : `${s.conversion} % de la anterior`}
                </span>
              </div>
            ))}
          </div>
          <p className="text-caption text-muted-foreground">Cada barra cuenta las oportunidades que llegaron al menos a esa etapa (también las que se cerraron después). La conversión es el paso desde la etapa anterior.</p>
          <div className="overflow-x-auto">
            <table className="w-full text-caption">
              <thead>
                <tr className="border-b text-left text-muted-foreground">
                  <th className="py-2 pr-3 font-normal">Etapa</th>
                  <th className="py-2 pr-3 text-right font-normal">Abiertas ahora</th>
                  <th className="py-2 pr-3 text-right font-normal">Importe</th>
                  <th className="py-2 text-right font-normal">Sin importe</th>
                </tr>
              </thead>
              <tbody>
                {d.stages.filter((s) => OPEN_STAGE_KEYS.includes(s.key)).map((s) => (
                  <tr key={s.key} className="border-b">
                    <td className="py-2 pr-3">{STAGE_LABELS[s.key]}</td>
                    <td className="py-2 pr-3 text-right tabular-nums">{s.count}</td>
                    <td className={cn("py-2 pr-3 text-right tabular-nums", s.amount === null && "text-muted-foreground")}>{s.count ? euros(s.amount) : "—"}</td>
                    <td className="py-2 text-right tabular-nums">{s.no_amount || ""}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Section>
      ) : (
        <div className="flex gap-2 overflow-x-auto pb-2">
          {OPEN_STAGE_KEYS.map((k) => {
            const items = open.filter((c) => c.stage === k);
            const st = d.stages.find((s) => s.key === k);
            return (
              <div key={k} className="flex w-60 shrink-0 flex-col rounded-lg bg-muted/40 p-1.5">
                <div className="flex items-baseline gap-1.5 px-1.5 py-1 text-caption font-medium">
                  {STAGE_LABELS[k]} <span className="text-muted-foreground">{items.length}</span>
                  <span className="ml-auto text-micro font-normal text-muted-foreground">{items.length ? euros(st?.amount ?? null) : ""}</span>
                </div>
                <div className="flex flex-col gap-1.5">
                  {items.length === 0 ? <p className="px-1.5 py-3 text-center text-micro text-muted-foreground">Vacío</p> : items.map((c) => <PipeCard key={c.id} c={c} onOpen={() => open1(c)} />)}
                </div>
              </div>
            );
          })}
        </div>
      )}

      <Section title={`Cerradas (${closed.length})`}>
        {closed.length === 0 ? <EmptyHint title="Ninguna cerrada todavía." /> : (
          <div className="divide-y">
            {closed.map((c) => (
              <ListRow
                key={c.id}
                onClick={() => open1(c)}
                primary={c.title}
                secondary={`Llegó a ${STAGE_LABELS[c.stage] ?? c.stage} · ${c.origin}`}
                value={c.amount === null ? <span className="text-muted-foreground">Sin importe</span> : euros(c.amount, true)}
                detail={<span className="text-muted-foreground">{OUTCOME_LABEL[c.outcome] ?? c.outcome}</span>}
              />
            ))}
          </div>
        )}
      </Section>
      <Source>{d.source} Una oportunidad sin importe no suma cero: se cuenta aparte. Para darle importe, añade «importe: 1.500 €» al frontmatter de su nota.</Source>
    </div>
  );
}

// --- Entrega · Carga de trabajo ---------------------------------------------------------

const KIND_LABEL: Record<string, string> = { tarea: "Tarea", sesion: "Sesión", incidencia: "Incidencia", proyecto: "Proyecto" };
const ITEM_DB: Record<string, string> = { tarea: "tareas", sesion: "reuniones", incidencia: "incidencias", proyecto: "proyectos" };

function LoadBar({ w }: { w: BizWorkload }) {
  if (w.assigned === null) return <div className="h-2 rounded-full bg-[repeating-linear-gradient(135deg,var(--muted)_0_4px,transparent_4px_8px)]" aria-hidden="true" />;
  if (w.capacity === null || w.capacity <= 0) return <div className="h-2 rounded-full bg-muted" aria-hidden="true" />;
  const pct = (w.assigned / w.capacity) * 100;
  return (
    <div className="relative h-2 rounded-full bg-muted" aria-hidden="true">
      <div className={cn("h-2 rounded-full", pct > 100 ? "bg-destructive/80" : pct >= 80 ? "bg-warning/80" : "bg-chart-1/80")} style={{ width: `${Math.min(100, pct)}%` }} />
    </div>
  );
}

function WorkloadRow({ w }: { w: BizWorkload }) {
  const openRow = useOpenRow();
  const [open, setOpen] = useState(false);
  const items = w.items ?? [];
  const value = w.assigned === null ? "Sin datos" : w.capacity !== null ? `${w.assigned} de ${w.capacity}` : `${w.assigned}`;
  const verdict = w.assigned === null
    ? w.note || "Sin datos"
    : w.capacity === null
      ? "Capacidad sin definir"
      : w.load !== null && w.load > 100 ? `Por encima de su capacidad (${w.load} %)` : `${w.load ?? 0} % de su capacidad`;
  return (
    <div className="py-3">
      <button type="button" className={cn("flex w-full items-center gap-4 text-left", items.length > 0 ? "hover:opacity-70" : "cursor-default")} onClick={() => items.length > 0 && setOpen((v) => !v)} aria-expanded={items.length > 0 ? open : undefined}>
        <span className="min-w-0 flex-1">
          <span className="block truncate text-body-lg">{w.name}</span>
          <span className="block truncate text-caption text-muted-foreground">{w.detail}{w.unit && w.capacity !== null ? ` · capacidad ${w.capacity} ${w.unit}` : ""}</span>
        </span>
        <span className="shrink-0 text-right">
          <span className={cn("block text-body-lg tabular-nums", w.assigned === null && "text-muted-foreground")}>{value}</span>
          <span className={cn("block text-caption", w.load !== null && w.load > 100 ? "text-destructive" : "text-muted-foreground")}>{verdict}</span>
        </span>
      </button>
      <div className="mt-2"><LoadBar w={w} /></div>
      {w.assigned !== null ? (
        <p className="mt-1 text-micro text-muted-foreground">{(w.counts ?? []).map((c) => `${c.value} ${c.label.toLowerCase()}`).join(" · ")}</p>
      ) : null}
      {open && items.length > 0 ? (
        <ul className="mt-2 space-y-1 text-caption">
          {items.map((it) => (
            <li key={`${it.db}${it.id}`}>
              <button type="button" className="flex w-full gap-2 text-left hover:underline" onClick={() => openRow(ITEM_DB[it.kind] ?? it.db, it.id)}>
                <span className="w-20 shrink-0 text-muted-foreground">{KIND_LABEL[it.kind] ?? it.kind}</span>
                <span className="min-w-0 flex-1 truncate">{it.title}{it.project ? <span className="text-muted-foreground"> · {it.project}</span> : null}</span>
                {it.date ? <span className={cn("shrink-0 tabular-nums", it.overdue ? "text-destructive" : "text-muted-foreground")}>{formatDate(it.date)}</span> : null}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

export function CargaView() {
  const wsId = useWorkspaceId();
  const q = useQuery(bizCargaOptions(wsId));
  if (q.isLoading) return <LoadingBlock rows={6} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  const d = q.data;
  const people = d.people.filter((w) => w.kind === "persona");
  const agents = d.people.filter((w) => w.kind === "agente");
  const loose = d.people.filter((w) => w.kind === "sin_asignar");
  const total = d.people.reduce((a, w) => a + (w.assigned ?? 0), 0);
  const unknown = d.people.filter((w) => w.assigned === null).length;
  const over = d.people.filter((w) => w.load !== null && w.load > 100).length;
  return (
    <div className="space-y-8">
      <div className="grid grid-cols-2 gap-6 md:grid-cols-4">
        <Stat label="Trabajo abierto" value={total} hint="Tareas, sesiones próximas, incidencias y proyectos" />
        <Stat label="Personas" value={people.length} hint={`${people.filter((w) => (w.assigned ?? 0) > 0).length} con trabajo asignado`} />
        <Stat label="Agentes de IA" value={agents.length} hint={unknown ? `${unknown} sin datos de carga` : "Todos visibles"} />
        <Stat label="Por encima de su capacidad" value={d.has_capacity ? over : "—"} tone={d.has_capacity ? (over ? "bad" : undefined) : "muted"} hint={d.has_capacity ? "Asignado frente a capacidad" : "Capacidad sin definir"} />
      </div>
      <Section title="Personas">
        {people.length === 0 ? <EmptyHint title="Sin personas en Equipo." /> : <div className="divide-y">{people.map((w) => <WorkloadRow key={`p-${w.name}`} w={w} />)}</div>}
      </Section>
      <Section title="Agentes de IA">
        {agents.length === 0 ? <EmptyHint title="Sin agentes en el inventario." /> : <div className="divide-y">{agents.map((w) => <WorkloadRow key={`a-${w.name}`} w={w} />)}</div>}
        <p className="text-caption text-muted-foreground">Un agente sin datos trabaja en Multica: la app solo ve lo que le asignan la carpeta o sus propias tareas. Personas y agentes se cuentan en piezas de trabajo, no en horas.</p>
      </Section>
      {loose.length > 0 ? (
        <Section title="Sin asignar">
          <div className="divide-y">{loose.map((w) => <WorkloadRow key="loose" w={w} />)}</div>
        </Section>
      ) : null}
      <Source>{d.source} {d.capacity_note}</Source>
    </div>
  );
}

