// @vitest-environment node

import { describe, expect, it } from "vitest";
import type { BizKpi } from "./api";
import { areaPace, kpiPace, paceBand, paceInfo } from "./pace";

const kpi = (over: Partial<BizKpi>): BizKpi => ({
  code: "K",
  area: "ventas",
  name: "K",
  unit: "",
  formula: "",
  direction: "up",
  period: "",
  value: null,
  target: null,
  alert: null,
  status: "no_data",
  explanation: "",
  source: "",
  enabled: true,
  ...over,
});

describe("paceBand", () => {
  it("keeps the old program's cut-offs", () => {
    expect(paceBand(105)).toBe("ahead");
    expect(paceBand(104)).toBe("on_track");
    expect(paceBand(95)).toBe("on_track");
    expect(paceBand(94)).toBe("attention");
    expect(paceBand(80)).toBe("attention");
    expect(paceBand(79)).toBe("at_risk");
    expect(paceBand(55)).toBe("at_risk");
    expect(paceBand(54)).toBe("critical");
    expect(paceBand(null)).toBe("no_data");
  });
});

describe("kpiPace", () => {
  it("measures a cumulative KPI against today's trajectory", () => {
    const p = kpiPace(kpi({ value: 400, target: 1000, expected: 500, status: "warning" }));
    expect(p).toEqual({ pace: 80, progress: 40, expected: 50, band: "attention" });
  });

  it("measures a plain KPI against its target", () => {
    expect(kpiPace(kpi({ value: 70, target: 80, status: "warning" })).pace).toBe(88);
  });

  it("inverts KPIs where lower is better", () => {
    expect(kpiPace(kpi({ direction: "down", value: 0, target: 0, status: "ok" })).band).toBe("on_track");
    const p = kpiPace(kpi({ direction: "down", value: 10, target: 5, status: "warning" }));
    expect(p.pace).toBe(50);
    expect(p.band).toBe("critical");
    // Between target and alert the pace falls from 100 % to 55 %.
    const q = kpiPace(kpi({ direction: "down", value: 3, target: 0, alert: 5, status: "warning" }));
    expect(q.pace).toBe(73);
    expect(q.band).toBe("at_risk");
    expect(kpiPace(kpi({ direction: "down", value: 5, target: 0, alert: 5, status: "alert" })).pace).toBe(55);
  });

  it("never shows a KPI in alert as better than at risk", () => {
    expect(kpiPace(kpi({ value: 90, target: 100, alert: 92, status: "alert" })).band).toBe("at_risk");
  });

  it("says «sin meta», never a verdict, when no target is configured", () => {
    const p = kpiPace(kpi({ value: 0, status: "not_configured" }));
    expect(p.band).toBe("no_target");
    expect(p.pace).toBeNull();
    expect(paceInfo(p.band).label).toBe("Sin meta");
  });

  it("skips KPIs without data or disabled", () => {
    expect(kpiPace(kpi({ value: 3, target: 5, status: "ok", enabled: false })).band).toBe("no_data");
  });
});

describe("areaPace", () => {
  it("is ruled by the most delayed KPI", () => {
    const slow = kpi({ code: "SLOW", value: 50, target: 100, status: "warning" });
    const p = areaPace({
      kpis: [kpi({ code: "FAST", value: 120, target: 100, status: "ok" }), slow, kpi({ code: "NONE", status: "no_data" })],
    });
    expect(p.ruling?.code).toBe("SLOW");
    expect(p.band).toBe("critical");
    expect(p.measured).toBe(2);
    expect(p.total).toBe(3);
  });

  it("reports no data when nothing is measurable", () => {
    expect(areaPace({ kpis: [kpi({})] }).band).toBe("no_data");
  });

  it("is «sin meta» when its KPIs have values but no target", () => {
    const p = areaPace({ kpis: [kpi({ value: 0, status: "not_configured" }), kpi({})] });
    expect(p.band).toBe("no_target");
    expect(p.ruling).toBeNull();
  });
});
