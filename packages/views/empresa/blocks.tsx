/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useState } from "react";
import { ArrowRight, Bot, Check, ExternalLink, X } from "lucide-react";
import type { BizException, BizKpi, BizRow } from "@multica/core/biz";
import { formatDateTime, formatKpiValue, useBizDecide } from "@multica/core/biz";
import { useWorkspacePaths } from "@multica/core/paths";
import { Button } from "@multica/ui/components/ui/button";
import { Textarea } from "@multica/ui/components/ui/textarea";
import { cn } from "@multica/ui/lib/utils";
import { toast } from "sonner";
import { useNavigation } from "../navigation";
import { AreaTag, EmptyHint, Pill, SeverityBadge, StatusBadge, str, useInspector } from "./shared";

export function KpiGrid({ kpis, compact }: { kpis: BizKpi[]; compact?: boolean }) {
  const nav = useNavigation();
  const p = useWorkspacePaths();
  if (kpis.length === 0) return <EmptyHint title="Sin indicadores configurados" next="Configúralos en la pestaña Sistemas." />;
  return (
    <div className={cn("grid gap-2", compact ? "grid-cols-2 xl:grid-cols-3" : "grid-cols-2 lg:grid-cols-3 xl:grid-cols-4")}>
      {kpis.map((k) => {
        const href = k.source ? `${p.empresa().replace(/\/empresa$/, "")}${k.source}` : "";
        return (
          <div key={k.code} className="group flex flex-col gap-1.5 rounded-lg border bg-card p-3">
            <div className="flex items-start justify-between gap-2">
              <span className="text-caption text-muted-foreground">{k.name}</span>
              <StatusBadge status={k.status} />
            </div>
            <div className="text-title font-semibold tabular-nums">{formatKpiValue(k.value, k.unit)}</div>
            <div className="text-micro text-muted-foreground">
              {k.target !== null ? (
                <>
                  Meta {formatKpiValue(k.target, k.unit)}
                  {k.expected !== undefined && k.expected !== null ? ` · esperado hoy ${formatKpiValue(k.expected, k.unit)}` : ""}
                  {k.alert !== null ? ` · alerta ${formatKpiValue(k.alert, k.unit)}` : ""}
                </>
              ) : (
                "Sin meta"
              )}
            </div>
            {k.explanation || k.coverage ? (
              <p className="line-clamp-2 text-micro text-muted-foreground" title={`${k.formula}\n${k.explanation}\n${k.coverage ?? ""}`}>
                {k.explanation || k.coverage}
              </p>
            ) : null}
            {href ? (
              <button type="button" className="mt-auto inline-flex items-center gap-1 self-start text-micro text-muted-foreground hover:text-foreground" onClick={() => nav.push(href)}>
                Ver datos <ArrowRight className="size-3" />
              </button>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}

const FACTOR_LABEL: Record<string, string> = {
  urgencia: "urgencia",
  impacto: "impacto",
  riesgo: "riesgo",
  antiguedad_dias: "días",
  dias_vencida: "días vencida",
};

export function ExceptionList({ items, showArea, limit, onAskAgent }: { items: BizException[]; showArea?: boolean; limit?: number; onAskAgent?: (e: BizException) => void }) {
  const open = useInspector();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const [expanded, setExpanded] = useState<string | null>(null);
  const shown = limit ? items.slice(0, limit) : items;
  if (items.length === 0) return <EmptyHint title="Nada requiere tu atención" next="Las excepciones aparecen aquí con qué pasa, por qué importa y qué hacer." />;
  return (
    <ul className="divide-y rounded-lg border">
      {shown.map((e, i) => {
        const key = `${e.kind}-${e.entity_id}-${i}`;
        const isOpen = expanded === key;
        const openEntity = () => {
          if (!e.entity_id) return;
          if (e.entity_type === "issue") nav.push(p.issueDetail(e.entity_id));
          else if (e.entity_type === "project") nav.push(p.projectDetail(e.entity_id));
          else if (e.entity_type === "agent") nav.push(p.agentDetail(e.entity_id));
          else open({ entity: e.entity_type, id: e.entity_id });
        };
        return (
          <li key={key} className="px-3 py-2.5">
            <div className="flex items-start gap-2">
              <SeverityBadge severity={e.severity} />
              <div className="min-w-0 flex-1">
                <button type="button" className="text-left text-body font-medium hover:underline" onClick={() => setExpanded(isOpen ? null : key)} aria-expanded={isOpen}>
                  {e.title}
                </button>
                <p className="text-caption text-muted-foreground">{e.what}</p>
                {isOpen ? (
                  <dl className="mt-2 grid gap-1 text-caption sm:grid-cols-[8rem_1fr]">
                    <dt className="text-muted-foreground">Por qué importa</dt>
                    <dd>{e.why}</dd>
                    <dt className="text-muted-foreground">Qué hacer</dt>
                    <dd>{e.action}</dd>
                    <dt className="text-muted-foreground">Si no se actúa</dt>
                    <dd>{e.consequence}</dd>
                    <dt className="text-muted-foreground">Recomendación</dt>
                    <dd>{e.recommendation}</dd>
                    <dt className="text-muted-foreground">Prioridad</dt>
                    <dd className="flex flex-wrap gap-1">
                      {Object.entries(e.factors ?? {}).map(([k, v]) => (
                        <Pill key={k}>
                          {FACTOR_LABEL[k] ?? k}: {v}
                        </Pill>
                      ))}
                      <Pill>puntuación {e.score}</Pill>
                      {e.capability ? <Pill>{e.capability}</Pill> : null}
                    </dd>
                  </dl>
                ) : null}
              </div>
              <div className="flex shrink-0 items-center gap-1">
                {showArea ? <AreaTag area={e.area} /> : null}
                {onAskAgent ? (
                  <Button variant="ghost" size="icon-sm" aria-label="Pedir al agente del área" title="Pedir al agente del área" onClick={() => onAskAgent(e)}>
                    <Bot />
                  </Button>
                ) : null}
                {e.entity_id ? (
                  <Button variant="ghost" size="icon-sm" aria-label="Abrir registro" title="Abrir registro" onClick={openEntity}>
                    <ExternalLink />
                  </Button>
                ) : null}
              </div>
            </div>
          </li>
        );
      })}
      {limit && items.length > limit ? <li className="px-3 py-2 text-caption text-muted-foreground">Y {items.length - limit} más…</li> : null}
    </ul>
  );
}

/** Approval card: what will happen, before/after, who asked, and the decision. */
export function ApprovalCard({ approval, canDecide }: { approval: BizRow; canDecide: boolean }) {
  const decide = useBizDecide();
  const [reason, setReason] = useState("");
  const [rejecting, setRejecting] = useState(false);
  const effects = (approval.effects as { field: string; before?: string; after?: string }[] | undefined) ?? [];
  const status = str(approval.status);
  const act = async (approve: boolean) => {
    try {
      const res = await decide.mutateAsync({ id: str(approval.id), approve, reason });
      const st = str((res as BizRow).status);
      if (st === "executed") toast.success("Aprobada y ejecutada");
      else if (st === "invalidated") toast.warning("Invalidada: el contenido o el registro cambiaron");
      else if (st === "rejected") toast.success("Rechazada con motivo");
      setRejecting(false);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : String(err));
    }
  };
  return (
    <div className="rounded-lg border bg-card p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-body font-medium">{str(approval.title)}</span>
        <AreaTag area={str(approval.area)} />
        <Pill>{str(approval.capability)}</Pill>
        <span className="ml-auto text-micro text-muted-foreground">
          {str(approval.requested_by_type) === "agent" ? "Agente" : "Persona"} · {str(approval.requested_by_name) || "—"} · {formatDateTime(approval.created_at)}
        </span>
      </div>
      {str(approval.summary) ? <p className="mt-2 whitespace-pre-wrap text-caption text-muted-foreground">{str(approval.summary)}</p> : null}
      {effects.length > 0 ? (
        <table className="mt-2 w-full text-caption">
          <thead>
            <tr className="text-left text-muted-foreground">
              <th className="py-1 font-normal">Campo</th>
              <th className="py-1 font-normal">Antes</th>
              <th className="py-1 font-normal">Después</th>
            </tr>
          </thead>
          <tbody>
            {effects.map((e, i) => (
              <tr key={i} className="border-t">
                <td className="py-1">{e.field}</td>
                <td className="py-1 text-muted-foreground">{e.before || "—"}</td>
                <td className="py-1 font-medium">{e.after || "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
      {status === "pending" ? (
        canDecide ? (
          <div className="mt-3 space-y-2">
            {rejecting ? (
              <Textarea value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Motivo del rechazo (obligatorio)" className="min-h-16" />
            ) : null}
            <div className="flex gap-2">
              <Button size="sm" onClick={() => act(true)} disabled={decide.isPending}>
                <Check /> Aprobar y ejecutar
              </Button>
              {rejecting ? (
                <Button size="sm" variant="destructive" disabled={!reason.trim() || decide.isPending} onClick={() => act(false)}>
                  Confirmar rechazo
                </Button>
              ) : (
                <Button size="sm" variant="outline" onClick={() => setRejecting(true)}>
                  <X /> Rechazar
                </Button>
              )}
            </div>
            <p className="text-micro text-muted-foreground">Al aprobar se comprueban de nuevo el contenido, la versión del registro y los controles globales.</p>
          </div>
        ) : (
          <p className="mt-2 text-caption text-muted-foreground">Solo propietarios y administradores deciden aprobaciones.</p>
        )
      ) : (
        <p className="mt-2 text-caption">
          <StatusBadge status={status === "executed" ? "ok" : status === "rejected" || status === "invalidated" || status === "failed" ? "alert" : "no_data"} label={APPROVAL_LABELS[status] ?? status} />
          {str(approval.reason) ? <span className="ml-2 text-muted-foreground">{str(approval.reason)}</span> : null}
        </p>
      )}
    </div>
  );
}

export const APPROVAL_LABELS: Record<string, string> = {
  pending: "Pendiente",
  approved: "Aprobada",
  executed: "Aprobada y ejecutada",
  rejected: "Rechazada",
  invalidated: "Invalidada",
  failed: "Falló al ejecutar",
  expired: "Caducada",
};

export function KpiInline({ kpi }: { kpi: BizKpi }) {
  return (
    <span className="inline-flex items-center gap-2">
      <span className="tabular-nums">{formatKpiValue(kpi.value, kpi.unit)}</span>
      <StatusBadge status={kpi.status} />
    </span>
  );
}
