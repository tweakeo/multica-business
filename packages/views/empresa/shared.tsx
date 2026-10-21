/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { createContext, useContext, type ReactNode } from "react";
import { toast } from "sonner";
import type { BizKpi } from "@multica/core/biz";
import { formatKpiValue, useBizRun } from "@multica/core/biz";
import { cn } from "@multica/ui/lib/utils";
import { Skeleton } from "@multica/ui/components/ui/skeleton";

export const AREAS = [
  { code: "direccion", name: "Dirección", transforms: "Ruido en decisiones", role: "Director", dot: "bg-area-direccion", text: "text-area-direccion", border: "border-area-direccion" },
  { code: "ventas", name: "Ventas", transforms: "Desconocidos en clientes", role: "Comercial", dot: "bg-area-ventas", text: "text-area-ventas", border: "border-area-ventas" },
  { code: "entrega", name: "Entrega", transforms: "Promesas en resultados", role: "Implementador", dot: "bg-area-entrega", text: "text-area-entrega", border: "border-area-entrega" },
  { code: "finanzas", name: "Finanzas", transforms: "Actividad en caja y margen", role: "Financiero", dot: "bg-area-finanzas", text: "text-area-finanzas", border: "border-area-finanzas" },
  { code: "marca", name: "Marca", transforms: "Mercado en demanda", role: "Responsable de Marca", dot: "bg-area-marca", text: "text-area-marca", border: "border-area-marca" },
  { code: "equipo", name: "Equipo", transforms: "Personas y agentes en capacidad", role: "Responsable de Equipo", dot: "bg-area-equipo", text: "text-area-equipo", border: "border-area-equipo" },
] as const;

export type AreaCode = (typeof AREAS)[number]["code"];

export function areaOf(code: string) {
  return AREAS.find((a) => a.code === code) ?? AREAS[0];
}

export function AreaDot({ area, className }: { area: string; className?: string }) {
  return <span aria-hidden="true" className={cn("inline-block size-2 shrink-0 rounded-full", areaOf(area).dot, className)} />;
}

export function AreaTag({ area }: { area: string }) {
  return <span className="text-caption text-muted-foreground">{areaOf(area).name}</span>;
}

// A status is a word; colour only reinforces meaning (green good, red bad)
// and never carries it alone, so no icon is needed next to it.
const STATUS: Record<string, { label: string; className: string }> = {
  ok: { label: "En meta", className: "text-success" },
  warning: { label: "Por debajo", className: "text-warning" },
  alert: { label: "Alerta", className: "text-destructive" },
  no_data: { label: "Sin datos", className: "text-muted-foreground" },
  not_configured: { label: "Sin meta", className: "text-muted-foreground" },
  disabled: { label: "Desactivado", className: "text-muted-foreground" },
  stale: { label: "Desactualizado", className: "text-warning" },
  paused: { label: "En pausa", className: "text-warning" },
  partial: { label: "Datos parciales", className: "text-warning" },
};

export function StatusBadge({ status, label }: { status: string; label?: string }) {
  const s = STATUS[status] ?? STATUS.no_data!;
  return <span className={cn("text-caption font-medium", s.className)}>{label ?? s.label}</span>;
}

const SEVERITY: Record<string, string> = {
  alta: "text-destructive",
  media: "text-warning",
  baja: "text-muted-foreground",
};

export function SeverityBadge({ severity }: { severity: string }) {
  return <span className={cn("text-caption font-medium capitalize", SEVERITY[severity] ?? SEVERITY.baja)}>{severity}</span>;
}

/** Secondary metadata: plain grey text, no frame. */
export function Pill({ children, className }: { children: ReactNode; className?: string }) {
  return <span className={cn("inline-flex items-center text-caption text-muted-foreground", className)}>{children}</span>;
}

export function Section({ title, actions, children, className }: { title: ReactNode; actions?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={cn("space-y-3", className)}>
      <div className="flex items-baseline justify-between gap-2">
        <h2 className="text-title font-semibold tracking-tight">{title}</h2>
        {actions}
      </div>
      {children}
    </section>
  );
}

