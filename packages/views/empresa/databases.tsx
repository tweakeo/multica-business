/* eslint-disable i18next/no-literal-string, no-restricted-syntax -- TLS "Empresa" module ships Spanish copy only (labels and aria text included); see docs/tls/DECISIONES.md */
"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Database, ExternalLink, FolderOpen, LayoutList, Lock, Table2 } from "lucide-react";
import { toast } from "sonner";
import {
  bizApi,
  bizDatabaseOptions,
  bizDatabaseRowOptions,
  bizDatabasesOptions,
  formatDate,
  type BizDbInfo,
  type BizDbLink,
  type BizDbRow,
} from "@multica/core/biz";
import { useWorkspaceId } from "@multica/core/hooks";
import { useWorkspacePaths } from "@multica/core/paths";
import { Button } from "@multica/ui/components/ui/button";
import { Input } from "@multica/ui/components/ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@multica/ui/components/ui/sheet";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@multica/ui/components/ui/table";
import { Markdown } from "@multica/ui/markdown";
import { cn } from "@multica/ui/lib/utils";
import { PAGE_GUTTER } from "../layout/page-header";
import { AppLink, useNavigation } from "../navigation";
import { openOriginal, revealInFinder } from "./library";
import { EmpresaShell } from "./overview-page";
import { AREAS, AreaDot, EmptyHint, ErrorBlock, LoadingBlock, Pill, useInspector } from "./shared";

// «Bases de datos»: every database of the company in one place, each read
// from where it lives in the folder (see server/internal/biz/databases.go).
// Here everything is read; a record the app also knows opens its sheet,
// where changes go through the single writer.

const GROUPS: { area: string; name: string }[] = [...AREAS.map((a) => ({ area: a.code as string, name: a.name as string })), { area: "", name: "Toda la empresa" }];

function areaName(code: string) {
  return AREAS.find((a) => a.code === code)?.name ?? "General";
}

/** «2026-10-21» → 21 oct 2026; «2026-09» → sept 2026. */
export function day(v: string) {
  if (/^\d{4}-\d{2}$/.test(v)) {
    const [y, m] = v.split("-").map(Number);
    return new Intl.DateTimeFormat("es-ES", { month: "short", year: "numeric" }).format(new Date(Date.UTC(y!, m! - 1, 15)));
  }
  return v ? formatDate(v) : "—";
}

async function openInObsidian(path: string) {
  try {
    const res = await bizApi.openInObsidian(path);
    if ((res as { opened_with?: string }).opened_with === "default") toast("La carpeta de The Last no está en una bóveda de Obsidian: se abrió con la app predeterminada.");
  } catch (e) {
    toast.error(e instanceof Error ? e.message : "No se pudo abrir");
  }
}

function OriginalButtons({ path, size = "xs" }: { path: string; size?: "xs" | "sm" }) {
  if (!path) return null;
  const note = path.toLowerCase().endsWith(".md");
  const file = /\.[a-z0-9]{2,5}$/i.test(path);
  return (
    <span className="inline-flex flex-wrap items-center gap-1">
      {note ? (
        <Button size={size} variant="outline" onClick={() => void openInObsidian(path)} title="Abrir la nota en Obsidian">
          Abrir en Obsidian <ExternalLink />
        </Button>
      ) : file ? (
        <Button size={size} variant="outline" onClick={() => void openOriginal(path)} title="Abrir el original">
          Abrir <ExternalLink />
        </Button>
      ) : null}
      <Button size={size} variant="ghost" onClick={() => void revealInFinder(path)} title="Mostrar en Finder">
        <FolderOpen /> Finder
      </Button>
    </span>
  );
}

// --- Index ----------------------------------------------------------------------

function DatabaseCard({ db }: { db: BizDbInfo }) {
  const p = useWorkspacePaths();
  return (
    <AppLink
      href={p.basesDb(db.key)}
      className="flex flex-col gap-1 rounded-lg border p-3 transition-colors hover:bg-accent/50 focus-visible:outline-2 focus-visible:outline-ring"
    >
      <span className="flex items-center gap-2">
        <span className="text-body font-medium">{db.name}</span>
        <span className="ml-auto text-caption tabular-nums text-muted-foreground">{db.count}</span>
      </span>
      <span className="text-caption text-muted-foreground">{db.description}</span>
      {db.count === 0 ? <span className="text-micro text-muted-foreground">Vacía · {db.fill}</span> : null}
    </AppLink>
  );
}

