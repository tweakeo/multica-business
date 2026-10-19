/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { AlertTriangle, CheckCircle2, CircleDashed, OctagonAlert, OctagonX } from "lucide-react";
import { Bar, BarChart, Cell, LabelList, ReferenceLine, XAxis, YAxis } from "recharts";
import {
  PACE_BANDS,
  PACE_NO_DATA,
  areaPace,
  formatKpiValue,
  kpiPace,
  paceInfo,
  type BizAreaHealth,
  type PaceBand,
  type PaceTone,
} from "@multica/core/biz";
import { ChartContainer, type ChartConfig } from "@multica/ui/components/ui/chart";
import { cn } from "@multica/ui/lib/utils";
import { AreaDot, areaOf } from "./shared";

// Pace colours mirror the old program (verde, naranja, rojo, grana) on the
// design-system tokens. Colour is never the only signal: every band also
// carries an icon, a word and its number.
const TONE: Record<PaceTone, { bar: string; text: string; fill: string; icon: typeof CheckCircle2 }> = {
  good: { bar: "bg-success", text: "text-success", fill: "var(--success)", icon: CheckCircle2 },
  attention: { bar: "bg-warning", text: "text-warning", fill: "var(--warning)", icon: AlertTriangle },
  risk: { bar: "bg-destructive", text: "text-destructive", fill: "var(--destructive)", icon: OctagonAlert },
  critical: { bar: "bg-critical", text: "text-critical", fill: "var(--critical)", icon: OctagonX },
  none: { bar: "bg-muted-foreground/40", text: "text-muted-foreground", fill: "var(--muted-foreground)", icon: CircleDashed },
};

const toneOf = (band: PaceBand) => TONE[paceInfo(band).tone];

export function PaceLabel({ band, className }: { band: PaceBand; className?: string }) {
  const t = toneOf(band);
  const Icon = t.icon;
  return (
    <span className={cn("inline-flex items-center gap-1 text-caption font-medium", t.text, className)}>
      <Icon aria-hidden="true" className="size-3.5" />
      {paceInfo(band).label}
    </span>
  );
}

/** Fill = progress towards the full target; tick = where it should be today. */
export function PaceBar({ band, progress, expected, className }: { band: PaceBand; progress: number | null; expected?: number | null; className?: string }) {
  return (
    <div
      role="meter"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={progress ?? 0}
      // eslint-disable-next-line no-restricted-syntax -- Spanish-only module (docs/tls/DECISIONES.md), same as its JSX copy
      aria-label={`Avance ${progress ?? 0} %${expected != null ? `, esperado hoy ${Math.round(expected)} %` : ""}`}
      className={cn("relative h-1.5 w-full rounded-full bg-muted", className)}
    >
      <div className={cn("h-full rounded-full transition-[width]", toneOf(band).bar)} style={{ width: `${progress ?? 0}%` }} />
      {expected != null && expected > 0 && expected < 100 ? (
        <span aria-hidden="true" className="absolute -top-0.5 -bottom-0.5 w-0.5 rounded-full bg-foreground/70" style={{ left: `calc(${expected}% - 1px)` }} />
      ) : null}
    </div>
  );
}

export function PaceLegend({ className }: { className?: string }) {
  const bands = PACE_BANDS.filter((b) => b.band !== "ahead");
  return (
    <div className={cn("flex flex-wrap items-center gap-x-4 gap-y-1 text-micro text-muted-foreground", className)}>
      {bands.map((b, i) => {
        const upper = i === 0 ? null : bands[i - 1]!.min - 1;
        return (
          <span key={b.band} className="inline-flex items-center gap-1.5">
            <span aria-hidden="true" className={cn("size-2 rounded-full", TONE[b.tone].bar)} />
            {b.label} {i === 0 ? `≥ ${b.min} %` : b.min === 0 ? `< ${bands[i - 1]!.min} %` : `${b.min}–${upper} %`}
          </span>
        );
      })}
      <span className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className={cn("size-2 rounded-full", TONE.none.bar)} />
        {PACE_NO_DATA.label}
      </span>
      <span className="inline-flex items-center gap-1.5">
        <span aria-hidden="true" className="h-2.5 w-0.5 rounded-full bg-foreground/70" />
        Dónde deberías estar hoy
      </span>
    </div>
  );
}

const chartConfig = { pace: { label: "Ritmo" } } satisfies ChartConfig;

