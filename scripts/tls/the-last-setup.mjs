#!/usr/bin/env node
// First-time setup of the production company "The Last" (run through
// scripts/tls/the-last.sh setup, which starts its own stack): local user,
// workspace, company folder in iCloud, then the projection is rebuilt from
// the folder and compared field by field. Reports go to
// ~/Library/Application Support/TLS/The Last/informes/.
//
// Nothing is written into the folder except .tls/escritor.json (the writer
// claim): no export, no adoption of hand-made notes.

import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const API = process.env.TLS_API ?? "http://127.0.0.1:8090";
const EMAIL = process.env.TLS_EMAIL ?? "direccion@tls.local";
const CODE = process.env.TLS_CODE;
const FOLDER = process.env.COMPANY_FOLDER;
const SLUG = "the-last";
const REPORTS = join(homedir(), "Library", "Application Support", "TLS", "The Last", "informes");
if (!CODE || !FOLDER) throw new Error("Lánzalo con scripts/tls/the-last.sh setup");

let token = "";
let ws = "";
async function http(method, path, body) {
  const res = await fetch(API + path, {
    method,
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(ws ? { "X-Workspace-ID": ws } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status}: ${text}`);
  return data;
}
const run = (action, payload) => http("POST", `/api/biz/run/${action}`, payload);
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const save = (name, data) => {
  mkdirSync(REPORTS, { recursive: true });
  const p = join(REPORTS, `${stamp}-${name}.json`);
  writeFileSync(p, JSON.stringify(data, null, 2));
  return p;
};
const summary = (r) => ({
  ficheros: r.files,
  iguales: r.equal,
  nuevos_en_bd: r.missing_in_db.length,
  distintos: r.different.length,
  ids_duplicados: r.duplicate_ids.length,
  errores: r.parse_errors.length,
  aplicados: r.applied,
  propuestas: r.proposals.length,
  registros: { vinculados: r.registros?.vinculados, sin_vincular: r.registros?.sin_vincular?.length },
});

await http("POST", "/auth/send-code", { email: EMAIL });
token = (await http("POST", "/auth/verify-code", { email: EMAIL, code: CODE })).token;
await http("PATCH", "/api/me", { name: process.env.TLS_NAME ?? "Dirección" }).catch(() => {});
// Local single-user install: no onboarding chat (it would ask for a runtime).
await http("POST", "/api/me/onboarding/complete", {});

const workspaces = await http("GET", "/api/workspaces");
let w = (workspaces.workspaces ?? workspaces).find((x) => x.slug === SLUG);
if (!w) {
  w = await http("POST", "/api/workspaces", {
    name: "The Last",
    slug: SLUG,
    issue_prefix: "TL",
    description: "Empresa con los datos en su carpeta (TLS_COMPANY_FOLDER).",
  });
  console.log("· workspace creado", w.id);
}
ws = w.id;
await http("POST", "/api/biz/bootstrap", {});
for (const [key, value] of Object.entries({ company_folder: FOLDER, mode: "produccion", import_mode: true })) {
  await run("settings.set", { key, value });
}

const status = await http("GET", "/api/biz/folder/status");
console.log("· estado de la carpeta:", save("estado", status));
const before = await http("POST", "/api/biz/folder/rebuild", { apply: false });
console.log("· vista previa:", save("vista-previa", before), summary(before));
const applied = await http("POST", "/api/biz/folder/rebuild", { apply: true });
console.log("· reconstrucción:", save("reconstruccion", applied), summary(applied));
const after = await http("POST", "/api/biz/folder/rebuild", { apply: false });
console.log("· comparación final:", save("comparacion", after), summary(after));
console.log(`Workspace ${SLUG} (${ws}) · escritor:`, JSON.stringify((await http("GET", "/api/biz/folder/status")).escritor));
