#!/usr/bin/env node
// Real dates of the Finanzas documents whose name does not carry one (run
// through scripts/tls/the-last.sh fechas). The app reads the result from
// "4 · Finanzas/Fechas de documentos.csv" (ruta,fecha,fuente,nota); the
// originals are never renamed or touched.
//
// Order: a labelled date in the PDF text ("Fecha", "Emitida", "Date of
// issue"…), a date in the name in any common Spanish form (17.06.25,
// "20 de mayo de 2025", "Urba gestores abril25"…), any date in the text, OCR
// of scanned PDFs and images (macOS Vision), and last the PDF/Office creation
// metadata. Rows with fuente "manual" are a person's and are kept as they are.
//
//   node the-last-fechas.mjs            # preview: prints what would change
//   node the-last-fechas.mjs --apply    # writes the CSV (copy of the old one first)

import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";

const ROOT = process.env.COMPANY_FOLDER;
if (!ROOT) throw new Error("Lánzalo con scripts/tls/the-last.sh fechas (necesita TLS_COMPANY_FOLDER)");
const APPLY = process.argv.includes("--apply");
const FIN = JSON.parse(readFileSync(join(ROOT, ".tls/layout.json"), "utf8")).areas?.finanzas ?? "4 · Finanzas";
const CSV = join(ROOT, FIN, "Fechas de documentos.csv");
const GROUPS = ["Fiscal", "Gestoría", "Trámites", "Registros"];
const PACKAGES = new Set([".numbers", ".pages", ".key", ".app", ".rtfd", ".bundle"]);
const STATE = join(homedir(), "Library/Application Support/TLS");
const TODAY = new Date().toISOString().slice(0, 10);

// --- Dates in text ----------------------------------------------------------------

const MONTHS = {
  enero: 1, ene: 1, january: 1, jan: 1,
  febrero: 2, feb: 2, february: 2,
  marzo: 3, mar: 3, march: 3,
  abril: 4, abr: 4, april: 4, apr: 4,
  mayo: 5, may: 5,
  junio: 6, jun: 6, june: 6,
  julio: 7, jul: 7, july: 7,
  agosto: 8, ago: 8, august: 8, aug: 8,
  septiembre: 9, setiembre: 9, sept: 9, sep: 9, september: 9,
  octubre: 10, oct: 10, october: 10,
  noviembre: 11, nov: 11, november: 11,
  diciembre: 12, dic: 12, december: 12, dec: 12,
};
const MON = Object.keys(MONTHS).sort((a, b) => b.length - a.length).join("|");
const pad = (n) => String(n).padStart(2, "0");
const year4 = (y) => (y.length === 2 ? 2000 + Number(y) : Number(y));

function valid(y, m, d) {
  if (y < 2023 || m < 1 || m > 12 || d < 1 || d > 31) return "";
  const dt = new Date(Date.UTC(y, m - 1, d));
  if (dt.getUTCMonth() !== m - 1) return "";
  const iso = `${y}-${pad(m)}-${pad(d)}`;
  return iso <= TODAY ? iso : "";
}

const PATTERNS = [
  [new RegExp(`(?<!\\d)(20\\d\\d)[-/.](\\d{1,2})[-/.](\\d{1,2})(?!\\d)`, "g"), (m) => valid(+m[1], +m[2], +m[3])],
  [new RegExp(`(?<!\\d)(\\d{1,2})[-/.](\\d{1,2})[-/.](20\\d\\d|\\d\\d)(?!\\d)`, "g"), (m) => valid(year4(m[3]), +m[2], +m[1])],
  [new RegExp(`(?<!\\d)(\\d{1,2})(?:º)?[\\s_]*(?:de[\\s_]+)?(${MON})\\.?,?[\\s_]*(?:de[\\s_]+|del[\\s_]+)?(20\\d\\d|\\d\\d)(?!\\d)`, "gi"), (m) => valid(year4(m[3]), MONTHS[m[2].toLowerCase()], +m[1])],
  [new RegExp(`\\b(${MON})\\.?\\s+(\\d{1,2}),?\\s+(20\\d\\d)(?!\\d)`, "gi"), (m) => valid(+m[3], MONTHS[m[1].toLowerCase()], +m[2])],
];

