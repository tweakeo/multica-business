import type { BizAreaHealth, BizKpi } from "./api";

// "Ritmo" from The Last System v0.5: how a KPI is doing against where it
// should be today (the linear trajectory for cumulative monthly KPIs, the
// target otherwise). The area shows its most delayed KPI, because that is
// the one that rules. Bands keep the old program's cut-offs.

export type PaceBand = "ahead" | "on_track" | "attention" | "at_risk" | "critical" | "no_data";

export const PACE_BANDS: { band: Exclude<PaceBand, "no_data">; min: number; label: string; tone: PaceTone }[] = [
  { band: "ahead", min: 105, label: "Por delante", tone: "good" },
  { band: "on_track", min: 95, label: "En ritmo", tone: "good" },
  { band: "attention", min: 80, label: "Atención", tone: "attention" },
  { band: "at_risk", min: 55, label: "En riesgo", tone: "risk" },
  { band: "critical", min: 0, label: "Crítico", tone: "critical" },
];

export type PaceTone = "good" | "attention" | "risk" | "critical" | "none";

export const PACE_NO_DATA = { label: "Sin dato", tone: "none" as PaceTone };

export function paceBand(pct: number | null): PaceBand {
  if (pct === null || !Number.isFinite(pct)) return "no_data";
  return PACE_BANDS.find((b) => pct >= b.min)?.band ?? "critical";
}

export function paceInfo(band: PaceBand) {
  return PACE_BANDS.find((b) => b.band === band) ?? PACE_NO_DATA;
}

export interface KpiPace {
  /** Value against where it should be today, in %. null when not measurable. */
  pace: number | null;
  /** Value against the full target, in % (0–100 capped). */
  progress: number | null;
  /** Where it should be today against the full target, in %; only for cumulative KPIs. */
  expected: number | null;
  band: PaceBand;
}

const NONE: KpiPace = { pace: null, progress: null, expected: null, band: "no_data" };
const MEASURED = new Set(["ok", "warning", "alert"]);
const clamp = (n: number) => Math.max(0, Math.min(100, n));

export function kpiPace(k: BizKpi): KpiPace {
  if (!k.enabled || !MEASURED.has(k.status) || k.value === null || k.target === null || k.direction === "range") return NONE;
  const v = k.value;
  const target = k.target;
  const due = k.expected ?? target;
  let pace: number | null;
  let progress: number | null;
  if (k.direction === "down") {
    // Lower is better: at or under the target is on pace. Above it, the pace
    // falls linearly so that reaching the alert threshold lands on 55 % (the
    // edge of "en riesgo"); without an alert, target / value.
    pace = downPace(v, due, k.alert);
    progress = pace;
  } else {
    pace = due > 0 ? (v / due) * 100 : 100;
    progress = target > 0 ? (v / target) * 100 : 100;
  }
  let band = paceBand(pace);
  // The server already judged it against the configured alert threshold:
  // never show an alert KPI as better than "en riesgo", nor a met one as worse.
  if (k.status === "alert" && (band === "no_data" || rank(band) < rank("at_risk"))) band = "at_risk";
  if (k.status === "ok" && (band === "no_data" || rank(band) > rank("on_track"))) band = "on_track";
  if (k.status === "warning" && band === "no_data") band = "attention";
  const expected = k.expected != null && target > 0 && k.direction !== "down" ? clamp((k.expected / target) * 100) : null;
  return { pace: pace === null ? null : Math.round(pace), progress: progress === null ? null : Math.round(clamp(progress)), expected, band };
}

function downPace(v: number, target: number, alert: number | null): number | null {
  if (v <= target) return 100;
  if (alert !== null && alert > target) return Math.max(0, 100 - (45 * (v - target)) / (alert - target));
  return target > 0 ? (target / v) * 100 : null;
}

function rank(b: PaceBand): number {
  return ["ahead", "on_track", "attention", "at_risk", "critical", "no_data"].indexOf(b);
}

export interface AreaPace extends KpiPace {
  /** The most delayed measured KPI, which sets the area's pace. */
  ruling: BizKpi | null;
  measured: number;
  total: number;
}

export function areaPace(area: Pick<BizAreaHealth, "kpis">): AreaPace {
  const kpis = area.kpis ?? [];
  let ruling: BizKpi | null = null;
  let best: KpiPace = NONE;
  let measured = 0;
  for (const k of kpis) {
    const p = kpiPace(k);
    if (p.band === "no_data") continue;
    measured++;
    if (!ruling || worse(p, best)) {
      ruling = k;
      best = p;
    }
  }
  return { ...best, ruling, measured, total: kpis.length };
}

function worse(a: KpiPace, b: KpiPace): boolean {
  if (rank(a.band) !== rank(b.band)) return rank(a.band) > rank(b.band);
  return (a.pace ?? Infinity) < (b.pace ?? Infinity);
}
