#!/usr/bin/env node
// Imports the lines a person wrote in 1 · Dirección/Decisiones.md (run
// through scripts/tls/the-last.sh decisiones). The only change in the folder
// is the id mark appended to each unmarked line; the visible text is kept
// byte for byte. Then the projection is rebuilt from the folder. Reports go
// to ~/Library/Application Support/TLS/The Last/informes/.

import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const API = process.env.TLS_API ?? "http://127.0.0.1:8090";
const EMAIL = process.env.TLS_EMAIL ?? "direccion@tls.local";
const CODE = process.env.TLS_CODE;
const REPORTS = join(homedir(), "Library", "Application Support", "TLS", "The Last", "informes");
if (!CODE) throw new Error("Lánzalo con scripts/tls/the-last.sh decisiones");

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
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const save = (name, data) => {
  mkdirSync(REPORTS, { recursive: true });
  const p = join(REPORTS, `${stamp}-${name}.json`);
  writeFileSync(p, JSON.stringify(data, null, 2));
  return p;
};

await http("POST", "/auth/send-code", { email: EMAIL });
token = (await http("POST", "/auth/verify-code", { email: EMAIL, code: CODE })).token;
const workspaces = await http("GET", "/api/workspaces");
ws = (workspaces.workspaces ?? workspaces).find((x) => x.slug === "the-last")?.id;
if (!ws) throw new Error("No existe la empresa the-last: ejecuta primero the-last.sh setup");

const preview = await http("POST", "/api/biz/folder/adopt", { apply: false, types: ["decision"] });
const lines = preview.proposals.filter((p) => p.type === "decision");
console.log(`· ${lines.length} líneas de decisiones sin marca:`, save("decisiones-vista-previa", lines));
const applied = await http("POST", "/api/biz/folder/adopt", { apply: true, types: ["decision"] });
console.log(`· marcadas: ${applied.adopted}`, applied.parse_errors.length ? applied.parse_errors : "");
const rebuild = await http("POST", "/api/biz/folder/rebuild", { apply: true });
const after = await http("POST", "/api/biz/folder/rebuild", { apply: false });
const decisions = (r) => [...r.different, ...r.missing_in_db].filter((d) => d.type === "decision").length;
console.log(`· reconstrucción: ${rebuild.applied} aplicados · después: ${after.equal} iguales, ${decisions(after)} decisiones distintas, ${after.parse_errors.length} errores`, save("decisiones-reconstruccion", after));
