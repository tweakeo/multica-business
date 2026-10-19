/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useMemo, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Bot, Search } from "lucide-react";
import { toast } from "sonner";
import { api } from "@multica/core/api";
import { bizSearchOptions, ENTITY_LABELS, type BizRow } from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { issueKeys } from "@multica/core/issues/queries";
import { useWorkspacePaths } from "@multica/core/paths";
import { Button } from "@multica/ui/components/ui/button";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@multica/ui/components/ui/dialog";
import { Input } from "@multica/ui/components/ui/input";
import { Textarea } from "@multica/ui/components/ui/textarea";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@multica/ui/components/ui/table";
import { cn } from "@multica/ui/lib/utils";
import { useNavigation } from "../navigation";
import { areaOf, EmptyHint, LoadingBlock, ErrorBlock, str, useAction, useInspector } from "./shared";

export interface Column {
  key: string;
  label: string;
  render?: (row: BizRow) => ReactNode;
  className?: string;
  align?: "right";
}

export function BizTable({ rows, columns, entity, empty, onRowClick, isLoading, error }: {
  rows: BizRow[] | undefined;
  columns: Column[];
  entity?: string;
  empty?: { title: string; next?: ReactNode };
  onRowClick?: (row: BizRow) => void;
  isLoading?: boolean;
  error?: unknown;
}) {
  const open = useInspector();
  if (isLoading) return <LoadingBlock />;
  if (error) return <ErrorBlock error={error} />;
  if (!rows || rows.length === 0) return <EmptyHint title={empty?.title ?? "Sin registros"} next={empty?.next} />;
  const click = onRowClick ?? (entity ? (r: BizRow) => open({ entity, id: str(r.id) }) : undefined);
  return (
    <div className="overflow-x-auto rounded-lg border">
      <Table>
        <TableHeader>
          <TableRow>
            {columns.map((c) => (
              <TableHead key={c.key} className={cn("h-8 text-caption", c.align === "right" && "text-right", c.className)}>
                {c.label}
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {rows.map((r, i) => (
            <TableRow
              key={str(r.id) || i}
              className={cn(click && "cursor-pointer")}
              tabIndex={click ? 0 : undefined}
              onClick={click ? () => click(r) : undefined}
              onKeyDown={click ? (e) => e.key === "Enter" && click(r) : undefined}
            >
              {columns.map((c) => (
                <TableCell key={c.key} className={cn("py-1.5 text-caption", c.align === "right" && "text-right tabular-nums", c.className)}>
                  {c.render ? c.render(r) : str(r[c.key]) || "—"}
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

/**
 * "Pedir al agente": a natural-language request becomes a Multica task
 * assigned to the area agent. The agent works through the same API, so its
 * sensitive actions still end in the approval queue.
 */
export function AskAgentDialog({ area, open, onOpenChange, initial }: { area: string; open: boolean; onOpenChange: (o: boolean) => void; initial?: string }) {
  const wsId = useWorkspaceId();
  const qc = useQueryClient();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const team = useQuery({ queryKey: ["biz", wsId, "area-agent", area], queryFn: () => api.bizGet(`/areas/${area}`), enabled: open });
  const agent = ((team.data as { agents?: BizRow[] } | undefined)?.agents ?? []).find((a) => str(a.area) === area) ??
    ((team.data as { agents?: BizRow[] } | undefined)?.agents ?? [])[0];
  const [text, setText] = useState(initial ?? "");
  const create = useMutation({
    mutationFn: () =>
      api.createIssue({
        title: text.split("\n")[0]!.slice(0, 120),
        description: `${text}\n\n_Petición desde Empresa · ${areaOf(area).name}_`,
        status: "todo",
        priority: "medium",
        assignee_type: "agent",
        assignee_id: str(agent?.agent_id),
      } as Parameters<typeof api.createIssue>[0]),
    onSuccess: (issue) => {
      qc.invalidateQueries({ queryKey: issueKeys.all(wsId) });
      toast.success("Petición enviada al agente", { description: "Sigue su trabajo en la tarea; las acciones sensibles llegarán a Aprobaciones." });
      onOpenChange(false);
      setText("");
      const id = (issue as { id?: string }).id;
      if (id) nav.push(p.issueDetail(id));
    },
    onError: (err) => toast.error(err instanceof Error ? err.message : String(err)),
  });
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Bot className={cn("size-4", areaOf(area).text)} /> Pedir al agente de {areaOf(area).name}
          </DialogTitle>
          <DialogDescription>
            {agent ? `${str(agent.name)} recibirá una tarea con tu petición.` : "Esta área no tiene agente asignado."} Lo que requiera aprobación quedará pendiente para una persona.
          </DialogDescription>
        </DialogHeader>
        <Textarea value={text} onChange={(e) => setText(e.target.value)} className="min-h-32" placeholder="Describe el resultado que quieres, por ejemplo: «Prepara el seguimiento de las propuestas abiertas de esta semana»" autoFocus />
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button disabled={!agent || !text.trim() || create.isPending} onClick={() => create.mutate()}>Enviar al agente</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** VEN-01/VEN-02: one form creates organization + contact + opportunity. */
export function NewLeadDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }) {
  const { exec, pending } = useAction();
  const [f, setF] = useState({ name: "", email: "", phone: "", company: "", service_code: "RENTA", channel: "web", notes: "" });
  const set = (k: keyof typeof f) => (e: { target: { value: string } }) => setF((x) => ({ ...x, [k]: e.target.value }));
  const submit = async () => {
    await exec("lead.create", {
      contact: { name: f.name, email: f.email, phone: f.phone },
      organization: f.company ? { name: f.company } : undefined,
      service_code: f.service_code,
      channel: f.channel,
      notes: f.notes,
    }, "Alta comercial creada: contacto + oportunidad");
    onOpenChange(false);
    setF({ name: "", email: "", phone: "", company: "", service_code: "RENTA", channel: "web", notes: "" });
  };
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Nuevo interesado</DialogTitle>
          <DialogDescription>Crea en un paso el contacto, su empresa (si la hay) y la oportunidad. Si el email ya existe, se reutiliza el contacto.</DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-2">
          <Input placeholder="Nombre *" value={f.name} onChange={set("name")} className="col-span-2" />
          <Input placeholder="Email" value={f.email} onChange={set("email")} />
          <Input placeholder="Teléfono" value={f.phone} onChange={set("phone")} />
          <Input placeholder="Empresa (opcional)" value={f.company} onChange={set("company")} className="col-span-2" />
          <label className="text-caption text-muted-foreground">
            Servicio
            <select className="mt-1 h-8 w-full rounded-md border bg-transparent px-2 text-body" value={f.service_code} onChange={set("service_code")}>
              <option value="RENTA">Renta</option>
              <option value="TRIM">Trimestrales</option>
            </select>
          </label>
          <label className="text-caption text-muted-foreground">
            Canal de entrada *
            <select className="mt-1 h-8 w-full rounded-md border bg-transparent px-2 text-body" value={f.channel} onChange={set("channel")}>
              {["web", "referido", "llamada", "instagram", "linkedin", "feria", "email"].map((c) => <option key={c} value={c}>{c}</option>)}
            </select>
          </label>
          <Textarea placeholder="Qué necesita (palabras del interesado)" value={f.notes} onChange={set("notes")} className="col-span-2 min-h-20" />
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)}>Cancelar</Button>
          <Button disabled={!f.name.trim() || pending} onClick={submit}>Crear</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Global search across business records and projects. */
export function BizSearch() {
  const wsId = useWorkspaceId();
  const open = useInspector();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const [q, setQ] = useState("");
  const res = useQuery(bizSearchOptions(wsId, q));
  const rows = useMemo(() => res.data ?? [], [res.data]);
  return (
    <div className="relative w-full max-w-xs">
      <Search className="pointer-events-none absolute top-1/2 left-2 size-3.5 -translate-y-1/2 text-muted-foreground" />
      <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar en la empresa…" className="h-8 pl-7 text-caption" aria-label="Buscar en la empresa" />
      {q.trim().length >= 2 ? (
        <div className="absolute top-9 right-0 left-0 z-20 max-h-80 overflow-auto rounded-md border bg-popover p-1 shadow-md">
          {rows.length === 0 ? <p className="px-2 py-1.5 text-caption text-muted-foreground">{res.isLoading ? "Buscando…" : "Sin resultados"}</p> : null}
          {rows.map((r) => (
            <button
              key={`${str(r.type)}-${str(r.id)}`}
              type="button"
              className="flex w-full items-center gap-2 rounded px-2 py-1.5 text-left text-caption hover:bg-accent"
              onClick={() => {
                setQ("");
                if (str(r.type) === "project") nav.push(p.projectDetail(str(r.id)));
                else open({ entity: str(r.type), id: str(r.id) });
              }}
            >
              <span className="w-20 shrink-0 text-micro text-muted-foreground">{ENTITY_LABELS[str(r.type)] ?? str(r.type)}</span>
              <span className="truncate">{str(r.title)}</span>
              <span className="ml-auto shrink-0 text-micro text-muted-foreground">{str(r.subtitle)}</span>
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
