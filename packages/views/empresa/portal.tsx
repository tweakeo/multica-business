/* eslint-disable i18next/no-literal-string -- TLS "Empresa" module ships Spanish copy only; see docs/tls/DECISIONES.md */
"use client";

import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, Circle, ExternalLink, Eye, FileText, FolderOpen, Lock } from "lucide-react";
import {
  bizApi,
  bizKeys,
  bizPortalOptions,
  bizPortalsOptions,
  formatDate,
  type BizIncidentInput,
  type BizPortalDoc,
  type BizPortalProject,
  type BizPortalSession,
} from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { Button } from "@multica/ui/components/ui/button";
import { Input } from "@multica/ui/components/ui/input";
import { Markdown } from "@multica/ui/markdown";
import { cn } from "@multica/ui/lib/utils";
import { toast } from "sonner";
import { useNavigation } from "../navigation";
import { openOriginal, revealInFinder } from "./library";
import { EmptyHint, ErrorBlock, LoadingBlock, Pill, Section } from "./shared";

// Portal Cliente (3 · Entrega/Sistemas/Portal Cliente.md): per project, the
// S1–S9 journey, each session's kit, the client's tasks, incidents (PT1) and
// progress. Everything is read from the project's folder. The client view is
// the same page without the internal fields; it is not published anywhere.

const STATE_LABEL: Record<string, { internal: string; client: string }> = {
  pendiente: { internal: "Pendiente", client: "Pendiente" },
  programada: { internal: "Programada", client: "Programada" },
  preparada: { internal: "Kit listo", client: "Preparada" },
  hecha: { internal: "Hecha", client: "Hecha" },
  no_incluida: { internal: "No incluida", client: "No incluida" },
};

const STATE_TONE: Record<string, string> = {
  hecha: "border-emerald-500/40 bg-emerald-500/10",
  preparada: "border-sky-500/40 bg-sky-500/10",
  programada: "border-amber-500/40 bg-amber-500/5",
  no_incluida: "border-dashed opacity-50",
  pendiente: "",
};

function setParams(nav: ReturnType<typeof useNavigation>, patch: Record<string, string | null>) {
  const sp = new URLSearchParams(nav.searchParams);
  for (const [k, v] of Object.entries(patch)) {
    if (v) sp.set(k, v);
    else sp.delete(k);
  }
  const q = sp.toString();
  nav.replace(`${nav.pathname}${q ? `?${q}` : ""}`);
}

/** Entrega · Portal Cliente: list of expedientes and the selected portal. */
export function ClientPortal() {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const list = useQuery(bizPortalsOptions(wsId));
  const projects = list.data?.projects ?? [];
  const slug = nav.searchParams.get("proyecto") ?? projects[0]?.slug ?? "";
  const client = nav.searchParams.get("vista") === "cliente";
  if (list.isLoading) return <LoadingBlock rows={6} />;
  if (list.error || !list.data) return <ErrorBlock error={list.error} retry={() => list.refetch()} />;
  if (!list.data.configured) return <EmptyHint title="La empresa no tiene carpeta configurada" next="El portal se lee de 3 · Entrega/Proyectos/ y Portal Cliente/." />;
  if (projects.length === 0) return <EmptyHint title="Sin expedientes" next={`Cada proyecto es una carpeta en ${list.data.folder} con su Proyecto.md.`} />;
  return (
    <div className="grid gap-4 lg:grid-cols-[260px_1fr]">
      <div className={cn("space-y-1", client && "hidden lg:block")}>
        <div className="px-1 pb-1 text-micro text-muted-foreground">Proyectos · {list.data.folder}</div>
        {projects.map((p) => (
          <button
            key={p.slug}
            type="button"
            onClick={() => setParams(nav, { proyecto: p.slug })}
            className={cn("w-full rounded-lg border px-3 py-2 text-left hover:bg-muted/40", p.slug === slug && "border-foreground/30 bg-muted/50")}
          >
            <div className="flex items-center gap-1.5">
              <span className="min-w-0 flex-1 truncate text-caption font-medium">{p.title}</span>
              {p.demo ? <Pill className="shrink-0">Demo</Pill> : null}
            </div>
            <div className="flex items-center gap-1.5 text-micro text-muted-foreground">
              <span className="truncate">{p.client || "Sin cliente"}</span>
              <span>·</span>
              <span className="shrink-0">{p.state || "Sin estado"}</span>
              {p.has_portal ? <span className="ml-auto shrink-0 tabular-nums">{p.progress.percent}%</span> : <span className="ml-auto shrink-0">sin portal</span>}
            </div>
          </button>
        ))}
      </div>
      {slug ? <PortalView key={`${slug}-${client}`} slug={slug} client={client} types={list.data.types} severities={list.data.severities} /> : null}
    </div>
  );
}

