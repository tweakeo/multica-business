/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useState, type ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { FileText, FolderOpen } from "lucide-react";
import {
  bizRecordOptions,
  ENTITY_LABELS,
  formatDate,
  formatDateTime,
  formatMinor,
  INVOICE_STATUS_LABELS,
  MOVEMENT_STATUS_LABELS,
  NATURE_LABELS,
  PERIOD_NEXT,
  PERIOD_STATUS_LABELS,
  STAGE_LABELS,
  CONTENT_STATUS_LABELS,
  type BizRow,
} from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { useWorkspacePaths } from "@multica/core/paths";
import { Button } from "@multica/ui/components/ui/button";
import { Input } from "@multica/ui/components/ui/input";
import { Textarea } from "@multica/ui/components/ui/textarea";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@multica/ui/components/ui/sheet";
import { useNavigation } from "../navigation";
import { APPROVAL_LABELS } from "./blocks";
import { ErrorBlock, LoadingBlock, Pill, RecordLink, str, num, useAction } from "./shared";

const HIDDEN = new Set([
  "workspace_id", "attrs", "entity_type", "proposal", "lines", "summary", "history", "payload", "effects", "template", "currency", "owner_type",
  "archived_at", "service_code", "import_hash", "import_batch", "requested_by_type", "occupant_type", "author_type", "payload_hash", "confirmed_by_type",
  "days_since_contact", "origin",
]);

// Fields shown first, in this order; the rest follow alphabetically.
const PRIORITY = ["title", "name", "number", "stage", "status", "value_minor", "total_minor", "amount_minor", "contact_name", "organization_name", "service_name",
  "owner_name", "next_action", "next_action_on", "last_contact_at", "issue_date", "due_date", "booked_on", "description", "decision", "why", "purpose", "context",
  "mission", "focus", "verdict", "notes", "body"];

function fieldOrder(a: string, b: string): number {
  const ia = PRIORITY.indexOf(a);
  const ib = PRIORITY.indexOf(b);
  if (ia !== -1 || ib !== -1) return (ia === -1 ? 999 : ia) - (ib === -1 ? 999 : ib);
  return (FIELD_LABELS[a] ?? a).localeCompare(FIELD_LABELS[b] ?? b, "es");
}

const FIELD_LABELS: Record<string, string> = {
  name: "Nombre", title: "Título", kind: "Tipo", email: "Email", phone: "Teléfono", position: "Cargo", tax_id: "NIF", sector: "Sector", city: "Ciudad",
  stage: "Etapa", value_minor: "Valor", owner_name: "Responsable", channel: "Canal", probability: "Probabilidad", next_action: "Próxima acción",
  next_action_on: "Fecha próxima acción", last_contact_at: "Último contacto", lost_reason: "Motivo de pérdida", contact_name: "Contacto",
  organization_name: "Organización", service_name: "Servicio", number: "Número", status: "Estado", direction: "Dirección", issue_date: "Emisión",
  due_date: "Vencimiento", base_minor: "Base", tax_minor: "IVA", withholding_minor: "Retención", total_minor: "Total", paid_minor: "Cobrado/pagado",
  category: "Categoría", nature: "Naturaleza", booked_on: "Fecha", amount_minor: "Importe", description: "Concepto", account_name: "Cuenta",
  invoice_number: "Factura", match_reason: "Motivo de conciliación", balance_after_minor: "Saldo", year: "Año", quarter: "Trimestre", package_path: "Paquete",
  evidence: "Evidencia", pillar: "Pilar", format: "Formato", scheduled_at: "Programado", published_at: "Publicado", evidence_url: "Evidencia",
  area: "Área", decision: "Decisión", why: "Por qué", purpose: "Para qué", context: "Contexto", author_name: "Autor", decided_at: "Decidida",
  period: "Periodo", target: "Meta", kpi_code: "KPI", result: "Resultado", learnings: "Aprendizajes", deferred_to: "Aplazado a", mission: "Misión",
  decisions: "Decide", limits: "Límites", occupant_name: "Ocupante", version: "Versión", created_at: "Creado", updated_at: "Actualizado",
  origin: "Origen", source_channel: "Canal de origen", opted_out: "Baja de comunicaciones", handle: "Identificador", qualified: "Cualificada",
  content_title: "Pieza de origen", source_content_title: "Pieza de origen", accepted_at: "Aceptada", won_at: "Ganada", days_overdue: "Días vencida",
  notes: "Notas", body: "Texto", manual: "Manual", conditions: "Condiciones", price_minor: "Precio", recurrence: "Recurrencia", code: "Código",
  paid_on: "Fecha de cobro/pago", method: "Método", document_path: "Justificante", iban_masked: "IBAN", opening_balance_minor: "Saldo inicial",
  last_balance_minor: "Último saldo del banco", opening_on: "Fecha saldo inicial", focus: "Foco", plan: "Plan", verdict: "Veredicto", review: "Balance",
  period_key: "Periodo", contacts: "Contactos", opportunities: "Oportunidades", billed_minor: "Facturado", conversations: "Conversaciones",
};