/** All dates in s, in reading order: [{date, index}]. */
function datesIn(s) {
  const out = [];
  for (const [re, fn] of PATTERNS) {
    for (const m of s.matchAll(re)) {
      const date = fn(m);
      if (date) out.push({ date, index: m.index });
    }
  }
  return out.sort((a, b) => a.index - b.index);
}

// Labels of the document's own date, strongest first; a date that follows
// "Fecha de situación", "vencimiento" or "válido hasta" is not that.
const LABELS = [
  /(fecha(?:\s+de)?(?:\s+la)?\s+(?:factura|emisi[oó]n|expedici[oó]n|documento|ingreso|presentaci[oó]n|resoluci[oó]n|solicitud)|fecha\s*:|fecha\s*\n|fecha[ \t]+(?=\d)|emitid[ao](?:\s+con\s+fecha)?|date of issue|invoice date|date issued|issue date|date paid|f\.\s*operaci[oó]n)/gi,
  /(fecha\s+de\s+(?:iniciaci[oó]n|efectos?|operaci[oó]n|alta)|efectos\s*:)/gi,
];
const NOT_DOC_DATE = /nacimiento|nacido|vencimiento|caducidad|due|validez|hasta la fecha|comprobad/i;

/** The first date that follows a label such as "Fecha:" or "Date of issue". */
function labelledDate(text) {
  for (const re of LABELS) {
    for (const m of text.matchAll(re)) {
      const around = text.slice(Math.max(0, m.index - 25), m.index + m[0].length + 10);
      if (NOT_DOC_DATE.test(around)) continue;
      const win = text.slice(m.index + m[0].length, m.index + m[0].length + 120);
      const d = datesIn(win)[0];
      if (d) return d.date;
    }
  }
  return "";
}

/** 02/11/2025 read as 2 November when the name says 11 February: US order. */
const swapped = (a, b) => a.length === 10 && b.length === 10 && a.slice(0, 4) === b.slice(0, 4) && a.slice(5, 7) === b.slice(8, 10) && a.slice(8, 10) === b.slice(5, 7);

/** A date in the file name; a month name alone takes the year from the path. */
function nameDate(name, rel) {
  const base = name.replace(/\.[^.]+$/, "").replace(/_/g, " ").replace(/(20\d\d)Y-(\d\d)M-(\d\d)D/g, "$1-$2-$3");
  const d = datesIn(base)[0];
  if (d) return { date: d.date };
  const mm = base.match(new RegExp(`(?:^|[\\s\\-])(${MON})\\.?\\s?(20\\d\\d|\\d\\d)?\\b`, "i"));
  if (mm) {
    const y = mm[2] ? year4(mm[2]) : Number(rel.match(/(?:^|\/)(20\d\d)(?:\/| )/)?.[1] ?? 0);
    if (y >= 2023) return { date: `${y}-${pad(MONTHS[mm[1].toLowerCase()])}`, nota: "solo el mes" };
  }
  return null;
}

// --- Reading the documents ------------------------------------------------------

const run = (cmd, args) => {
  try {
    return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"], maxBuffer: 32 << 20, timeout: 60000 });
  } catch {
    return "";
  }
};

let ocrBin = "";
function ocr(file) {
  if (ocrBin === null) return "";
  if (!ocrBin) {
    const src = join(dirname(new URL(import.meta.url).pathname), "tls-ocr.swift");
    const bin = join(STATE, "bin", "tls-ocr");
    if (!existsSync(bin) || statSync(bin).mtimeMs < statSync(src).mtimeMs) {
      mkdirSync(dirname(bin), { recursive: true });
      run("swiftc", ["-O", "-o", bin, src]);
    }
    ocrBin = existsSync(bin) ? bin : null;
    if (!ocrBin) return "";
  }
  return run(ocrBin, [file]);
}