function DatabasesIndex({ dbs }: { dbs: BizDbInfo[] }) {
  return (
    <div className={cn(PAGE_GUTTER, "space-y-6 py-4")}>
      <p className="max-w-3xl text-caption text-muted-foreground">
        Todas las bases de datos de The Last en un solo sitio. Cada una se lee de su sitio en la carpeta de la empresa (notas, tablas, registros y documentos) y
        enlaza con el original. Lo que la app también conoce se edita desde su ficha, con el escritor único.
      </p>
      {GROUPS.map((g) => {
        const list = dbs.filter((d) => d.area === g.area);
        if (list.length === 0) return null;
        return (
          <section key={g.area || "general"} className="space-y-2">
            <h2 className="flex items-center gap-2 text-caption font-medium text-muted-foreground">
              {g.area ? <AreaDot area={g.area} /> : null}
              {g.name}
            </h2>
            <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-3">
              {list.map((d) => (
                <DatabaseCard key={d.key} db={d} />
              ))}
            </div>
          </section>
        );
      })}
    </div>
  );
}

// --- One database ----------------------------------------------------------------

function Rail({ dbs, current }: { dbs: BizDbInfo[]; current: string }) {
  const p = useWorkspacePaths();
  return (
    <nav aria-label="Bases de datos" className="hidden w-56 shrink-0 overflow-y-auto border-r py-3 pr-2 pl-4 lg:block">
      <AppLink href={p.bases()} className="mb-2 flex items-center gap-1.5 rounded-md px-2 py-1 text-caption text-muted-foreground hover:bg-accent/50">
        <ArrowLeft className="size-3.5" /> Todas
      </AppLink>
      {GROUPS.map((g) => {
        const list = dbs.filter((d) => d.area === g.area);
        if (list.length === 0) return null;
        return (
          <div key={g.area || "general"} className="mb-2">
            <div className="flex items-center gap-1.5 px-2 py-1 text-micro text-muted-foreground">
              {g.area ? <AreaDot area={g.area} /> : null}
              {g.name}
            </div>
            {list.map((d) => (
              <AppLink
                key={d.key}
                href={p.basesDb(d.key)}
                aria-current={d.key === current ? "page" : undefined}
                className={cn(
                  "flex items-center gap-2 rounded-md px-2 py-1 text-caption hover:bg-accent/50",
                  d.key === current ? "bg-accent font-medium text-foreground" : "text-muted-foreground",
                )}
              >
                <span className="min-w-0 flex-1 truncate">{d.name}</span>
                <span className="tabular-nums">{d.count}</span>
              </AppLink>
            ))}
          </div>
        );
      })}
    </nav>
  );
}

const SELECT = "h-8 rounded-md border bg-transparent px-2 text-caption";

type DateFilter = "" | "30" | "quarter" | "year" | "range";

export function inDates(v: string, f: DateFilter, from: string, to: string, now = new Date()) {
  if (!f) return true;
  if (!v) return false;
  const start = v.length === 7 ? `${v}-01` : v;
  const end = v.length === 7 ? `${v}-31` : v;
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  let lo = "";
  let hi = "9999-12-31";
  if (f === "30") lo = iso(new Date(now.getTime() - 30 * 86_400_000));
  if (f === "quarter") lo = iso(new Date(Date.UTC(now.getFullYear(), Math.floor(now.getMonth() / 3) * 3, 1)));
  if (f === "year") lo = `${now.getFullYear()}-01-01`;
  if (f === "range") {
    lo = from;
    hi = to || hi;
  }
  return end >= lo && start <= hi;
}

function uniq(values: string[]) {
  return [...new Set(values.filter(Boolean))].sort((a, b) => a.localeCompare(b, "es"));
}