function display(key: string, v: unknown, row: BizRow): ReactNode {
  if (v === null || v === undefined || v === "") return <span className="text-muted-foreground">—</span>;
  if (key.endsWith("_minor")) return formatMinor(v as number, str(row.currency) || "EUR");
  if (key === "stage") return STAGE_LABELS[str(v)] ?? str(v);
  if (key === "status" && row.entity_type === undefined) {
    return INVOICE_STATUS_LABELS[str(v)] ?? MOVEMENT_STATUS_LABELS[str(v)] ?? PERIOD_STATUS_LABELS[str(v)] ?? CONTENT_STATUS_LABELS[str(v)] ?? APPROVAL_LABELS[str(v)] ?? str(v);
  }
  if (key === "nature") return NATURE_LABELS[str(v)] ?? str(v);
  if (key === "probability") return `${str(v)} %`;
  if (typeof v === "boolean") return v ? "Sí" : "No";
  if (key.endsWith("_at")) return formatDateTime(v);
  if (key.endsWith("_on") || key.endsWith("_date")) return formatDate(v);
  if (Array.isArray(v)) return v.join(", ");
  if (typeof v === "object") return <code className="text-micro">{JSON.stringify(v)}</code>;
  return str(v);
}

export function RecordSheet({ target, onClose }: { target: { entity: string; id: string } | null; onClose: () => void }) {
  return (
    <Sheet open={target !== null} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full overflow-y-auto data-[side=right]:sm:max-w-xl">
        {target ? <RecordBody entity={target.entity} id={target.id} /> : null}
      </SheetContent>
    </Sheet>
  );
}

