/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronRight, ExternalLink, FolderOpen, Lock } from "lucide-react";
import { bizApi, bizDocumentsOptions, bizSystemsOptions, formatDate, type BizLibraryDoc, type BizSystemNote } from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { Button } from "@multica/ui/components/ui/button";
import { Input } from "@multica/ui/components/ui/input";
import { Markdown } from "@multica/ui/markdown";
import { cn } from "@multica/ui/lib/utils";
import { toast } from "sonner";
import { EmptyHint, ErrorBlock, LoadingBlock, Pill, Section } from "./shared";

// The library is what the company folder holds for people to read: the
// systems of each area and the documents of Finanzas. It is read as it is
// and links to the original; nothing here becomes a record.

/** Opens the original from the folder in a new tab (the request carries the session). */
export async function openOriginal(path: string) {
  const win = window.open("", "_blank");
  try {
    const blob = await bizApi.file(path);
    const url = URL.createObjectURL(blob);
    if (win) win.location.href = url;
    else window.location.assign(url);
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  } catch (e) {
    win?.close();
    toast.error(e instanceof Error ? e.message : "No se pudo abrir el original");
  }
}

async function revealInFinder(path: string) {
  try {
    await bizApi.reveal(path);
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "No se pudo abrir Finder");
  }
}

function OriginalActions({ path, folder }: { path: string; folder?: boolean }) {
  return (
    <span className="inline-flex shrink-0 items-center gap-1">
      {folder ? (
        <Button size="xs" variant="ghost" className="invisible" aria-hidden tabIndex={-1}>Abrir <ExternalLink /></Button>
      ) : (
        <Button size="xs" variant="ghost" onClick={(e) => { e.stopPropagation(); void openOriginal(path); }} title="Abrir el original">
          Abrir <ExternalLink />
        </Button>
      )}
      <Button size="xs" variant="ghost" onClick={(e) => { e.stopPropagation(); void revealInFinder(path); }} title="Mostrar en Finder">
        <FolderOpen />
      </Button>
    </span>
  );
}

// --- Systems -----------------------------------------------------------------

function SystemCard({ doc, nested }: { doc: BizSystemNote & { children?: BizSystemNote[] | null }; nested?: boolean }) {
  const [open, setOpen] = useState(false);
  const sections = doc.sections ?? [];
  const children = doc.children ?? [];
  return (
    <div className={cn("rounded-lg border", nested && "bg-muted/30")}>
      <div
        role="button"
        tabIndex={0}
        aria-expanded={open}
        className="flex w-full cursor-pointer items-center gap-2 p-3 text-left"
        onClick={() => setOpen((o) => !o)}
        onKeyDown={(e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); setOpen((o) => !o); } }}
      >
        <ChevronRight className={cn("size-4 shrink-0 text-muted-foreground transition-transform", open && "rotate-90")} />
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-body font-medium">{doc.title}</span>
            {doc.status ? <Pill>{doc.status}</Pill> : null}
            {children.length ? <span className="text-micro text-muted-foreground">{children.length} procedimientos</span> : null}
          </div>
          {doc.owner || doc.modified_at ? (
            <div className="text-micro text-muted-foreground">
              {doc.owner}
              {doc.owner && doc.modified_at ? " · " : ""}
              {doc.modified_at ? `actualizado ${formatDate(doc.modified_at)}` : ""}
            </div>
          ) : null}
        </div>
        <OriginalActions path={doc.path} />
      </div>
      {open ? (
        <div className="space-y-3 border-t px-3 py-3 pl-9">
          {doc.intro ? <Markdown mode="minimal" className="text-caption">{doc.intro}</Markdown> : null}
          {sections.map((s) => (
            <div key={s.heading}>
              <div className="text-caption font-medium">{s.heading}</div>
              {s.body ? <Markdown mode="minimal" className="text-caption text-muted-foreground">{s.body}</Markdown> : <p className="text-caption text-muted-foreground">—</p>}
            </div>
          ))}
          {sections.length === 0 && !doc.intro ? <p className="text-caption text-muted-foreground">Nota sin secciones.</p> : null}
          {children.length ? (
            <div className="space-y-2">
              <div className="text-caption font-medium">Procedimientos</div>
              {children.map((c) => <SystemCard key={c.path} doc={c} nested />)}
            </div>
          ) : null}
          <p className="text-micro text-muted-foreground">
            <code>{doc.path}</code> · solo lectura: se edita en la carpeta.
          </p>
        </div>
      ) : null}
    </div>
  );
}

