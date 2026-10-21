/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { Line, LineChart, Tooltip, YAxis } from "recharts";
import { bizListOptions, formatDate, formatKpiValue } from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { ChartContainer, type ChartConfig } from "@multica/ui/components/ui/chart";
import { cn } from "@multica/ui/lib/utils";
import { num, str } from "./shared";

const PERIODS = [
  { key: "1S", days: 7 },
  { key: "1M", days: 30 },
  { key: "3M", days: 91 },
  { key: "1A", days: 365 },
  { key: "Todo", days: null },
] as const;
type PeriodKey = (typeof PERIODS)[number]["key"];

const DAY = 86_400_000;
const iso = (t: number) => new Date(t).toISOString().slice(0, 10);
const pctFmt = new Intl.NumberFormat("es-ES", { maximumFractionDigits: 1, signDisplay: "always" });

/**
 * Cash over time, rebuilt backwards from today's balance: the balance on a
 * day is today's cash minus every movement booked after it. Points sit on the
 * days something moved, so the line only bends where money did.
 */
export function cashSeries(cash: number, movements: { booked_on: string; amount: number }[], from: string, to: string) {
  const sorted = [...movements].sort((a, b) => b.booked_on.localeCompare(a.booked_on));
  const points: { date: string; value: number }[] = [{ date: to, value: cash }];
  let running = cash;
  for (const m of sorted) {
    if (m.booked_on > to) {
      running -= m.amount;
      points[0]!.value = running;
      continue;
    }
    if (m.booked_on < from) break;
    // Balance at the end of the movement's day, then step back past it.
    if (points[0]!.date !== m.booked_on) points.unshift({ date: m.booked_on, value: running });
    running -= m.amount;
  }
  if (points[0]!.date !== from) points.unshift({ date: from, value: running });
  return points;
}

const chartConfig = { value: { label: "Caja" } } satisfies ChartConfig;

/** The protagonist of Empresa: available cash, its change and one clean line. */
export function CashHero({ cash, coverage }: { cash: number | null; coverage: string }) {
  const wsId = useWorkspaceId();
  const [period, setPeriod] = useState<PeriodKey>("3M");
  const movements = useQuery(bizListOptions(wsId, "movement", { limit: "1999" }));
  const rows = (movements.data ?? []).map((m) => ({ booked_on: str(m.booked_on).slice(0, 10), amount: num(m.amount_minor) / 100 }));
  const today = iso(Date.now());
  const days = PERIODS.find((p) => p.key === period)?.days ?? null;
  const earliest = rows.reduce((min, m) => (m.booked_on && m.booked_on < min ? m.booked_on : min), today);
  const from = days === null ? iso(Date.parse(earliest) - DAY) : iso(Date.now() - days * DAY);
  const data = cash === null ? [] : cashSeries(cash, rows, from, today);
  const start = data[0]?.value ?? null;
  const delta = cash !== null && start !== null ? cash - start : null;
  const up = (delta ?? 0) >= 0;
  const stroke = delta === null || delta === 0 ? "var(--chart-1)" : up ? "var(--success)" : "var(--destructive)";

  return (
    <section>
      <p className="text-body text-muted-foreground">Caja disponible</p>
      <p className="mt-1 text-hero tabular-nums">{formatKpiValue(cash, "EUR")}</p>
      <p className={cn("mt-1 text-body tabular-nums", delta === null || delta === 0 ? "text-muted-foreground" : up ? "text-success" : "text-destructive")}>
        {delta === null ? coverage : (
          <>
            {up ? "+" : "−"}{formatKpiValue(Math.abs(delta), "EUR")}
            {start ? ` (${pctFmt.format((delta / Math.abs(start)) * 100)} %)` : ""}
            <span className="text-muted-foreground"> · {period === "Todo" ? "desde el inicio" : `en ${period}`}</span>
          </>
        )}
      </p>

      <div className="mt-8 h-56">
        {data.length > 1 ? (
          <ChartContainer config={chartConfig} className="aspect-auto h-full w-full" initialDimension={{ width: 720, height: 224 }}>
            <LineChart data={data} margin={{ top: 8, right: 0, bottom: 8, left: 0 }}>
              <YAxis hide domain={["dataMin", "dataMax"]} />
              <Tooltip
                cursor={{ stroke: "var(--border)", strokeWidth: 1 }}
                content={({ active, payload }) => {
                  const pt = active ? (payload?.[0]?.payload as { date: string; value: number } | undefined) : undefined;
                  return pt ? (
                    <div className="text-caption">
                      <div className="font-medium tabular-nums">{formatKpiValue(pt.value, "EUR")}</div>
                      <div className="text-muted-foreground">{formatDate(pt.date)}</div>
                    </div>
                  ) : null;
                }}
              />
              <Line type="monotone" dataKey="value" stroke={stroke} strokeWidth={2} dot={false} activeDot={{ r: 4, strokeWidth: 0, fill: stroke }} isAnimationActive={false} />
            </LineChart>
          </ChartContainer>
        ) : (
          <div className="flex h-full items-center text-caption text-muted-foreground">
            {movements.isLoading ? "" : "Sin movimientos suficientes para dibujar la evolución."}
          </div>
        )}
      </div>

      <div role="tablist" className="mt-4 flex gap-1">
        {PERIODS.map((p) => (
          <button
            key={p.key}
            type="button"
            role="tab"
            aria-selected={period === p.key}
            onClick={() => setPeriod(p.key)}
            className={cn(
              "rounded-full px-3 py-1 text-label font-medium transition-colors",
              period === p.key ? "bg-secondary text-foreground" : "text-muted-foreground hover:text-foreground",
            )}
          >
            {p.key}
          </button>
        ))}
      </div>
    </section>
  );
}
