/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { createContext, useContext, type ReactNode } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  CircleDashed,
  CircleHelp,
  CircleSlash,
  Clock,
  OctagonAlert,
  PauseCircle,
} from "lucide-react";
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
  const a = areaOf(area);
  return (
    <span className="inline-flex items-center gap-1.5 text-caption text-muted-foreground">
      <AreaDot area={area} />
      {a.name}
    </span>
  );
}

// Every status pairs an icon and a word: colour is never the only signal.
const STATUS: Record<string, { label: string; icon: typeof CheckCircle2; className: string }> = {
  ok: { label: "En meta", icon: CheckCircle2, className: "text-success" },
  warning: { label: "Por debajo", icon: AlertTriangle, className: "text-warning" },
  alert: { label: "Alerta", icon: OctagonAlert, className: "text-destructive" },
  no_data: { label: "Sin datos", icon: CircleDashed, className: "text-muted-foreground" },
  not_configured: { label: "Sin meta", icon: CircleHelp, className: "text-muted-foreground" },
  disabled: { label: "Desactivado", icon: CircleSlash, className: "text-muted-foreground" },
  stale: { label: "Desactualizado", icon: Clock, className: "text-warning" },
  paused: { label: "En pausa", icon: PauseCircle, className: "text-warning" },
  partial: { label: "Datos parciales", icon: CircleDashed, className: "text-warning" },
};

export function StatusBadge({ status, label }: { status: string; label?: string }) {
  const s = STATUS[status] ?? STATUS.no_data!;
  const Icon = s.icon;
  return (
    <span className={cn("inline-flex items-center gap-1 text-caption font-medium", s.className)}>
      <Icon aria-hidden="true" className="size-3.5" />
      {label ?? s.label}
    </span>
  );
}

const SEVERITY: Record<string, string> = {
  alta: "bg-destructive/10 text-destructive",
  media: "bg-warning/10 text-warning",
  baja: "bg-muted text-muted-foreground",
};

export function SeverityBadge({ severity }: { severity: string }) {
  return (
    <span className={cn("rounded px-1.5 py-0.5 text-micro font-medium uppercase tracking-wide", SEVERITY[severity] ?? SEVERITY.baja)}>
      {severity}
    </span>
  );
}

export function Pill({ children, className }: { children: ReactNode; className?: string }) {
  return <span className={cn("inline-flex items-center rounded-md border px-1.5 py-0.5 text-caption text-muted-foreground", className)}>{children}</span>;
}

export function Section({ title, actions, children, className }: { title: ReactNode; actions?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={cn("space-y-2", className)}>
      <div className="flex items-center justify-between gap-2">
        <h2 className="text-label font-medium text-muted-foreground">{title}</h2>
        {actions}
      </div>
      {children}
    </section>
  );
}

export function EmptyHint({ title, next }: { title: string; next?: ReactNode }) {
  return (
    <div className="rounded-lg border border-dashed px-4 py-6 text-center">
      <p className="text-body font-medium">{title}</p>
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
    <div role="alert" className="rounded-lg border border-destructive/30 bg-destructive/5 px-4 py-3 text-caption">
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