function RecordBody({ entity, id }: { entity: string; id: string }) {
  const wsId = useWorkspaceId();
  const q = useQuery(bizRecordOptions(wsId, entity, id));
  if (q.isLoading) return <div className="p-4"><LoadingBlock rows={6} /></div>;
  if (q.error || !q.data) return <div className="p-4"><ErrorBlock error={q.error ?? "No encontrado"} retry={() => q.refetch()} /></div>;
  const row = q.data.record as BizRow;
  const rel = q.data.related;
  const title = str(row.title) || str(row.name) || str(row.number) || str(row.description) || ENTITY_LABELS[entity] || entity;
  const fields = Object.entries(row)
    .filter(([k, v]) => !HIDDEN.has(k) && !k.endsWith("_id") && k !== "id" && !(typeof v === "object" && v !== null && !Array.isArray(v)))
    .sort(([a], [b]) => fieldOrder(a, b));
  const file = (rel.file ?? [])[0];
  return (
    <div className="flex flex-col gap-4 p-4">
      <SheetHeader className="p-0">
        <SheetDescription>{ENTITY_LABELS[entity] ?? entity}</SheetDescription>
        <SheetTitle className="text-title">{title}</SheetTitle>
      </SheetHeader>

      <EntityActions entity={entity} row={row} />

      {entity === "opportunity" && row.proposal ? <ProposalSnapshot proposal={row.proposal as BizRow} /> : null}
      {entity === "invoice" ? <InvoiceLines row={row} /> : null}
      {entity === "period" ? <PeriodSummary row={row} /> : null}

      <dl className="grid grid-cols-[9rem_1fr] gap-x-3 gap-y-1.5 text-caption">
        {fields.map(([k, v]) => (
          <div key={k} className="contents">
            <dt className="text-muted-foreground">{FIELD_LABELS[k] ?? k}</dt>
            <dd className="min-w-0 whitespace-pre-wrap break-words">{display(k, v, row)}</dd>
          </div>
        ))}
      </dl>

      {file ? (
        <div className="flex items-center gap-2 rounded-md border px-2 py-1.5 text-caption">
          <FolderOpen className="size-3.5 text-muted-foreground" />
          <span className="truncate font-mono text-micro">{str(file.rel_path)}</span>
          <Pill className="ml-auto">{str(file.state) === "committed" ? "Escrito en la carpeta" : "Escritura pendiente"}</Pill>
        </div>
      ) : null}

      <Related rel={rel} />

      {(rel.documents ?? []).length > 0 ? (
        <Block title="Documentos">
          {(rel.documents ?? []).map((d) => (
            <div key={str(d.id)} className="flex items-center gap-2 text-caption">
              <FileText className="size-3.5 text-muted-foreground" />
              <span className="font-mono text-micro">{str(d.rel_path)}</span>
              <span className="ml-auto text-micro text-muted-foreground">sha256 {str(d.sha256).slice(0, 10)}</span>
            </div>
          ))}
        </Block>
      ) : null}

      {(rel.approvals ?? []).length > 0 ? (
        <Block title="Aprobaciones">
          {(rel.approvals ?? []).map((a) => (
            <div key={str(a.id)} className="flex items-center gap-2 text-caption">
              <span>{str(a.title)}</span>
              <Pill className="ml-auto">{APPROVAL_LABELS[str(a.status)] ?? str(a.status)}</Pill>
            </div>
          ))}
        </Block>
      ) : null}

      <Block title="Historial auditado">
        {(rel.audit ?? []).length === 0 ? <p className="text-caption text-muted-foreground">Sin cambios registrados.</p> : null}
        {(rel.audit ?? []).map((a) => (
          <div key={str(a.id)} className="flex items-start gap-2 text-caption">
            <span className="w-24 shrink-0 text-micro text-muted-foreground">{formatDateTime(a.at)}</span>
            <span className="min-w-0 flex-1">
              <span className="font-medium">{str(a.actor_name) || str(a.actor_type)}</span> · {str(a.action)}
              {str(a.result) !== "ok" ? <span className="text-muted-foreground"> ({str(a.result)})</span> : null}
            </span>
          </div>
        ))}
      </Block>

      {(rel.events ?? []).length > 0 ? (
        <Block title="Eventos">
          {(rel.events ?? []).map((e) => (
            <div key={str(e.id)} className="flex items-center gap-2 text-caption">
              <span className="font-mono text-micro">{str(e.type)}</span>
              <Pill className="ml-auto">{str(e.status)}{num(e.attempts) > 1 ? ` · ${num(e.attempts)} intentos` : ""}</Pill>
            </div>
          ))}
        </Block>
      ) : null}
    </div>
  );
}

function Block({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="space-y-1.5">
      <h3 className="text-label font-medium text-muted-foreground">{title}</h3>
      {children}
    </div>
  );
}

const RELATED_ENTITY: Record<string, string> = {
  contacts: "contact", opportunities: "opportunity", invoices: "invoice", payments: "payment", movements: "movement", conversations: "conversation", offers: "offer",
};