function pdfMetaDate(file) {
  const info = run("pdfinfo", ["-isodates", file]);
  const m = info.match(/^CreationDate:\s+(\d{4}-\d\d-\d\d)/m);
  return m && m[1] >= "2023-01-01" && m[1] <= TODAY ? m[1] : "";
}

function officeMetaDate(file) {
  const xml = run("unzip", ["-p", file, "docProps/core.xml"]);
  const m = xml.match(/<dcterms:created[^>]*>(\d{4}-\d\d-\d\d)/);
  return m && m[1] >= "2023-01-01" && m[1] <= TODAY ? m[1] : "";
}

/** {fecha, fuente, nota} for one document, or null when nothing is readable. */
function resolve(file, rel, name) {
  const ext = name.toLowerCase().match(/\.[^.]+$/)?.[0] ?? "";
  const byName = nameDate(name, rel);
  if (ext === ".pdf") {
    const text = run("pdftotext", ["-l", "3", "-enc", "UTF-8", file, "-"]);
    const labelled = labelledDate(text);
    if (labelled && byName && swapped(labelled, byName.date)) return { fecha: byName.date, fuente: "documento", nota: "fecha en formato de EE. UU. (mes/día), confirmada por el nombre" };
    if (labelled) return { fecha: labelled, fuente: "documento", nota: byName && byName.date.slice(0, 7) !== labelled.slice(0, 7) ? `el nombre dice ${byName.date}` : "" };
    if (byName) return { fecha: byName.date, fuente: "nombre", nota: byName.nota ?? "" };
    const any = datesIn(text)[0];
    if (any) return { fecha: any.date, fuente: "documento", nota: "primera fecha del texto" };
    if (text.trim().length < 20) {
      const dir = mkdtempSync(join(tmpdir(), "tls-ocr-"));
      run("pdftoppm", ["-r", "200", "-f", "1", "-l", "1", "-png", file, join(dir, "p")]);
      const img = readdirSync(dir).find((f) => f.startsWith("p") && f.endsWith(".png"));
      if (img) {
        const t = ocr(join(dir, img));
        const d = labelledDate(t) || datesIn(t)[0]?.date;
        rmSync(dir, { recursive: true, force: true });
        if (d) return { fecha: d, fuente: "documento", nota: "leída del escaneo (OCR)" };
      }
      rmSync(dir, { recursive: true, force: true });
    }
    const meta = pdfMetaDate(file);
    if (meta) return { fecha: meta, fuente: "metadatos", nota: "fecha de creación del PDF; el texto no trae fecha" };
    return null;
  }
  if (byName) return { fecha: byName.date, fuente: "nombre", nota: byName.nota ?? "" };
  const inFolder = datesIn(rel.split("/").slice(0, -1).join("/"))[0];
  if ([".png", ".jpg", ".jpeg", ".heic"].includes(ext)) {
    const t = ocr(file);
    const d = labelledDate(t) || datesIn(t)[0]?.date;
    if (d) return { fecha: d, fuente: "documento", nota: "leída de la imagen (OCR)" };
  }
  if ([".xlsx", ".docx", ".pptx"].includes(ext)) {
    const meta = officeMetaDate(file);
    if (meta) return { fecha: meta, fuente: "metadatos", nota: "fecha de creación del documento" };
  }
  if (inFolder && ext !== ".md") return { fecha: inFolder.date, fuente: "nombre", nota: "fecha del nombre de la carpeta" };
  return null;
}

// The app takes the date from the name with these two patterns (library.go);
// only the documents they miss need a row.
const APP_DAY = /(20\d\d)[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])/;
const APP_MONTH = /(20\d\d)[-_.](0[1-9]|1[0-2])\b/;

