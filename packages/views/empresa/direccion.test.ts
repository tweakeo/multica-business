import { describe, expect, it } from "vitest";
import { compare, euros, previousAtSamePoint } from "./direccion";

describe("vistas de Dirección", () => {
  it("dice «Sin datos» en vez de cero cuando no se sabe", () => {
    expect(euros(null)).toBe("Sin datos");
    expect(euros(undefined)).toBe("Sin datos");
    expect(euros(0)).toMatch(/^0\s?€$/);
  });

  it("solo compara periodos con datos en los dos lados", () => {
    expect(compare(684, null)).toBeNull();
    expect(compare(null, 684)).toBeNull();
    expect(compare(1202.7, 684)).toEqual({ delta: 1202.7 - 684, pct: ((1202.7 - 684) / 684) * 100 });
    expect(compare(600, 0)).toEqual({ delta: 600, pct: null });
  });

  it("compara el periodo en curso con el anterior a la misma altura", () => {
    const base = { label: "", end: "", invoices: 0, no_amount: 0, partial: false, reason: "" };
    const prev = { ...base, key: "2026-T3", start: "2026-07-01", current: false, invoiced: 1902.7, items: [
      { date: "2026-07-15", number: "F8", party: "", amount: 1202.7, path: "", id: "a" },
      { date: "2026-09-20", number: "F9", party: "", amount: 700, path: "", id: "b" },
    ] };
    const cur = { ...base, key: "2026-T4", start: "2026-10-01", current: true, invoiced: 0, items: [] };
    expect(previousAtSamePoint(cur, prev, "2026-10-21")).toBe(1202.7);
    expect(previousAtSamePoint({ ...cur, current: false }, prev, "2026-10-21")).toBe(1902.7);
    const unknown = { ...prev, items: [{ ...prev.items[0]!, amount: null }] };
    expect(previousAtSamePoint(cur, unknown, "2026-10-21")).toBeNull();
  });
});