function Related({ rel }: { rel: Record<string, BizRow[] | null> }) {
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const keys = Object.keys(rel).filter((k) => !["audit", "events", "documents", "approvals", "file"].includes(k) && (rel[k] ?? []).length > 0);
  if (keys.length === 0) return null;
  const titles: Record<string, string> = { contacts: "Contactos", opportunities: "Oportunidades", invoices: "Facturas", payments: "Cobros y pagos", movements: "Movimientos", conversations: "Conversaciones", project: "Proyecto", projects: "Proyectos", offers: "Versiones de oferta" };
  return (
    <>
      {keys.map((k) => (
        <Block key={k} title={titles[k] ?? k}>
          {(rel[k] ?? []).map((r) => {
            const label = str(r.title) || str(r.name) || str(r.number) || (r.version ? `v${str(r.version)} · ${formatMinor(r.price_minor as number)}` : "") || str(r.summary).slice(0, 80) || str(r.description) || str(r.id);
            const extra = r.total_minor !== undefined ? formatMinor(r.total_minor as number) : r.value_minor !== undefined ? formatMinor(r.value_minor as number) : r.amount_minor !== undefined ? formatMinor(r.amount_minor as number) : "";
            return (
              <div key={str(r.id)} className="flex items-center gap-2 text-caption">
                {k === "project" || k === "projects" ? (
                  <button type="button" className="hover:underline" onClick={() => nav.push(p.projectDetail(str(r.id)))}>
                    {label}
                  </button>
                ) : (
                  <RecordLink entity={RELATED_ENTITY[k] ?? k} id={r.id}>{label}</RecordLink>
                )}
                <span className="ml-auto text-micro text-muted-foreground">
                  {str(r.stage) ? STAGE_LABELS[str(r.stage)] ?? str(r.stage) : ""}
                  {str(r.status) ? ` ${INVOICE_STATUS_LABELS[str(r.status)] ?? MOVEMENT_STATUS_LABELS[str(r.status)] ?? str(r.status)}` : ""} {extra}
                </span>
              </div>
            );
          })}
        </Block>
      ))}
    </>
  );
}

function ProposalSnapshot({ proposal }: { proposal: BizRow }) {
  return (
    <div className="rounded-md border bg-muted/30 p-3 text-caption">
      <div className="mb-1 font-medium">Propuesta · instantánea de la oferta v{str(proposal.offer_version)}</div>
      <div className="grid grid-cols-2 gap-1">
        <span className="text-muted-foreground">Servicio</span><span>{str(proposal.service)}</span>
        <span className="text-muted-foreground">Precio unitario</span><span>{formatMinor(proposal.unit_price_minor as number)} × {str(proposal.quantity)} {str(proposal.billing_unit)}</span>
        <span className="text-muted-foreground">Base</span><span>{formatMinor(proposal.base_minor as number)}</span>
        <span className="text-muted-foreground">IVA</span><span>{formatMinor(proposal.tax_minor as number)}</span>
        <span className="text-muted-foreground">Total</span><span className="font-medium">{formatMinor(proposal.total_minor as number)}</span>
        <span className="text-muted-foreground">Válida hasta</span><span>{formatDate(proposal.valid_until)}</span>
      </div>
      {str(proposal.conditions) ? <p className="mt-1 text-muted-foreground">{str(proposal.conditions)}</p> : null}
      <p className="mt-1 text-micro text-muted-foreground">Cambiar el precio vigente no altera esta propuesta ni su factura.</p>
    </div>
  );
}

function InvoiceLines({ row }: { row: BizRow }) {
  const lines = (row.lines as BizRow[] | undefined) ?? [];
  if (lines.length === 0) return null;
  return (
    <div className="rounded-md border p-3 text-caption">
      {lines.map((l, i) => (
        <div key={i} className="flex justify-between gap-2">
          <span>{str(l.concept)}{l.offer_version ? <span className="text-muted-foreground"> · oferta v{str(l.offer_version)}</span> : null}</span>
          <span className="tabular-nums">{formatMinor(l.base_minor as number)}</span>
        </div>
      ))}
    </div>
  );
}