/** The area's systems as the folder has them: N · Área/Sistemas/*.md. */
export function FolderSystems({ area }: { area: string }) {
  const wsId = useWorkspaceId();
  const q = useQuery(bizSystemsOptions(wsId, area));
  if (q.isLoading) return <LoadingBlock rows={4} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  const { systems, folder, configured } = q.data;
  return (
    <Section title={`Sistemas del área (${systems.length})`} actions={folder ? <span className="text-micro text-muted-foreground">{folder}</span> : null}>
      {!configured ? (
        <EmptyHint title="La empresa no tiene carpeta configurada" next="Los sistemas se leen de la carpeta de la empresa." />
      ) : systems.length === 0 ? (
        <EmptyHint title="Sin sistemas escritos" next={`Escribe cada sistema como una nota en ${folder || "Sistemas/"}.`} />
      ) : (
        <div className="space-y-2">{systems.map((s) => <SystemCard key={s.path} doc={s} />)}</div>
      )}
    </Section>
  );
}

// --- Autónomo: documents of Finanzas -------------------------------------------

const GROUP_HINT: Record<string, string> = {
  Fiscal: "Facturas, modelos y revisiones por año y trimestre",
  Gestoría: "Lo que se envía y recibe de la gestoría",
  Trámites: "Alta, Seguridad Social, baja y otros trámites",
  Registros: "Registros únicos (CSV) e importaciones",
};