function PortalView({ slug, client, types, severities }: { slug: string; client: boolean; types: string[]; severities: string[] }) {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const q = useQuery(bizPortalOptions(wsId, slug, client));
  const [open, setOpen] = useState<string>("");
  useEffect(() => {
    const cur = q.data?.sessions?.find((s) => s.current)?.code ?? "";
    setOpen((o) => o || cur);
  }, [q.data]);
  if (q.isLoading) return <LoadingBlock rows={8} />;
  if (q.error || !q.data) return <ErrorBlock error={q.error} retry={() => q.refetch()} />;
  const p = q.data;
  const sessions = p.sessions ?? [];
  const selected = sessions.find((s) => s.code === open);
  return (
    <div className="min-w-0 space-y-5">
      <div className="flex flex-wrap items-start gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="text-title font-semibold">{client ? p.client || p.title : p.title}</h2>
            {p.demo ? <Pill>Demo</Pill> : null}
            {p.closed ? <Pill><Lock className="mr-1 inline size-3" />{p.state} · solo lectura</Pill> : null}
          </div>
          <div className="text-caption text-muted-foreground">{client ? "Tu proyecto con The Last" : `${p.client || "Sin cliente"} · ${p.state || "Sin estado"}`}</div>
        </div>
        <div className="inline-flex rounded-md border p-0.5">
          <Button size="xs" variant={client ? "ghost" : "secondary"} onClick={() => setParams(nav, { vista: null })}>Vista interna</Button>
          <Button size="xs" variant={client ? "secondary" : "ghost"} onClick={() => setParams(nav, { vista: "cliente" })}><Eye />Vista cliente</Button>
        </div>
      </div>

      {client ? (
        <div className="rounded-lg border border-dashed px-3 py-2 text-caption text-muted-foreground">
          Así lo vería el cliente: solo lectura, sin notas internas ni responsables. No está publicado en internet; Manu decide cuándo y cómo se comparte.
        </div>
      ) : !p.has_portal ? (
        <div className="rounded-lg border border-dashed px-3 py-2 text-caption text-muted-foreground">
          Este expediente aún no tiene <code>Portal.md</code>: el viaje sale sin registrar. Para activarlo, crea <code>{p.portal_path}</code> con la tabla «## Viaje» y la lista «## Tareas del cliente».
        </div>
      ) : null}

      <Progress p={p} client={client} />

      <Section title={client ? "Tus sesiones" : "Viaje S1–S9"}>
        <div className="grid grid-cols-3 gap-2 sm:grid-cols-5 xl:grid-cols-9">
          {sessions.map((s) => (
            <button
              key={s.code}
              type="button"
              onClick={() => setOpen(s.code === open ? "" : s.code)}
              className={cn("rounded-lg border p-2 text-left transition-colors hover:bg-muted/40", STATE_TONE[s.state], s.code === open && "ring-2 ring-foreground/20", s.current && "border-foreground/50")}
            >
              <div className="flex items-center gap-1 text-micro text-muted-foreground">
                {s.state === "hecha" ? <Check className="size-3" /> : <Circle className="size-3" />}
                {client ? STATE_LABEL[s.state]?.client : `${s.code} · ${STATE_LABEL[s.state]?.internal ?? s.status}`}
              </div>
              <div className="mt-0.5 line-clamp-2 text-caption font-medium leading-tight">{s.name}</div>
              <div className="mt-1 text-micro text-muted-foreground">{s.date ? formatDate(s.date) : "—"}{(s.kit ?? []).length ? ` · ${(s.kit ?? []).length} doc.` : ""}</div>
            </button>
          ))}
        </div>
        {selected ? <SessionDetail s={selected} client={client} /> : null}
      </Section>

      <div className="grid gap-5 xl:grid-cols-2">
        <Section title={client ? "Lo que te toca" : `Tareas del cliente (${p.progress.tasks_done}/${p.progress.tasks_total})`}>
          {(p.tasks ?? []).length === 0 ? (
            <EmptyHint title="Sin tareas para el cliente" next={client ? undefined : "Se anotan en «## Tareas del cliente» de Portal.md como casillas."} />
          ) : (
            <ul className="divide-y rounded-lg border">
              {(p.tasks ?? []).map((t, i) => (
                <li key={i} className="flex items-start gap-2 px-3 py-2 text-caption">
                  <span className={cn("mt-0.5 flex size-4 shrink-0 items-center justify-center rounded border", t.done && "border-emerald-600 bg-emerald-600 text-white")}>
                    {t.done ? <Check className="size-3" /> : null}
                  </span>
                  <span className={cn("min-w-0 flex-1", t.done && "text-muted-foreground line-through")}>{t.text}</span>
                  {t.session ? <span className="shrink-0 text-micro text-muted-foreground">{client ? sessions.find((s) => s.code === t.session)?.name ?? "" : t.session}</span> : null}
                  {t.due ? <span className={cn("shrink-0 text-micro tabular-nums", t.overdue ? "font-medium text-red-600" : "text-muted-foreground")}>{t.overdue ? "venció " : "vence "}{formatDate(t.due)}</span> : null}
                </li>
              ))}
            </ul>
          )}
        </Section>

        <Section title={`Documentación${(p.documents ?? []).length ? ` (${(p.documents ?? []).length})` : ""}`}>
          {(p.documents ?? []).length === 0 ? (
            <EmptyHint title="Sin documentación compartida" next={client ? undefined : `Lo que el cliente ve va en ${p.client_folder}/ (lo de una sesión, en una carpeta «S<n> …»).`} />
          ) : (
            <DocList docs={p.documents ?? []} client={client} />
          )}
        </Section>
      </div>

      <Incidents p={p} client={client} types={types} severities={severities} />

      {!client ? (
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 border-t pt-3 text-micro text-muted-foreground">
          <span>Se edita en la carpeta:</span>
          {[p.path, p.portal_path, p.incidents_path].map((f) => (
            <button key={f} type="button" className="inline-flex items-center gap-1 hover:underline" onClick={() => void openOriginal(f)} title="Abrir el original">
              <code>{f.split("/").pop()}</code>
            </button>
          ))}
          <button type="button" className="inline-flex items-center gap-1 hover:underline" onClick={() => void revealInFinder(p.path)}>
            <FolderOpen className="size-3" /> Mostrar en Finder
          </button>
        </div>
      ) : null}
      {!client && p.intro ? (
        <details className="rounded-lg border px-3 py-2 text-caption">
          <summary className="cursor-pointer text-muted-foreground">Notas internas de Portal.md</summary>
          <Markdown mode="minimal" className="mt-2 text-caption">{p.intro}</Markdown>
        </details>
      ) : null}
    </div>
  );
}