function PeriodSummary({ row }: { row: BizRow }) {
  const s = (row.summary as BizRow) ?? {};
  const exc = (s.exceptions as BizRow[] | undefined) ?? [];
  const history = (row.history as BizRow[] | undefined) ?? [];
  return (
    <div className="space-y-2 rounded-md border p-3 text-caption">
      {str(s.note) ? <p className="text-muted-foreground">{str(s.note)}</p> : null}
      {exc.length > 0 ? (
        <ul className="list-disc pl-4">
          {exc.map((e, i) => (
            <li key={i}>{str(e.message)}: {str(e.count)}</li>
          ))}
        </ul>
      ) : s.ready ? <p>Sin excepciones.</p> : null}
      {history.length > 0 ? (
        <div>
          <div className="font-medium">Historial de estados</div>
          {history.map((h, i) => (
            <div key={i} className="text-muted-foreground">
              {formatDateTime(h.at)} · {PERIOD_STATUS_LABELS[str(h.from)] ?? str(h.from)} → {PERIOD_STATUS_LABELS[str(h.to)] ?? str(h.to)} {str(h.evidence) ? `· ${str(h.evidence)}` : ""} {str(h.reason) ? `· ${str(h.reason)}` : ""}
            </div>
          ))}
        </div>
      ) : null}
    </div>
  );
}

// --- Entity actions -----------------------------------------------------------

