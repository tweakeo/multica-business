#!/usr/bin/env node
// Registers the invoices of 4 · Finanzas/Fiscal and imports the statements of
// Registros/importar (run through scripts/tls/the-last.sh registros <datos.json>
// [--apply]). Without --apply it only reports what it would do.
//
// <datos.json> holds what was read from each original (never committed: it is
// real data): {facturas: [{registro_id, tipo: emitida|recibida, documento
// (relative to Registros/), fecha, numero, tercero, moneda, base, iva,
// retencion, total, estado, fuente, app}], explicados: [...], cuenta: {nombre,
// saldo, fecha_saldo, evidencia}, ignorar: [{id, motivo}]}.
//
//   - A copy of Registros/ goes first to …/TLS/The Last/copias/; nothing is
//     ever deleted from the folder.
//   - An invoice whose number, date, party, base, IVA and total were all read
//     («app»: true) is recorded with invoice.register: the app writes its row
//     and its note. Any other one only gets its register row, with the
//     unknown fields empty and «por revisar» in fuente.
//   - Each importar/*.csv goes through bank.import (re-importing inserts
//     nothing). A proposed match is confirmed only when the amount is exact
//     and the dates are at most 3 days apart; the rest stay proposed.
//   - Finally the projection is compared with the folder (rebuild preview).
// Reports go to ~/Library/Application Support/TLS/The Last/informes/.

import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync, renameSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const API = process.env.TLS_API ?? "http://127.0.0.1:8090";
const EMAIL = process.env.TLS_EMAIL ?? "direccion@tls.local";
const CODE = process.env.TLS_CODE;
const FOLDER = process.env.COMPANY_FOLDER;
const STATE = join(homedir(), "Library", "Application Support", "TLS", "The Last");
const REPORTS = join(STATE, "informes");
const [datosPath, ...flags] = process.argv.slice(2);
const APPLY = flags.includes("--apply");
if (!CODE || !FOLDER || !datosPath) throw new Error("Uso: the-last.sh registros <datos.json> [--apply]");
const datos = JSON.parse(readFileSync(datosPath, "utf8"));
const REG = join(FOLDER, "4 · Finanzas", "Registros");

