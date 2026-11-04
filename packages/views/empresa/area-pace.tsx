"use client";

import { areaPace, formatKpiValue, paceInfo, type BizAreaHealth, type PaceBand, type PaceTone } from "@multica/core/biz";
import { cn } from "@multica/ui/lib/utils";
import { ListRow } from "./shared";

// Pace is a word ("En ritmo", "En riesgo"…). Colour only reinforces it:
// green on track, amber attention, red behind. No icon, no legend needed.
const TONE: Record<PaceTone, string> = {
  good: "text-success",
  attention: "text-warning",
  risk: "text-destructive",
  critical: "text-destructive",
  none: "text-muted-foreground",
};

export function PaceLabel({ band, className }: { band: PaceBand; className?: string }) {
  const info = paceInfo(band);
  return <span className={cn("text-caption", TONE[info.tone], className)}>{info.label}</span>;
}

/** One row per area: name and the KPI that rules it, pace % and its word. */
export function AreaPaceRow({ area, onOpen }: { area: BizAreaHealth; onOpen: () => void }) {
  const p = areaPace(area);
  return (
    <ListRow
      onClick={onOpen}
      primary={area.name}
      secondary={
        p.ruling
          ? `${p.ruling.name} · ${formatKpiValue(p.ruling.value, p.ruling.unit)} de ${formatKpiValue(p.ruling.target, p.ruling.unit)}`
          : p.band === "no_target"
            ? "Indicadores sin meta configurada"
            : "Ningún indicador con dato y meta"
      }
      value={<span className={cn(p.pace === null && "text-muted-foreground")}>{p.pace === null ? "—" : `${p.pace} %`}</span>}
      detail={<PaceLabel band={p.band} />}
    />
  );
}
