import { describe, expect, it } from "vitest";
import { day, inDates } from "./databases";

const now = new Date(Date.UTC(2026, 9, 21, 12));

describe("Bases de datos · date filter", () => {
  it("keeps everything without a filter and drops undated rows with one", () => {
    expect(inDates("", "", "", "", now)).toBe(true);
    expect(inDates("", "year", "", "", now)).toBe(false);
  });

  it("reads quarters and months as periods", () => {
    expect(inDates("2026-10-02", "quarter", "", "", now)).toBe(true);
    expect(inDates("2026-09-30", "quarter", "", "", now)).toBe(false);
    // «2026-09» (T3) overlaps a range that starts on 15 September.
    expect(inDates("2026-09", "range", "2026-09-15", "2026-10-01", now)).toBe(true);
    expect(inDates("2026-08", "range", "2026-09-15", "", now)).toBe(false);
  });

  it("covers the last 30 days and the current year", () => {
    expect(inDates("2026-09-25", "30", "", "", now)).toBe(true);
    expect(inDates("2026-09-01", "30", "", "", now)).toBe(false);
    expect(inDates("2026-01-01", "year", "", "", now)).toBe(true);
    expect(inDates("2025-12-31", "year", "", "", now)).toBe(false);
  });

  it("formats months and unknown dates", () => {
    expect(day("")).toBe("—");
    expect(day("2026-09")).toMatch(/sept?\.? 2026/);
  });
});