let token = "";
let ws = "";
async function http(method, path, body) {
  const res = await fetch(API + path, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(ws ? { "X-Workspace-ID": ws } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${text}`);
  return text ? JSON.parse(text) : null;
}
const run = async (action, payload) => {
  const r = await http("POST", `/api/biz/run/${action}`, payload);
  if (r?.status === "approval_required") throw new Error(`${action} pide aprobación`);
  return r?.result ?? r;
};
const list = (entity, q = "") => http("GET", `/api/biz/list/${entity}?limit=1999${q}`);
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const save = (name, data) => {
  mkdirSync(REPORTS, { recursive: true });
  const p = join(REPORTS, `${stamp}-${name}.json`);
  writeFileSync(p, JSON.stringify(data, null, 2));
  return p;
};

// --- Registers: the same CSV dialect as the app (comma, quotes when needed) ---
const HEADERS = {
  "emitidas.csv": ["id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento", "documento", "ambito", "proyecto_id", "estado_emision", "fuente"],
  "recibidas.csv": ["id", "fecha_documento", "tercero", "numero_documento", "moneda", "total_documento", "documento", "ambito", "proyecto_id", "estado_revision", "fuente"],
};
function parseCSV(text) {
  const rows = [];
  let row = [], field = "", quoted = false;
  text = text.replace(/^﻿/, "");
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"' && text[i + 1] === '"') (field += '"'), i++;
      else if (c === '"') quoted = false;
      else field += c;
    } else if (c === '"') quoted = true;
    else if (c === ",") row.push(field), (field = "");
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field), rows.push(row), (row = []), (field = "");
    } else field += c;
  }
  if (field !== "" || row.length) row.push(field), rows.push(row);
  return rows.filter((r) => r.length > 1 || r[0] !== "");
}
const cell = (v) => (/[",\n\r]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v);
/** Appends rows whose id is not there yet; every existing row stays as it is. */
function appendRows(file, rows) {
  const p = join(REG, file);
  const all = existsSync(p) ? parseCSV(readFileSync(p, "utf8")) : [HEADERS[file]];
  const header = all[0];
  const ids = new Set(all.slice(1).map((r) => r[header.indexOf("id")]));
  const fresh = rows.filter((r) => !ids.has(r.id));
  if (!fresh.length) return 0;
  const lines = [...all, ...fresh.map((r) => header.map((h) => r[h] ?? ""))].map((r) => r.map(cell).join(","));
  writeFileSync(p + ".tmp", lines.join("\n") + "\n");
  renameSync(p + ".tmp", p);
  return fresh.length;
}

const minor = (v) => (v === "" || v == null ? null : Math.round(Number(v) * 100));
const DAY = 86_400_000;

// --- Session ---------------------------------------------------------------
// One code a minute: after a recent run, wait for the next one.
for (let i = 0; ; i++) {
  try {
    await http("POST", "/auth/send-code", { email: EMAIL });
    break;
  } catch (e) {
    if (!String(e.message).includes("→ 429") || i >= 12) throw e;
    await new Promise((r) => setTimeout(r, 10_000));
  }
}
token = (await http("POST", "/auth/verify-code", { email: EMAIL, code: CODE })).token;
const workspaces = await http("GET", "/api/workspaces");
ws = (workspaces.workspaces ?? workspaces).find((x) => x.slug === "the-last")?.id;
if (!ws) throw new Error("No existe la empresa the-last: ejecuta primero the-last.sh setup");

const report = { modo: APPLY ? "aplicar" : "vista previa", facturas: {}, movimientos: {}, conciliacion: {}, explicados: datos.explicados ?? [] };
const app = datos.facturas.filter((f) => f.app);
const onlyRow = datos.facturas.filter((f) => !f.app);
report.facturas = { total: datos.facturas.length, en_la_app: app.length, solo_registro: onlyRow.length, por_revisar: datos.facturas.filter((f) => f.por_revisar).length };

if (!APPLY) {
  console.log("· vista previa:", save("registros-vista-previa", report), report.facturas);
  process.exit(0);
}

// 1. Copy of Registros/ before touching it.
const copy = join(STATE, "copias", `Registros-${stamp}`);
mkdirSync(join(STATE, "copias"), { recursive: true });
cpSync(REG, copy, { recursive: true });
report.copia = copy;
console.log("· copia de Registros/ en", copy);

// 2. Invoices.
const errors = [];
for (const f of app) {
  try {
    await run("invoice.register", {
      direction: f.tipo === "emitida" ? "issued" : "received",
      number: f.numero, issue_date: f.fecha, party: f.tercero, concept: f.concepto, currency: f.moneda,
      base_minor: minor(f.base), tax_minor: minor(f.iva), withholding_minor: minor(f.retencion) ?? 0, total_minor: minor(f.total),
      document_path: join("4 · Finanzas", "Registros", f.documento), // join resolves the "../"
      registro_id: f.registro_id, ambito: "The Last", fuente: f.fuente,
    });
  } catch (e) {
    errors.push({ registro_id: f.registro_id, error: String(e.message ?? e) });
    onlyRow.push(f); // still gets its row
  }
}
// The app writes its rows from its journal, a moment later. Appending at the
// same time would race it, so wait for them; one still missing afterwards is
// written here with the same content.
const rowIds = () => new Set(["emitidas.csv", "recibidas.csv"].flatMap((f) => parseCSV(readFileSync(join(REG, f), "utf8")).slice(1).map((r) => r[0])));
for (let i = 0; i < 30 && app.some((f) => !rowIds().has(f.registro_id)); i++) await new Promise((r) => setTimeout(r, 1000));
const missing = app.filter((f) => !rowIds().has(f.registro_id) && !onlyRow.includes(f));
if (missing.length) report.facturas.filas_repuestas = missing.map((f) => f.registro_id);
onlyRow.push(...missing);
const toRow = (f) => ({
  id: f.registro_id, fecha_documento: f.fecha, tercero: f.tercero, numero_documento: f.numero, moneda: f.moneda,
  total_documento: f.total, documento: f.documento, ambito: "The Last", proyecto_id: "",
  ...(f.tipo === "emitida" ? { estado_emision: f.estado } : { estado_revision: "pendiente" }), fuente: f.fuente,
});
report.facturas.filas_escritas = {
  "emitidas.csv": appendRows("emitidas.csv", onlyRow.filter((f) => f.tipo === "emitida").map(toRow)),
  "recibidas.csv": appendRows("recibidas.csv", onlyRow.filter((f) => f.tipo === "recibida").map(toRow)),
};
report.facturas.errores = errors;
console.log("· facturas:", report.facturas);

// 3. Account and statements.
const c = datos.cuenta;
let account = (await list("account")).find((a) => a.name === c.nombre);
if (!account) {
  account = await run("account.create", { name: c.nombre, iban_masked: c.iban ?? "", opening_balance_minor: minor(c.saldo), opening_on: c.fecha_saldo || "" });
  report.cuenta = { creada: c.nombre, saldo: c.saldo, fecha: c.fecha_saldo, evidencia: c.evidencia };
}
const dir = join(REG, "importar");
for (const name of readdirSync(dir).filter((n) => n.toLowerCase().endsWith(".csv")).sort()) {
  const r = await run("bank.import", { account_id: account.id, batch: `importar/${name}`, csv: readFileSync(join(dir, name), "utf8") });
  report.movimientos[name] = { insertados: r.inserted, ya_estaban: r.duplicates, no_importables: r.skipped, errores: r.errors, propuestas: r.proposed_matches };
}
console.log("· movimientos:", Object.fromEntries(Object.entries(report.movimientos).map(([k, v]) => [k, { insertados: v.insertados, ya_estaban: v.ya_estaban, no_importables: v.no_importables.length }])));

let movements = await list("movement");
for (const x of datos.ignorar ?? []) {
  const m = movements.find((m) => m.notes?.startsWith(`Fila ${x.id} `));
  if (m && m.status !== "ignored" && m.status !== "reconciled") await run("movement.classify", { id: m.id, ignore: true, notes: `${m.notes} · ${x.motivo}` });
}

// 4. Confirm only exact matches: same amount and at most 3 days apart.
const invoices = new Map((await list("invoice")).map((i) => [i.id, i]));
movements = await list("movement");
const confirmed = [], proposed = [];
for (const m of movements.filter((m) => m.status === "proposed")) {
  const inv = invoices.get(m.invoice_id);
  const days = inv ? Math.abs(new Date(m.booked_on.slice(0, 10)) - new Date(inv.issue_date.slice(0, 10))) / DAY : Infinity;
  const exact = inv && Math.abs(Number(m.amount_minor)) === Number(inv.total_minor) - Number(inv.paid_minor) && days <= 3;
  const line = { movimiento: `${m.booked_on.slice(0, 10)} ${m.description} ${(Number(m.amount_minor) / 100).toFixed(2)}`, factura: inv?.number, dias: days, motivo: m.match_reason };
  if (!exact) {
    proposed.push(line);
    continue;
  }
  await run("payment.confirm", { invoice_id: inv.id, movement_id: m.id, evidence: `Movimiento ${m.booked_on.slice(0, 10)} · ${m.notes || m.description}` });
  confirmed.push(line);
}
report.conciliacion = { confirmadas: confirmed, propuestas: proposed };
console.log(`· conciliación: ${confirmed.length} confirmadas, ${proposed.length} propuestas para revisar`);

// 5. The evidence of a confirmed payment is the note of its bank movement (a
// file, as Esquema.md asks), not a sentence. pagos.csv is the payment's home:
// the cell is fixed there and the projection follows the folder.
const findNote = (dir, suffix) => {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) {
      const hit = findNote(p, suffix);
      if (hit) return hit;
    } else if (e.name.endsWith(suffix)) return p;
  }
  return "";
};
const payments = new Map((await list("payment")).map((p) => [p.id, p]));
for (let i = 0; i < 30 && [...payments.values()].some((p) => p.movement_id && !findNote(join(REG, "Bancos"), `--${p.movement_id.slice(0, 8)}.md`)); i++) await new Promise((r) => setTimeout(r, 1000));
const pagosPath = join(REG, "pagos.csv");
const pagos = parseCSV(readFileSync(pagosPath, "utf8"));
const [ci, ce] = ["id", "evidencia"].map((h) => pagos[0].indexOf(h));
let evidencias = 0;
for (const row of pagos.slice(1)) {
  const pay = payments.get(row[ci]);
  if (!pay?.movement_id || (row[ce] && existsSync(join(REG, row[ce])))) continue;
  const note = findNote(join(REG, "Bancos"), `--${pay.movement_id.slice(0, 8)}.md`);
  if (note) (row[ce] = note.slice(REG.length + 1)), evidencias++;
}
if (evidencias) {
  writeFileSync(pagosPath + ".tmp", pagos.map((r) => r.map(cell).join(",")).join("\n") + "\n");
  renameSync(pagosPath + ".tmp", pagosPath);
  await http("POST", "/api/biz/folder/rebuild", { apply: true });
}
report.conciliacion.evidencias_enlazadas = evidencias;

// 6. Projection against the folder.
const after = await http("POST", "/api/biz/folder/rebuild", { apply: false });
report.reconstruccion = {
  iguales: after.equal, nuevos_en_bd: after.missing_in_db.length, distintos: after.different.length, errores: after.parse_errors.length,
  registros: { vinculados: after.registros?.vinculados, sin_vincular: after.registros?.sin_vincular?.length, diferencias: after.registros?.diferencias?.length },
};
save("registros-reconstruccion", after);
console.log("· reconstrucción (vista previa):", report.reconstruccion);
console.log("· informe:", save("registros", report));