/**
 * The list row of the minimal system: what it is on the left (with an
 * optional grey line under it), the figure and its context on the right. No
 * frame, no icon; rows separate by space and a hairline.
 */
export function ListRow({ primary, secondary, value, detail, onClick, className }: { primary: ReactNode; secondary?: ReactNode; value?: ReactNode; detail?: ReactNode; onClick?: () => void; className?: string }) {
  const body = (
    <>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-body-lg">{primary}</span>
        {secondary ? <span className="block truncate text-caption text-muted-foreground">{secondary}</span> : null}
      </span>
      {value !== undefined || detail ? (
        <span className="shrink-0 text-right">
          {value !== undefined ? <span className="block text-body-lg tabular-nums">{value}</span> : null}
          {detail ? <span className="block text-caption tabular-nums">{detail}</span> : null}
        </span>
      ) : null}
    </>
  );
  const cls = cn("flex w-full items-center gap-4 py-3.5 text-left", className);
  return onClick ? (
    <button type="button" onClick={onClick} className={cn(cls, "transition-opacity hover:opacity-60 focus-visible:opacity-60 focus-visible:outline-none")}>
      {body}
    </button>
  ) : (
    <div className={cls}>{body}</div>
  );
}

export function EmptyHint({ title, next }: { title: string; next?: ReactNode }) {
  return (
    <div className="py-6">
      <p className="text-body text-muted-foreground">{title}</p>
      {next ? <p className="mt-1 text-caption text-muted-foreground">{next}</p> : null}
    </div>
  );
}

export function LoadingBlock({ rows = 3 }: { rows?: number }) {
  return (
    <div className="space-y-2" aria-busy="true">
      {Array.from({ length: rows }, (_, i) => (
        <Skeleton key={i} className="h-10 rounded-md" />
      ))}
    </div>
  );
}

export function ErrorBlock({ error, retry }: { error: unknown; retry?: () => void }) {
  return (
    <div role="alert" className="py-3 text-caption">
      <p className="font-medium text-destructive">No se pudo cargar</p>
      <p className="mt-0.5 text-muted-foreground">{error instanceof Error ? error.message : String(error)}</p>
      {retry ? (
        <button type="button" className="mt-2 text-caption underline" onClick={retry}>
          Reintentar
        </button>
      ) : null}
    </div>
  );
}

export function KpiValue({ kpi }: { kpi: BizKpi }) {
  return <span className="tabular-nums">{formatKpiValue(kpi.value, kpi.unit)}</span>;
}

/** Runs a business action and reports the honest outcome. */
export function useAction() {
  const run = useBizRun();
  const exec = async (action: string, payload: unknown, success?: string) => {
    try {
      const res = await run.mutateAsync({ action, payload });
      if (res.status === "approval_required") {
        toast.info("Pendiente de aprobación", { description: "La acción no se ha ejecutado: la decide una persona autorizada." });
      } else if (success) {
        toast.success(success);
      }
      return res;
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err));
      throw err;
    }
  };
  return { exec, pending: run.isPending };
}

// --- Inspector context ------------------------------------------------------

type InspectorTarget = { entity: string; id: string } | null;
const InspectorContext = createContext<(target: InspectorTarget) => void>(() => {});

export const InspectorProvider = InspectorContext.Provider;

export function useInspector() {
  return useContext(InspectorContext);
}

export function RecordLink({ entity, id, children, className }: { entity: string; id: unknown; children: ReactNode; className?: string }) {
  const open = useInspector();
  if (typeof id !== "string" || !id) return <>{children}</>;
  return (
    <button type="button" className={cn("text-left hover:underline focus-visible:underline", className)} onClick={() => open({ entity, id })}>
      {children}
    </button>
  );
}

export function str(v: unknown): string {
  if (v === null || v === undefined) return "";
  return typeof v === "string" ? v : String(v);
}

export function num(v: unknown): number {
  return typeof v === "number" ? v : Number(v ?? 0) || 0;
}