function DatabaseView({ dbKey, dbs }: { dbKey: string; dbs: BizDbInfo[] }) {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const q = useQuery(bizDatabaseOptions(wsId, dbKey));
  const [term, setTerm] = useState("");
  const [area, setArea] = useState("");
  const [status, setStatus] = useState("");
  const [owner, setOwner] = useState("");
  const [dates, setDates] = useState<DateFilter>("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [view, setView] = useState<"tabla" | "lista">("tabla");
  const selected = nav.searchParams.get("fila") ?? "";
  const select = (db: string, id: string) => {
    const sp = new URLSearchParams(nav.searchParams);
    if (id) sp.set("fila", id);
    else sp.delete("fila");
    const qs = sp.toString();
    const base = db === dbKey ? nav.pathname : nav.pathname.replace(/\/bases\/[^/]+$/, `/bases/${encodeURIComponent(db)}`);
    nav.replace(`${base}${qs ? `?${qs}` : ""}`);
  };

  const info = q.data?.database ?? dbs.find((d) => d.key === dbKey) ?? null;
  const rows = useMemo(() => q.data?.rows ?? [], [q.data]);
  const options = useMemo(
    () => ({ areas: uniq(rows.map((r) => r.area)), statuses: uniq(rows.map((r) => r.status)), owners: uniq(rows.map((r) => r.owner)) }),
    [rows],
  );
  const shown = useMemo(() => {
    const t = term.trim().toLowerCase();
    return rows.filter(
      (r) =>
        (!area || r.area === area) &&
        (!status || r.status === status) &&
        (!owner || r.owner === owner) &&
        inDates(r.date, dates, from, to) &&
        (!t || [r.title, r.subtitle, r.status, r.owner, r.origin, r.path, ...(r.fields ?? []).map((f) => f.value)].join(" ").toLowerCase().includes(t)),
    );
  }, [rows, term, area, status, owner, dates, from, to]);

  if (!info) return <div className={cn(PAGE_GUTTER, "py-4")}><EmptyHint title="Base de datos desconocida" /></div>;
  const columns = info.columns ?? [];
  const showArea = !info.area && options.areas.length > 1;
  const filtered = shown.length !== rows.length;

  return (
    <div className="flex h-full min-h-0">
      <Rail dbs={dbs} current={dbKey} />
      <div className="min-w-0 flex-1 space-y-3 overflow-y-auto py-4 pr-4 pl-4 lg:pl-6">
        <header className="space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="text-heading font-semibold">{info.name}</h2>
            {info.area ? (
              <span className="inline-flex items-center gap-1.5 text-caption text-muted-foreground">
                <AreaDot area={info.area} /> {areaName(info.area)}
              </span>
            ) : null}
            <span className="text-caption tabular-nums text-muted-foreground">{filtered ? `${shown.length} de ${rows.length}` : rows.length}</span>
            {info.folder ? (
              <span className="ml-auto">
                <Button size="xs" variant="ghost" onClick={() => void revealInFinder(info.folder)} title="Mostrar la carpeta en Finder">
                  <FolderOpen /> Carpeta
                </Button>
              </span>
            ) : null}
          </div>
          <p className="text-caption text-muted-foreground">{info.description}</p>
          <p className="text-micro text-muted-foreground">
            Fuente: <code>{info.source}</code>
          </p>
          {info.why ? <p className="text-micro text-muted-foreground">{info.why}</p> : null}
        </header>

        {q.isLoading ? <LoadingBlock rows={6} /> : q.error ? <ErrorBlock error={q.error} retry={() => void q.refetch()} /> : null}

        {!q.isLoading && !q.error && rows.length === 0 ? (
          <EmptyHint
            title={q.data && !q.data.configured ? "La empresa no tiene carpeta configurada" : "Esta base de datos está vacía"}
            next={
              <span className="inline-flex flex-wrap items-center gap-2">
                <span>{info.fill}</span>
                {info.folder ? (
                  <Button size="xs" variant="outline" onClick={() => void revealInFinder(info.folder)}>
                    <FolderOpen /> Abrir la carpeta
                  </Button>
                ) : null}
              </span>
            }
          />
        ) : null}

        {rows.length > 0 ? (
          <>
            <div className="flex flex-wrap items-center gap-2" role="search">
              <Input value={term} onChange={(e) => setTerm(e.target.value)} placeholder="Buscar…" aria-label="Buscar en la base de datos" className="h-8 w-56" />
              {options.areas.length > 1 ? (
                <select className={SELECT} value={area} onChange={(e) => setArea(e.target.value)} aria-label="Área">
                  <option value="">Todas las áreas</option>
                  {options.areas.map((a) => (
                    <option key={a} value={a}>{areaName(a)}</option>
                  ))}
                </select>
              ) : null}
              {options.statuses.length > 1 ? (
                <select className={SELECT} value={status} onChange={(e) => setStatus(e.target.value)} aria-label="Estado">
                  <option value="">Todos los estados</option>
                  {options.statuses.map((s) => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </select>
              ) : null}
              {options.owners.length > 0 ? (
                <select className={SELECT} value={owner} onChange={(e) => setOwner(e.target.value)} aria-label="Responsable">
                  <option value="">Cualquier responsable</option>
                  {options.owners.map((o) => (
                    <option key={o} value={o}>{o}</option>
                  ))}
                </select>
              ) : null}
              <select className={SELECT} value={dates} onChange={(e) => setDates(e.target.value as DateFilter)} aria-label="Fecha">
                <option value="">Cualquier fecha</option>
                <option value="30">Últimos 30 días</option>
                <option value="quarter">Este trimestre</option>
                <option value="year">Este año</option>
                <option value="range">Entre fechas…</option>
              </select>
              {dates === "range" ? (
                <>
                  <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} aria-label="Desde" className="h-8 w-36" />
                  <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} aria-label="Hasta" className="h-8 w-36" />
                </>
              ) : null}
              {filtered ? (
                <Button size="xs" variant="ghost" onClick={() => { setTerm(""); setArea(""); setStatus(""); setOwner(""); setDates(""); }}>
                  Quitar filtros
                </Button>
              ) : null}
              <span className="ml-auto inline-flex rounded-md border p-0.5" role="group" aria-label="Vista">
                <Button size="xs" variant={view === "tabla" ? "secondary" : "ghost"} aria-pressed={view === "tabla"} onClick={() => setView("tabla")}>
                  <Table2 /> Tabla
                </Button>
                <Button size="xs" variant={view === "lista" ? "secondary" : "ghost"} aria-pressed={view === "lista"} onClick={() => setView("lista")}>
                  <LayoutList /> Lista
                </Button>
              </span>
            </div>

            {shown.length === 0 ? (
              <EmptyHint title="Ningún registro cumple los filtros" />
            ) : view === "tabla" ? (
              <div className="overflow-x-auto rounded-lg border">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="h-8 text-caption">Nombre</TableHead>
                      {showArea ? <TableHead className="h-8 text-caption">Área</TableHead> : null}
                      <TableHead className="h-8 text-caption">Estado</TableHead>
                      <TableHead className="h-8 text-caption">Fecha</TableHead>
                      <TableHead className="h-8 text-caption">Responsable</TableHead>
                      {columns.map((c) => (
                        <TableHead key={c} className="h-8 text-caption">{c}</TableHead>
                      ))}
                      <TableHead className="h-8 text-caption">Relaciones</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {shown.map((r) => (
                      <TableRow
                        key={r.id}
                        className={cn("cursor-pointer", selected === r.id && "bg-accent/60")}
                        tabIndex={0}
                        onClick={() => select(dbKey, r.id)}
                        onKeyDown={(e) => e.key === "Enter" && select(dbKey, r.id)}
                      >
                        <TableCell className="max-w-96 py-1.5 text-caption">
                          <span className="flex items-center gap-1.5">
                            {r.private ? <Lock className="size-3 shrink-0 text-muted-foreground" aria-label="Privado" /> : null}
                            <span className="truncate font-medium">{r.title || "—"}</span>
                          </span>
                          {r.subtitle ? <span className="text-micro text-muted-foreground">{r.subtitle}</span> : null}
                        </TableCell>
                        {showArea ? (
                          <TableCell className="py-1.5 text-caption">
                            {r.area ? <span className="inline-flex items-center gap-1.5"><AreaDot area={r.area} />{areaName(r.area)}</span> : "—"}
                          </TableCell>
                        ) : null}
                        <TableCell className="py-1.5 text-caption">{r.status || "—"}</TableCell>
                        <TableCell className="py-1.5 text-caption whitespace-nowrap tabular-nums">{day(r.date)}</TableCell>
                        <TableCell className="py-1.5 text-caption">{r.owner || "—"}</TableCell>
                        {columns.map((c) => (
                          <TableCell key={c} className="max-w-64 truncate py-1.5 text-caption">{(r.fields ?? []).find((f) => f.label === c)?.value || "—"}</TableCell>
                        ))}
                        <TableCell className="py-1.5 text-caption text-muted-foreground">
                          {(r.links ?? []).length ? (r.links ?? []).map((l) => l.title).join(", ") : "—"}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            ) : (
              <ul className="divide-y rounded-lg border">
                {shown.map((r) => (
                  <li key={r.id}>
                    <button
                      type="button"
                      onClick={() => select(dbKey, r.id)}
                      className={cn("flex w-full flex-col gap-0.5 px-3 py-2 text-left hover:bg-accent/50", selected === r.id && "bg-accent/60")}
                    >
                      <span className="flex items-center gap-2">
                        {r.area ? <AreaDot area={r.area} /> : null}
                        <span className="min-w-0 flex-1 truncate text-body font-medium">{r.title || "—"}</span>
                        <span className="text-caption text-muted-foreground">{day(r.date)}</span>
                      </span>
                      <span className="text-caption text-muted-foreground">
                        {[r.status, r.owner, ...columns.map((c) => (r.fields ?? []).find((f) => f.label === c)?.value ?? "")].filter(Boolean).join(" · ")}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </>
        ) : null}
      </div>
      <RowSheet dbKey={dbKey} id={selected} dbs={dbs} onClose={() => select(dbKey, "")} onOpen={select} />
    </div>
  );
}

// --- Detail ------------------------------------------------------------------------

function LinkList({ title, links, dbs, onOpen }: { title: string; links: BizDbLink[]; dbs: BizDbInfo[]; onOpen: (db: string, id: string) => void }) {
  if (links.length === 0) return null;
  const name = (k: string) => dbs.find((d) => d.key === k)?.name ?? k;
  return (
    <div className="space-y-1">
      <div className="text-caption font-medium">{title}</div>
      <ul className="space-y-0.5">
        {links.map((l) => (
          <li key={l.db + l.id}>
            <button type="button" onClick={() => onOpen(l.db, l.id)} className="text-left text-caption hover:underline">
              <span className="text-muted-foreground">{name(l.db)} · </span>
              {l.title || l.id}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}

function RowSheet({ dbKey, id, dbs, onClose, onOpen }: { dbKey: string; id: string; dbs: BizDbInfo[]; onClose: () => void; onOpen: (db: string, id: string) => void }) {
  const wsId = useWorkspaceId();
  const nav = useNavigation();
  const p = useWorkspacePaths();
  const inspect = useInspector();
  const q = useQuery(bizDatabaseRowOptions(wsId, dbKey, id));
  const row: BizDbRow | undefined = q.data?.row;
  return (
    <Sheet open={Boolean(id)} onOpenChange={(o) => !o && onClose()}>
      <SheetContent side="right" className="w-full overflow-y-auto data-[side=right]:sm:max-w-xl">
        {q.isLoading ? (
          <div className="p-4"><LoadingBlock rows={5} /></div>
        ) : q.error ? (
          <div className="p-4"><ErrorBlock error={q.error} /></div>
        ) : row ? (
          <>
            <SheetHeader>
              <SheetTitle className="pr-6">{row.title || "—"}</SheetTitle>
              <SheetDescription>
                {dbs.find((d) => d.key === dbKey)?.name} · {row.origin}
              </SheetDescription>
            </SheetHeader>
            <div className="space-y-4 px-4 pb-6">
              <div className="flex flex-wrap items-center gap-1.5">
                {row.area ? (
                  <Pill className="inline-flex items-center gap-1.5"><AreaDot area={row.area} />{areaName(row.area)}</Pill>
                ) : null}
                {row.status ? <Pill>{row.status}</Pill> : null}
                {row.date ? <Pill>{day(row.date)}</Pill> : null}
                {row.owner ? <Pill>Responsable: {row.owner}</Pill> : null}
                {row.private ? <Pill className="inline-flex items-center gap-1"><Lock className="size-3" />Privado</Pill> : null}
              </div>
              <div className="flex flex-wrap items-center gap-2">
                <OriginalButtons path={row.path} size="sm" />
                {row.entity === "issue" ? (
                  <Button size="sm" variant="outline" onClick={() => nav.push(p.issueDetail(row.entity_id))}>Abrir la tarea</Button>
                ) : row.entity ? (
                  <Button size="sm" variant="outline" onClick={() => inspect({ entity: row.entity, id: row.entity_id })} title="Ficha de la app: aquí se edita">
                    <Database /> Ficha de la app
                  </Button>
                ) : null}
              </div>
              {(row.fields ?? []).length ? (
                <dl className="grid grid-cols-[minmax(7rem,auto)_1fr] gap-x-3 gap-y-1.5 text-caption">
                  {(row.fields ?? []).map((f) => (
                    <div key={f.label} className="contents">
                      <dt className="text-muted-foreground">{f.label}</dt>
                      <dd className="min-w-0 break-words">
                        {/^https?:\/\//.test(f.value) ? (
                          <a href={f.value} target="_blank" rel="noreferrer" className="underline">{f.value}</a>
                        ) : (
                          f.value
                        )}
                      </dd>
                    </div>
                  ))}
                </dl>
              ) : null}
              <LinkList title="Relacionado con" links={row.links ?? []} dbs={dbs} onOpen={onOpen} />
              <LinkList title="Aparece en" links={q.data?.inbound ?? []} dbs={dbs} onOpen={onOpen} />
              {(row.links ?? []).length === 0 && (q.data?.inbound ?? []).length === 0 ? (
                <p className="text-caption text-muted-foreground">Sin relaciones: la nota no enlaza con otra ficha ni otra la enlaza.</p>
              ) : null}
              {q.data?.body ? (
                <div className="space-y-1 border-t pt-3">
                  <div className="text-caption font-medium">Nota</div>
                  <Markdown mode="minimal" className="text-caption">{q.data.body}</Markdown>
                </div>
              ) : null}
              {row.path ? (
                <p className="text-micro text-muted-foreground">
                  <code>{row.path}</code> · la carpeta es la fuente; esta vista no escribe.
                </p>
              ) : (
                <p className="text-micro text-muted-foreground">Solo existe en la app.</p>
              )}
            </div>
          </>
        ) : null}
      </SheetContent>
    </Sheet>
  );
}

// --- Page ---------------------------------------------------------------------------

export function BasesDatosPage({ db }: { db?: string }) {
  const wsId = useWorkspaceId();
  const list = useQuery(bizDatabasesOptions(wsId));
  const dbs = list.data?.databases ?? [];
  const current = db ? dbs.find((d) => d.key === db) : undefined;
  return (
    <EmpresaShell icon={Database} title={current ? `Bases de datos · ${current.name}` : "Bases de datos"}>
      {list.isLoading ? (
        <div className={cn(PAGE_GUTTER, "py-4")}><LoadingBlock rows={6} /></div>
      ) : list.error ? (
        <div className={cn(PAGE_GUTTER, "py-4")}><ErrorBlock error={list.error} retry={() => void list.refetch()} /></div>
      ) : db ? (
        <DatabaseView key={db} dbKey={db} dbs={dbs} />
      ) : (
        <DatabasesIndex dbs={dbs} />
      )}
    </EmpresaShell>
  );
}

/** Route entry: `/{slug}/bases` and `/{slug}/bases/{db}`. */
export function BasesDatosRoute() {
  const nav = useNavigation();
  const db = nav.pathname.split("/").filter(Boolean)[2];
  return <BasesDatosPage db={db ? decodeURIComponent(db) : undefined} />;
}