function* documents() {
  for (const g of GROUPS) {
    const stack = [join(ROOT, FIN, g)];
    while (stack.length) {
      const dir = stack.pop();
      let entries = [];
      try {
        entries = readdirSync(dir, { withFileTypes: true });
      } catch {
        continue;
      }
      for (const e of entries) {
        const name = e.name;
        const full = join(dir, name);
        const ext = name.toLowerCase().match(/\.[^.]+$/)?.[0] ?? "";
        if (e.isDirectory() && !PACKAGES.has(ext)) {
          if (!name.startsWith(".")) stack.push(full);
          continue;
        }
        if (name === ".DS_Store" || name.startsWith("~$") || (name.startsWith(".") && !name.endsWith(".icloud"))) continue;
        yield { full, rel: relative(ROOT, full).split("\\").join("/"), name, cloud: name.endsWith(".icloud") };
      }
    }
  }
}

// --- CSV ------------------------------------------------------------------------------

function parseCSV(text) {
  const rows = [];
  let row = [], cell = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') (cell += '"'), i++;
      else if (c === '"') q = false;
      else cell += c;
    } else if (c === '"') q = true;
    else if (c === ",") row.push(cell), (cell = "");
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cell), rows.push(row), (row = []), (cell = "");
    } else cell += c;
  }
  if (cell || row.length) row.push(cell), rows.push(row);
  return rows.filter((r) => r.some((x) => x !== ""));
}
const esc = (s) => (/[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s);

const HEADER = ["ruta", "fecha", "fuente", "nota"];
const old = new Map();
if (existsSync(CSV)) {
  const rows = parseCSV(readFileSync(CSV, "utf8").replace(/^\uFEFF/, ""));
  const h = rows[0] ?? [];
  for (const r of rows.slice(1)) {
    const o = Object.fromEntries(h.map((k, i) => [k, r[i] ?? ""]));
    if (o.ruta) old.set(o.ruta, o);
  }
}

const rows = new Map();
const unread = [];
for (const d of documents()) {
  const kept = old.get(d.rel);
  if (kept && kept.fuente === "manual") {
    rows.set(d.rel, kept);
    continue;
  }
  if (APP_DAY.test(d.name) || APP_MONTH.test(d.name)) continue;
  if (d.cloud) {
    unread.push(`${d.rel} (en iCloud, sin descargar)`);
    continue;
  }
  const r = resolve(d.full, d.rel, d.name);
  if (r) rows.set(d.rel, { ruta: d.rel, ...r });
  else unread.push(d.rel);
}
for (const [k, v] of old) if (v.fuente === "manual" && !rows.has(k)) rows.set(k, v); // a moved file keeps its manual row

const sorted = [...rows.values()].sort((a, b) => a.ruta.localeCompare(b.ruta, "es"));
const out = [HEADER.join(","), ...sorted.map((r) => HEADER.map((k) => esc(r[k] ?? "")).join(","))].join("\n") + "\n";
const changed = !existsSync(CSV) || readFileSync(CSV, "utf8") !== out;
const bySource = sorted.reduce((a, r) => ((a[r.fuente] = (a[r.fuente] ?? 0) + 1), a), {});

console.log(JSON.stringify({ csv: relative(ROOT, CSV), filas: sorted.length, por_fuente: bySource, sin_fecha_legible: unread, cambia: changed, modo: APPLY ? "aplicar" : "vista previa" }, null, 1));
if (APPLY && changed) {
  if (existsSync(CSV)) {
    const bak = join(homedir(), "Backups", `tls-fechas-${new Date().toISOString().replace(/[:.]/g, "-")}.csv`);
    mkdirSync(dirname(bak), { recursive: true });
    copyFileSync(CSV, bak);
  }
  const tmp = CSV + ".tmp";
  writeFileSync(tmp, out);
  renameSync(tmp, CSV);
}