/** One bar per area: the pace of its most delayed KPI. */
export function AreaPaceChart({ areas, onSelect }: { areas: BizAreaHealth[]; onSelect?: (code: string) => void }) {
  const data = areas.map((a) => {
    const p = areaPace(a);
    return {
      code: a.code,
      name: a.name,
      // Bars stop at 120 % so a runaway KPI does not flatten the rest.
      pace: p.pace === null ? 0 : Math.min(120, Math.max(0, p.pace)),
      label: p.pace === null ? "Sin dato" : `${p.pace} %`,
      fill: toneOf(p.band).fill,
    };
  });
  return (
    <ChartContainer config={chartConfig} className="aspect-auto h-48 w-full" initialDimension={{ width: 480, height: 192 }}>
      <BarChart data={data} layout="vertical" margin={{ left: 0, right: 56, top: 4, bottom: 4 }} barCategoryGap={6}>
        <XAxis type="number" domain={[0, 120]} hide />
        <YAxis type="category" dataKey="name" tickLine={false} axisLine={false} width={80} tickMargin={4} />
        <ReferenceLine x={100} stroke="var(--border)" strokeDasharray="3 3" />
        <Bar
          dataKey="pace"
          radius={4}
          background={{ fill: "var(--muted)", radius: 4 }}
          isAnimationActive={false}
          className={onSelect ? "cursor-pointer" : undefined}
          onClick={(d: { payload?: { code?: string } }) => d.payload?.code && onSelect?.(d.payload.code)}
        >
          {data.map((d) => (
            <Cell key={d.code} fill={d.fill} />
          ))}
          <LabelList dataKey="label" position="right" className="fill-foreground text-caption tabular-nums" />
        </Bar>
      </BarChart>
    </ChartContainer>
  );
}

export function AreaPaceCard({ area, onOpen }: { area: BizAreaHealth; onOpen: () => void }) {
  const p = areaPace(area);
  const info = areaOf(area.code);
  const kpis = area.kpis ?? [];
  return (
    <button
      type="button"
      onClick={onOpen}
      className="group flex flex-col gap-3 rounded-lg border bg-card p-4 text-left transition-colors hover:bg-accent/40"
    >
      <div className="flex items-start gap-2">
        <AreaDot area={area.code} className="mt-1.5" />
        <div className="min-w-0 flex-1">
          <div className="text-body font-semibold">{area.name}</div>
          <div className="truncate text-caption text-muted-foreground">{area.transforms || info.transforms}</div>
        </div>
        <PaceLabel band={p.band} />
      </div>

      <div className="space-y-1.5">
        <div className="flex items-baseline gap-1.5">
          <span className={cn("text-title font-semibold tabular-nums", p.pace === null && "text-muted-foreground")}>{p.pace === null ? "—" : `${p.pace} %`}</span>
          <span className="text-caption text-muted-foreground">del ritmo</span>
        </div>
        <PaceBar band={p.band} progress={p.progress} expected={p.expected} />
        <p className="truncate text-caption text-muted-foreground" title={p.ruling?.name}>
          {p.ruling ? (
            <>
              Manda <span className="text-foreground">{p.ruling.name}</span>: {formatKpiValue(p.ruling.value, p.ruling.unit)} de {formatKpiValue(p.ruling.target, p.ruling.unit)}
            </>
          ) : (
            "Ningún indicador con dato y meta"
          )}
        </p>
      </div>

      {kpis.length > 0 ? (
        <ul className="space-y-1.5 border-t pt-3">
          {kpis.slice(0, 4).map((k) => {
            const kp = kpiPace(k);
            return (
              <li key={k.code} className="grid grid-cols-[minmax(0,1fr)_auto_3rem] items-center gap-2 text-caption">
                <span className="truncate text-muted-foreground" title={k.name}>{k.name}</span>
                <span className="tabular-nums">{formatKpiValue(k.value, k.unit)}</span>
                {kp.band === "no_data" ? (
                  <span className="text-right text-micro text-muted-foreground">sin meta</span>
                ) : (
                  <PaceBar band={kp.band} progress={kp.progress} expected={kp.expected} className="h-1" />
                )}
              </li>
            );
          })}
        </ul>
      ) : null}

      <div className="mt-auto flex flex-wrap items-center gap-x-2 text-micro text-muted-foreground">
        <span>Etapa {area.maturity.stage} · {area.maturity.label}</span>
        <span aria-hidden="true">·</span>
        <span className={cn(area.exceptions > 0 && "text-foreground")}>{area.exceptions === 0 ? "Sin excepciones" : area.exceptions === 1 ? "1 excepción" : `${area.exceptions} excepciones`}</span>
        {area.paused ? (
          <>
            <span aria-hidden="true">·</span>
            <span className="font-medium text-warning">En pausa</span>
          </>
        ) : null}
        <span className="ml-auto">{p.measured}/{p.total} medidos</span>
      </div>
    </button>
  );
}