function formatSize(n: number): string {
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${Math.round(n / 1024)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
}

function docDate(d: BizLibraryDoc): string {
  if (/^\d{4}-\d{2}$/.test(d.date)) {
    const [y, m] = d.date.split("-");
    return `${m}/${y}`;
  }
  return formatDate(d.date);
}

const PACKAGES = new Set(["numbers", "pages", "key", "rtfd", "bundle", "app"]);

const DATE_SOURCE: Record<string, string> = {
  nombre: "Fecha del nombre",
  documento: "Fecha leída del documento",
  metadatos: "Fecha de creación del PDF o documento (el texto no la trae)",
  manual: "Fecha anotada a mano en el índice de fechas",
  archivo: "Fecha del archivo: ni el nombre ni el documento la indican",
};

function DocRow({ d }: { d: BizLibraryDoc }) {
  const quarter = d.quarter_from_date ? `${d.quarter} (por fecha; está en Sin trimestre)` : (d.quarter ?? "");
  const where = [d.year ? String(d.year) : "", quarter, d.detail].filter(Boolean).join(" · ");
  const dateTitle = [DATE_SOURCE[d.date_source] ?? "", d.date_note].filter(Boolean).join(" · ");
  return (
    <div className="flex items-center gap-3 px-3 py-2 text-caption hover:bg-muted/40">
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <button type="button" className="truncate text-left font-medium hover:underline" title={d.path} onClick={() => (PACKAGES.has(d.ext) ? revealInFinder(d.path) : openOriginal(d.path))}>
            {d.name}
          </button>
          {d.private ? (
            <Pill className="shrink-0"><Lock className="mr-1 inline size-3" />Privado</Pill>
          ) : null}
          {d.in_cloud ? <Pill className="shrink-0">En iCloud</Pill> : null}
        </div>
        {where ? <div className="truncate text-micro text-muted-foreground">{where}</div> : null}
      </div>
      <span className="w-12 shrink-0 text-micro uppercase text-muted-foreground">{d.ext || "—"}</span>
      <span className="w-24 shrink-0 text-right tabular-nums" title={dateTitle}>
        {docDate(d)}
        {d.date_source === "archivo" ? <span className="text-muted-foreground">*</span> : null}
      </span>
      <span className="w-16 shrink-0 text-right tabular-nums text-muted-foreground">{formatSize(d.size)}</span>
      <OriginalActions path={d.path} folder={PACKAGES.has(d.ext)} />
    </div>
  );
}

/** Finanzas · Autónomo: Fiscal/, Gestoría/, Trámites/ and Registros/ as documents. */
export function AutonomoDocuments() {
  const wsId = useWorkspaceId();
  const q = useQuery(bizDocumentsOptions(wsId));
  const [group, setGroup] = useState("");
  const [year, setYear] = useState("");
  const [text, setText] = useState("");
  const docs = q.data?.documents ?? [];
  const years = useMemo(() => [...new Set(docs.map((d) => d.date.slice(0, 4)).filter(Boolean))].sort().reverse(), [docs]);
  const shown = useMemo(() => {
    const t = text.trim().toLowerCase();
    return docs.filter((d) => (!group || d.group === group) && (!year || d.date.startsWith(year)) && (!t || d.path.toLowerCase().includes(t)));
  }, [docs, group, year, text]);
  // Group → kind, each kind newest first (the server sorts by date).
  const tree = useMemo(() => {
    const out = new Map<string, Map<string, BizLibraryDoc[]>>();
    for (const g of q.data?.groups ?? []) out.set(g, new Map());
    for (const d of shown) {
      const kinds = out.get(d.group) ?? new Map<string, BizLibraryDoc[]>();
      out.set(d.group, kinds);
      kinds.set(d.kind, [...(kinds.get(d.kind) ?? []), d]);
    }
    return out;
  }, [shown, q.data?.groups]);
  if (q.isLoading) return <LoadingBlock rows={6} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  if (!q.data.configured) return <EmptyHint title="La empresa no tiene carpeta configurada" next="Los documentos se leen de la carpeta de la empresa." />;
  const count = (g: string) => docs.filter((d) => d.group === g).length;
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-1.5">
        <Button size="xs" variant={group === "" ? "secondary" : "ghost"} onClick={() => setGroup("")}>Todos ({docs.length})</Button>
        {q.data.groups.map((g) => (
          <Button key={g} size="xs" variant={group === g ? "secondary" : "ghost"} onClick={() => setGroup(g)}>{g} ({count(g)})</Button>
        ))}
        <select className="ml-auto h-7 rounded-md border bg-transparent px-2 text-caption" value={year} onChange={(e) => setYear(e.target.value)} aria-label="Año">
          <option value="">Todos los años</option>
          {years.map((y) => <option key={y} value={y}>{y}</option>)}
        </select>
        <Input className="h-7 w-56 text-caption" placeholder="Buscar por nombre o carpeta" value={text} onChange={(e) => setText(e.target.value)} />
      </div>
      {[...tree.entries()].filter(([, kinds]) => kinds.size > 0).map(([g, kinds]) => (
        <Section key={g} title={`${g} (${[...kinds.values()].reduce((a, x) => a + x.length, 0)})`} actions={<span className="text-micro text-muted-foreground">{GROUP_HINT[g] ?? ""}</span>}>
          <div className="space-y-3">
            {[...kinds.entries()].map(([kind, items]) => (
              <div key={kind} className="rounded-lg border">
                <div className="flex items-center gap-2 border-b px-3 py-1.5 text-caption font-medium">
                  {kind}
                  <span className="font-normal text-muted-foreground">{items.length}</span>
                </div>
                <div className="divide-y">{items.map((d) => <DocRow key={d.path} d={d} />)}</div>
              </div>
            ))}
          </div>
        </Section>
      ))}
      {shown.length === 0 ? <EmptyHint title="Ningún documento con estos filtros" /> : null}
      <p className="text-micro text-muted-foreground">
        Se leen tal cual de <code>{q.data.folder}</code>: nada se copia ni se convierte en ficha. «Abrir» muestra el original; el icono de carpeta lo enseña en Finder. Si el nombre no trae fecha, se usa la leída del documento (índice <code>{q.data.dates_index}</code>, editable a mano); * fecha del archivo, cuando tampoco el documento la indica. Los documentos privados no se ofrecen a los agentes.
      </p>
    </div>
  );
}