function Progress({ p, client }: { p: BizPortalProject; client: boolean }) {
  const pr = p.progress;
  const cur = (p.sessions ?? []).find((s) => s.code === pr.current);
  const stats = [
    { label: client ? "Sesiones hechas" : "Sesiones", value: `${pr.sessions_done}/${pr.sessions_total}` },
    { label: client ? "Siguiente" : "Sesión actual", value: cur ? (client ? cur.name : `${cur.code} · ${cur.name}`) : pr.sessions_total ? "Completado" : "—" },
    { label: client ? "Tus tareas" : "Tareas del cliente", value: `${pr.tasks_done}/${pr.tasks_total}` },
    { label: "Incidencias abiertas", value: String(pr.incidents_open) },
  ];
  return (
    <div className="rounded-lg border p-3">
      <div className="flex items-baseline justify-between">
        <span className="text-caption font-medium">Avance</span>
        <span className="text-title font-semibold tabular-nums">{pr.percent}%</span>
      </div>
      <div className="mt-1.5 h-2 overflow-hidden rounded-full bg-muted">
        <div className="h-full rounded-full bg-emerald-600" style={{ width: `${pr.percent}%` }} />
      </div>
      <div className="mt-3 grid grid-cols-2 gap-3 md:grid-cols-4">
        {stats.map((s) => (
          <div key={s.label}>
            <div className="text-micro text-muted-foreground">{s.label}</div>
            <div className="truncate text-body font-medium tabular-nums" title={s.value}>{s.value}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

function useBlobUrl(path: string) {
  const q = useQuery({ queryKey: ["biz-blob", path], queryFn: () => bizApi.file(path), enabled: Boolean(path), staleTime: Infinity });
  const [url, setUrl] = useState("");
  useEffect(() => {
    if (!q.data) return;
    const u = URL.createObjectURL(q.data);
    setUrl(u);
    return () => URL.revokeObjectURL(u);
  }, [q.data]);
  return url;
}

function SessionDetail({ s, client }: { s: BizPortalSession; client: boolean }) {
  const cover = useBlobUrl(client ? "" : s.cover);
  const kit = s.kit ?? [];
  return (
    <div className="mt-3 grid gap-4 rounded-lg border p-3 md:grid-cols-[1fr_220px]">
      <div className="min-w-0 space-y-3">
        <div>
          <div className="text-body font-medium">{client ? `Tu sesión de ${s.name.toLowerCase()}` : `${s.code} · ${s.name}`}</div>
          <div className="text-caption text-muted-foreground">
            {(client ? STATE_LABEL[s.state]?.client : s.status || "Sin registrar") ?? s.status}
            {s.date ? ` · ${formatDate(s.date)}` : ""}
          </div>
        </div>
        {s.summary ? <p className="text-caption">{s.summary}</p> : <p className="text-caption text-muted-foreground">{client ? "Aquí aparecerá el resumen después de la sesión." : "Sin resumen para el cliente."}</p>}
        {!client && s.note ? (
          <div className="rounded-md bg-muted/50 px-2 py-1.5 text-caption"><span className="font-medium">Nota interna:</span> {s.note}</div>
        ) : null}
        <div>
          <div className="mb-1 text-caption font-medium">{client ? "Materiales" : `Kit de la sesión (${kit.length})`}</div>
          {kit.length === 0 ? (
            <p className="text-caption text-muted-foreground">{client ? "Aún no hay materiales." : "Sin documentos: van en una carpeta «" + s.code + " …» del proyecto (internos) o de Portal Cliente/ (los ve el cliente)."}</p>
          ) : (
            <DocList docs={kit} client={client} />
          )}
        </div>
      </div>
      {!client && cover ? <img src={cover} alt={`Portada ${s.code}`} className="w-full rounded-md border object-cover" /> : null}
    </div>
  );
}

function DocList({ docs, client }: { docs: BizPortalDoc[]; client: boolean }) {
  return (
    <ul className="divide-y rounded-lg border">
      {docs.map((d) => (
        <li key={d.path} className="flex items-center gap-2 px-3 py-1.5 text-caption">
          <FileText className="size-3.5 shrink-0 text-muted-foreground" />
          <button type="button" className="min-w-0 flex-1 truncate text-left hover:underline" title={client ? d.name : d.path} onClick={() => void openOriginal(d.path)}>
            {d.name}
          </button>
          {!client ? <Pill className="shrink-0">{d.client ? "Cliente" : "Interno"}</Pill> : null}
          {d.in_cloud ? <Pill className="shrink-0">En iCloud</Pill> : null}
          <span className="shrink-0 text-micro uppercase text-muted-foreground">{d.ext}</span>
          <Button size="xs" variant="ghost" onClick={() => void openOriginal(d.path)} title="Abrir"><ExternalLink /></Button>
        </li>
      ))}
    </ul>
  );
}

const SEVERITY_TONE: Record<string, string> = { Grave: "text-red-600", Media: "text-amber-600", Leve: "text-muted-foreground" };

function Incidents({ p, client, types, severities }: { p: BizPortalProject; client: boolean; types: string[]; severities: string[] }) {
  const [form, setForm] = useState(false);
  const incidents = p.incidents ?? [];
  const canAdd = !p.closed;
  return (
    <Section
      title={`Incidencias (abiertas: ${incidents.filter((i) => i.open).length} de ${incidents.length})`}
      actions={canAdd ? <Button size="xs" variant="outline" onClick={() => setForm((f) => !f)}>{form ? "Cerrar formulario" : "Reportar incidencia"}</Button> : null}
    >
      <p className="mb-2 text-micro text-muted-foreground">
        Para errores, accesos rotos, automatizaciones que fallan o bloqueos. Las dudas, mejoras y cambios menores van por comentarios.
      </p>
      {form && canAdd ? <IncidentForm slug={p.slug} client={client} types={types} severities={severities} onDone={() => setForm(false)} /> : null}
      {incidents.length === 0 ? (
        <EmptyHint title="Sin incidencias" />
      ) : (
        <div className="overflow-x-auto rounded-lg border">
          <table className="w-full text-caption">
            <thead className="bg-muted/40 text-left text-micro text-muted-foreground">
              <tr>
                <th className="px-2 py-1.5">ID</th>
                <th className="px-2 py-1.5">Fecha</th>
                <th className="px-2 py-1.5">Descripción</th>
                <th className="px-2 py-1.5">Tipo</th>
                <th className="px-2 py-1.5">Severidad</th>
                <th className="px-2 py-1.5">Estado</th>
                {!client ? <th className="px-2 py-1.5">Responsable</th> : null}
                {!client ? <th className="px-2 py-1.5">Resolución</th> : null}
              </tr>
            </thead>
            <tbody className="divide-y">
              {incidents.map((i) => (
                <tr key={i.id || i.description} className={cn(!i.open && "text-muted-foreground")}>
                  <td className="whitespace-nowrap px-2 py-1.5 font-mono">{i.id}</td>
                  <td className="whitespace-nowrap px-2 py-1.5 tabular-nums">{i.date ? formatDate(i.date) : "—"}</td>
                  <td className="px-2 py-1.5">
                    {i.description}
                    {i.reporter ? <div className="text-micro text-muted-foreground">{i.reporter}{!client && i.email ? ` · ${i.email}` : ""}</div> : null}
                  </td>
                  <td className="px-2 py-1.5">{i.type}</td>
                  <td className={cn("px-2 py-1.5", SEVERITY_TONE[i.severity])}>{i.severity}</td>
                  <td className="whitespace-nowrap px-2 py-1.5">
                    {i.status || "—"}
                    {i.open && !client && i.age_days > 3 ? <div className="text-micro text-red-600">{i.age_days} días</div> : null}
                  </td>
                  {!client ? <td className="px-2 py-1.5">{i.owner || "—"}</td> : null}
                  {!client ? <td className="px-2 py-1.5">{i.resolution || "—"}</td> : null}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Section>
  );
}

function IncidentForm({ slug, client, types, severities, onDone }: { slug: string; client: boolean; types: string[]; severities: string[]; onDone: () => void }) {
  const wsId = useWorkspaceId();
  const qc = useQueryClient();
  const [v, setV] = useState<BizIncidentInput>({ reporter: "", email: "", date: new Date().toISOString().slice(0, 10), type: "", severity: "", description: "", steps: "" });
  const [busy, setBusy] = useState(false);
  const set = (k: keyof BizIncidentInput) => (e: { target: { value: string } }) => setV((o) => ({ ...o, [k]: e.target.value }));
  const ready = v.reporter && v.email.includes("@") && v.date && v.type && v.severity && v.description.trim();
  const submit = async () => {
    if (client) return;
    setBusy(true);
    try {
      const r = (await bizApi.addIncident(slug, v)) as { id?: string; path?: string };
      toast.success(`Incidencia ${r.id ?? ""} registrada en ${r.path ?? "Incidencias.md"}`);
      await qc.invalidateQueries({ queryKey: bizKeys.portals(wsId) });
      onDone();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "No se pudo registrar");
    } finally {
      setBusy(false);
    }
  };
  const field = "h-8 w-full rounded-md border bg-transparent px-2 text-caption";
  return (
    <div className="mb-3 space-y-2 rounded-lg border p-3">
      {client ? (
        <p className="text-micro text-muted-foreground">Vista previa del formulario del cliente: en esta vista no se envía. Para registrar una incidencia que llega por otro canal, usa la vista interna.</p>
      ) : null}
      <div className="grid gap-2 md:grid-cols-3">
        <label className="text-micro text-muted-foreground">Quién reporta *<Input className="h-8 text-caption" value={v.reporter} onChange={set("reporter")} /></label>
        <label className="text-micro text-muted-foreground">Email de contacto *<Input className="h-8 text-caption" type="email" value={v.email} onChange={set("email")} /></label>
        <label className="text-micro text-muted-foreground">Fecha del incidente *<Input className="h-8 text-caption" type="date" value={v.date} onChange={set("date")} /></label>
        <label className="text-micro text-muted-foreground">Tipo *
          <select className={field} value={v.type} onChange={set("type")}>
            <option value="">Elegir…</option>
            {types.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </label>
        <label className="text-micro text-muted-foreground">Gravedad *
          <select className={field} value={v.severity} onChange={set("severity")}>
            <option value="">Elegir…</option>
            {severities.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </label>
      </div>
      <label className="block text-micro text-muted-foreground">Qué ha pasado y qué esperabas que pasara *
        <textarea className="mt-0.5 min-h-16 w-full rounded-md border bg-transparent px-2 py-1 text-caption" value={v.description} onChange={set("description")} />
      </label>
      <label className="block text-micro text-muted-foreground">Pasos para reproducirlo (si aplica)
        <textarea className="mt-0.5 min-h-10 w-full rounded-md border bg-transparent px-2 py-1 text-caption" value={v.steps} onChange={set("steps")} />
      </label>
      <div className="flex items-center justify-end gap-2">
        <Button size="sm" variant="ghost" onClick={onDone}>Cancelar</Button>
        <Button size="sm" disabled={client || !ready || busy} onClick={() => void submit()}>{busy ? "Registrando…" : "Registrar incidencia"}</Button>
      </div>
    </div>
  );
}