function EntityActions({ entity, row }: { entity: string; row: BizRow }) {
  const { exec, pending } = useAction();
  const [text, setText] = useState("");
  const [text2, setText2] = useState("");
  const id = str(row.id);
  const field = (placeholder: string, value: string, set: (v: string) => void, area = false) =>
    area ? <Textarea value={value} onChange={(e) => set(e.target.value)} placeholder={placeholder} className="min-h-16 text-caption" /> : <Input value={value} onChange={(e) => set(e.target.value)} placeholder={placeholder} className="h-8 text-caption" />;

  switch (entity) {
    case "opportunity": {
      const stage = str(row.stage);
      const open = !["ganada", "perdida"].includes(stage);
      if (!open) return null;
      return (
        <div className="space-y-2 rounded-md border p-3">
          <div className="flex flex-wrap gap-1.5">
            {stage === "entrada" ? <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("opportunity.move", { id, stage: "cualificacion" }, "Pasa a cualificación")}>Cualificar</Button> : null}
            {stage === "cualificacion" ? <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("opportunity.move", { id, stage: "diagnostico" }, "Pasa a diagnóstico")}>Diagnóstico hecho</Button> : null}
            {["entrada", "cualificacion", "diagnostico", "negociacion"].includes(stage) ? <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("opportunity.proposal", { id }, "Propuesta generada desde la oferta vigente")}>Generar propuesta</Button> : null}
            {stage === "propuesta" ? <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("opportunity.move", { id, stage: "negociacion" }, "En negociación")}>Negociación</Button> : null}
            {stage !== "pausada" && stage !== "aceptada" ? <Button size="xs" variant="ghost" disabled={pending} onClick={() => exec("opportunity.move", { id, stage: "pausada" }, "Pausada")}>Pausar</Button> : null}
          </div>
          {field("Resumen del contacto o evidencia de aceptación / motivo de pérdida", text, setText, true)}
          <div className="flex flex-wrap gap-1.5">
            <Button size="xs" disabled={!text.trim() || pending} onClick={() => exec("contact.touch", { opportunity_id: id, summary: text }, "Contacto registrado").then(() => setText(""))}>Registrar contacto</Button>
            {["propuesta", "negociacion"].includes(stage) ? <Button size="xs" variant="outline" disabled={!text.trim() || pending} onClick={() => exec("opportunity.accept", { id, evidence: text }, "Aceptación registrada: factura en borrador")}>Registrar aceptación</Button> : null}
            <Button size="xs" variant="ghost" disabled={!text.trim() || pending} onClick={() => exec("opportunity.move", { id, stage: "perdida", lost_reason: text }, "Marcada como perdida")}>Marcar perdida</Button>
          </div>
          <p className="text-micro text-muted-foreground">Ganada solo se alcanza al confirmarse el cobro; entonces nace el proyecto.</p>
        </div>
      );
    }
    case "invoice": {
      const status = str(row.status);
      return (
        <div className="space-y-2 rounded-md border p-3">
          {status === "draft" && str(row.direction) === "issued" ? (
            <Button size="xs" disabled={pending} onClick={() => exec("invoice.issue", { id }, "Factura emitida y numerada")}>Emitir factura</Button>
          ) : null}
          {["issued", "partially_paid"].includes(status) ? (
            <>
              {field("Evidencia del cobro/pago (justificante, referencia bancaria)", text, setText)}
              <Button size="xs" variant="outline" disabled={!text.trim() || pending}
                onClick={() => exec("payment.confirm", { invoice_id: id, amount_minor: num(row.total_minor) - num(row.paid_minor), evidence: text, method: "transferencia" }, "Cobro confirmado")}>
                Confirmar {str(row.direction) === "issued" ? "cobro" : "pago"} pendiente ({formatMinor(num(row.total_minor) - num(row.paid_minor))})
              </Button>
              <p className="text-micro text-muted-foreground">Mejor desde Bancos: confirmar contra un movimiento deja trazabilidad completa.</p>
            </>
          ) : null}
          {status !== "draft" ? <p className="text-micro text-muted-foreground">Una factura emitida no se edita: se rectifica.</p> : null}
        </div>
      );
    }
    case "movement": {
      const status = str(row.status);
      if (status === "reconciled") return null;
      return (
        <div className="flex flex-wrap gap-1.5 rounded-md border p-3">
          {status === "proposed" ? (
            <>
              <Button size="xs" disabled={pending} onClick={() => exec("payment.confirm", { invoice_id: str(row.invoice_id), movement_id: id }, "Conciliado y cobro/pago confirmado")}>Confirmar conciliación</Button>
              <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("movement.match", { id, reject: true }, "Propuesta descartada")}>Descartar propuesta</Button>
            </>
          ) : null}
          {status !== "ignored" ? <Button size="xs" variant="ghost" disabled={pending} onClick={() => exec("movement.classify", { id, ignore: true, notes: "Sin factura por naturaleza" }, "Marcado sin factura")}>Sin factura (justificar)</Button> : null}
        </div>
      );
    }
    case "period": {
      const next = PERIOD_NEXT[str(row.status)];
      return (
        <div className="space-y-2 rounded-md border p-3">
          {str(row.status) === "open" || str(row.status) === "prepared" ? (
            <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("period.prepare", { year: row.year, quarter: row.quarter }, "Paquete regenerado")}>Preparar / regenerar paquete</Button>
          ) : null}
          {next && next !== "prepared" ? (
            <>
              {field(next === "approved" ? "Comentario (opcional)" : "Evidencia obligatoria: justificante, nº de registro…", text, setText)}
              <Button size="xs" disabled={pending || (next !== "approved" && !text.trim())} onClick={() => exec("period.transition", { id, to: next, evidence: text }, `Periodo: ${PERIOD_STATUS_LABELS[next]}`).then(() => setText(""))}>
                Pasar a «{PERIOD_STATUS_LABELS[next]}»
              </Button>
            </>
          ) : null}
          {str(row.status) !== "open" ? (
            <div className="flex gap-1.5">
              {field("Motivo para reabrir", text2, setText2)}
              <Button size="xs" variant="ghost" disabled={!text2.trim() || pending} onClick={() => exec("period.transition", { id, to: "open", reason: text2 }, "Periodo reabierto con motivo")}>Reabrir</Button>
            </div>
          ) : null}
        </div>
      );
    }
    case "content": {
      const status = str(row.status);
      const nexts: Record<string, string[]> = { idea: ["borrador"], borrador: ["revision"], revision: ["aprobado", "borrador"], aprobado: ["programado", "publicado"], programado: ["publicado", "fallido"], fallido: ["programado"] };
      const opts = nexts[status] ?? [];
      if (opts.length === 0) return null;
      return (
        <div className="space-y-2 rounded-md border p-3">
          {opts.includes("publicado") || opts.includes("programado") || opts.includes("fallido") ? field("Fecha (AAAA-MM-DD) para programar, enlace de evidencia para publicar o motivo de fallo", text, setText) : null}
          <div className="flex flex-wrap gap-1.5">
            {opts.map((o) => (
              <Button key={o} size="xs" variant="outline" disabled={pending || ((o === "publicado" || o === "programado" || o === "fallido") && !text.trim())}
                onClick={() => exec("content.move", { id, status: o, evidence_url: o === "publicado" ? text : undefined, scheduled_at: o === "programado" ? text : undefined, failure_reason: o === "fallido" ? text : undefined }, `Contenido: ${CONTENT_STATUS_LABELS[o]}`)}>
                {CONTENT_STATUS_LABELS[o]}
              </Button>
            ))}
          </div>
        </div>
      );
    }
    case "conversation": {
      if (row.qualified) return null;
      return (
        <div className="space-y-2 rounded-md border p-3">
          {field("Nombre del interesado", text, setText)}
          {field("Email (opcional)", text2, setText2)}
          <div className="flex gap-1.5">
            <Button size="xs" disabled={!text.trim() || pending} onClick={() => exec("conversation.qualify", { id, name: text, email: text2, service_code: "RENTA" }, "Pasa a Ventas como interesado")}>Cualificar → Renta</Button>
            <Button size="xs" variant="outline" disabled={!text.trim() || pending} onClick={() => exec("conversation.qualify", { id, name: text, email: text2, service_code: "TRIM" }, "Pasa a Ventas como interesado")}>Cualificar → Trimestrales</Button>
          </div>
        </div>
      );
    }
    case "decision": {
      const status = str(row.status);
      if (status === "superseded") return <p className="text-caption text-muted-foreground">Sustituida por una decisión posterior.</p>;
      return (
        <div className="space-y-2 rounded-md border p-3">
          {field(status === "open" ? "Decisión" : "Nueva decisión (corrige sin borrar la anterior)", text, setText, true)}
          {field("Por qué · Para qué (separados por «·»)", text2, setText2)}
          <Button size="xs" disabled={pending || !text.trim() || !text2.includes("·")}
            onClick={() => {
              const [why, purpose] = text2.split("·").map((x) => x.trim());
              exec(status === "open" ? "decision.decide" : "decision.supersede", { id, decision: text, why, purpose }, status === "open" ? "Decisión registrada" : "Decisión corregida").then(() => { setText(""); setText2(""); });
            }}>
            {status === "open" ? "Decidir" : "Corregir decisión"}
          </Button>
        </div>
      );
    }
    case "objective": {
      return (
        <div className="space-y-2 rounded-md border p-3">
          {field("Resultado / aprendizajes / destino si se aplaza", text, setText)}
          <div className="flex flex-wrap gap-1.5">
            <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("objective.save", { id, status: "achieved", result: text }, "Objetivo conseguido")}>Conseguido</Button>
            <Button size="xs" variant="outline" disabled={pending} onClick={() => exec("objective.save", { id, status: "missed", learnings: text }, "Objetivo no conseguido")}>No conseguido</Button>
            <Button size="xs" variant="ghost" disabled={pending || !text.trim()} onClick={() => exec("objective.save", { id, status: "deferred", deferred_to: text }, "Objetivo aplazado")}>Aplazar a…</Button>
          </div>
        </div>
      );
    }
    default:
      return null;
  }
}
