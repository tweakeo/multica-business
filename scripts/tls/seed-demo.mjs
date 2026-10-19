#!/usr/bin/env node
// Builds the fictitious demo company "Asesoría Ribera (DEMO)" through the
// real APIs (Multica + /api/biz), so every record passes the same rules,
// events, audit and portable-folder writes as daily use.
//
//   node scripts/tls/seed-demo.mjs            # create (fails if it exists)
//   node scripts/tls/seed-demo.mjs --reset    # delete the demo workspace and folder first
//   add --offline to skip the live part (no agent runs, rituals off)
//
// Env: TLS_API (default http://localhost:8080), TLS_EMAIL (demo@tls.local),
// TLS_CODE (888888, dev only), TLS_DEMO_FOLDER, DATABASE_URL (date shifts).
// All people, companies, amounts and documents are invented.

import { execFileSync } from "node:child_process";
import { mkdirSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { AGENTS } from "./demo/agents.mjs";

const API = process.env.TLS_API ?? "http://localhost:8080";
const EMAIL = process.env.TLS_EMAIL ?? "demo@tls.local";
const CODE = process.env.TLS_CODE ?? "888888";
const FOLDER = process.env.TLS_DEMO_FOLDER ?? join(homedir(), "TLS Empresas", "DEMO - Asesoría Ribera");
const DB = process.env.DATABASE_URL ?? "postgres://multica:multica@localhost:5432/multica?sslmode=disable";
const PSQL = ["/opt/homebrew/opt/postgresql@17/bin/psql", "/opt/homebrew/bin/psql", "/usr/local/bin/psql"].find(existsSync) ?? "psql";
const SLUG = "asesoria-ribera-demo";
const RESET = process.argv.includes("--reset");
const OFFLINE = process.argv.includes("--offline");

let token = "";
let ws = "";
const log = (...a) => console.log("·", ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function http(method, path, body, { allow = [] } = {}) {
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
  let data;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = text;
  }
  if (!res.ok && !allow.includes(res.status)) {
    throw new Error(`${method} ${path} → ${res.status}: ${typeof data === "string" ? data : JSON.stringify(data)}`);
  }
  return data;
}

const run = async (action, payload) => {
  const r = await http("POST", `/api/biz/run/${action}`, payload);
  return r.result ?? r;
};
const list = (entity, q = "") => http("GET", `/api/biz/list/${entity}${q ? "?" + q : ""}`);
const sql = (query) => execFileSync(PSQL, [DB, "-Atc", query], { encoding: "utf8" }).trim();
const eur = (n) => Math.round(n * 100);
const iso = (d) => d.toISOString().slice(0, 10);
const TODAY = new Date(new Date().toISOString().slice(0, 10) + "T00:00:00Z");
const daysAgo = (n) => iso(new Date(TODAY.getTime() - n * 86400000));

async function waitFor(fn, label, timeoutMs = 60000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const v = await fn();
    if (v) return v;
    await http("POST", "/api/biz/events/process", {});
    await sleep(1000);
  }
  throw new Error(`timeout waiting for ${label}`);
}

// --- Documents -------------------------------------------------------------

function fakePdf(path, title, lines) {
  const text = [title, ...lines].map((l, i) => `BT /F1 ${i === 0 ? 14 : 10} Tf 50 ${780 - i * 18} Td (${l.replace(/[()\\]/g, "")}) Tj ET`).join("\n");
  const objs = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    `<< /Length ${text.length} >>\nstream\n${text}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let out = "%PDF-1.4\n";
  const offsets = [];
  objs.forEach((o, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${o}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n${offsets.map((o) => String(o).padStart(10, "0") + " 00000 n \n").join("")}`;
  out += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, out);
}

function writeStatic(rel, content) {
  const p = join(FOLDER, rel);
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, content);
}

// --- Main ------------------------------------------------------------------

async function main() {
  token = process.env.TLS_TOKEN ?? "";
  if (!token) {
    await http("POST", "/auth/send-code", { email: EMAIL });
    token = (await http("POST", "/auth/verify-code", { email: EMAIL, code: CODE })).token;
  }
  const me = await http("GET", "/api/me");
  log("sesión", me.email ?? EMAIL);

  const workspaces = await http("GET", "/api/workspaces");
  const existing = (workspaces.workspaces ?? workspaces).find((w) => w.slug === SLUG);
  if (existing) {
    if (!RESET) throw new Error(`La demo ya existe (${SLUG}). Usa --reset para recrearla.`);
    ws = "";
    await http("DELETE", `/api/workspaces/${existing.id}`);
    log("demo anterior eliminada");
  }
  if (RESET && existsSync(FOLDER)) rmSync(FOLDER, { recursive: true, force: true });

  const created = await http("POST", "/api/workspaces", {
    name: "Asesoría Ribera (DEMO)",
    slug: SLUG,
    issue_prefix: "RIB",
    description: "Empresa de demostración ficticia: gestoría con servicios de Renta y Trimestrales.",
    context:
      "Gestoría ficticia de Valencia. Servicios: Renta (IRPF particulares) y Trimestrales (303/111 de empresas y autónomos). Todo dato es inventado.",
  });
  ws = created.id;
  log("workspace", created.slug, ws);

  // Company settings. Import mode keeps history from triggering agents.
  await http("POST", "/api/biz/bootstrap", {});
  mkdirSync(FOLDER, { recursive: true });
  for (const [key, value] of Object.entries({
    import_mode: true,
    mode: "demo",
    company_folder: FOLDER,
    capacity_hours_per_day: 7,
    company_profile: {
      razon_social: "Asesoría Ribera Demo SL",
      nif: "B00000000 (ficticio)",
      sector: "Asesoría fiscal y contable",
      ciudad: "Valencia",
      personas: 2,
      servicios: ["Renta", "Trimestrales"],
      politica_arranque: "El proyecto arranca con el cobro confirmado; excepciones de crédito solo con decisión registrada.",
    },
  })) {
    await run("settings.set", { key, value });
  }

  // --- Service canvases: custom statuses + one workflow per service -------
  const status = async (key, name, category, color, description) =>
    http("POST", "/api/issue-statuses", { key, name, category, color, description }).catch((e) => {
      if (!String(e).includes("409")) throw e;
    });
  await status("renta_documentacion", "Documentación", "unstarted", "#a855f7", "Esperando documentación del cliente");
  await status("renta_preparacion", "Preparación", "started", "#3b82f6", "Preparando la declaración");
  await status("renta_revision", "Revisión con cliente", "started", "#f59e0b", "Resultado presentado al cliente para conformidad");
  await status("renta_presentacion", "Presentación de la renta", "started", "#10b981", "Lista para presentar por una persona");
  await status("trim_recogida", "Recogida de documentos", "unstarted", "#a855f7", "Facturas y extractos del trimestre");
  await status("trim_contabilizacion", "Contabilización", "started", "#3b82f6", "Registro y clasificación");
  await status("trim_conciliacion", "Conciliación", "started", "#06b6d4", "Bancos contra facturas");
  await status("trim_modelos", "Modelos y validación", "started", "#f59e0b", "Borradores de 303/111 y conformidad del cliente");
  await status("trim_presentacion", "Presentación de modelos", "started", "#10b981", "Presentar con certificado y archivar justificantes");

  const wfRenta = await http("POST", "/api/issue-workflows", {
    name: "Canvas · Renta",
    description: "Ciclo de una declaración de la renta",
    steps: ["todo", "renta_documentacion", "renta_preparacion", "renta_revision", "renta_presentacion", "done"].map((k) => ({ status_key: k })),
  });
  const wfTrim = await http("POST", "/api/issue-workflows", {
    name: "Canvas · Trimestrales",
    description: "Ciclo trimestral de impuestos de empresa",
    steps: ["todo", "trim_recogida", "trim_contabilizacion", "trim_conciliacion", "trim_modelos", "trim_presentacion", "done"].map((k) => ({ status_key: k })),
  });
  log("canvases", wfRenta.id, wfTrim.id);

  // --- Services, templates and offers (price history) ---------------------
  const renta = await run("service.save", {
    code: "RENTA",
    name: "Renta",
    description: "Declaración anual del IRPF de particulares: documentación, preparación, revisión con el cliente y presentación.",
    recurrence: "annual",
    workflow_id: wfRenta.id,
    template: {
      project_days: 10,
      done_when: "Declaración presentada, justificante archivado y enviado al cliente.",
      phases: [
        { name: "Onboarding", tasks: [
          { title: "Solicitar documentación al cliente", status: "renta_documentacion", offset: 0, duration: 2, assignee: "agent:entrega",
            description: "Datos fiscales, certificados de retenciones, deducciones (vivienda, donativos, alquiler) y cambios familiares.", acceptance: "Lista de documentos recibidos y pendientes en un comentario." },
        ] },
        { name: "Preparación", tasks: [
          { title: "Descargar datos fiscales y borrador de la AEAT", status: "renta_preparacion", offset: 2, duration: 1, assignee: "lead",
            description: "Requiere acceso con certificado o Cl@ve del cliente: lo hace una persona.", acceptance: "Datos fiscales guardados en la carpeta del cliente." },
          { title: "Preparar la declaración y comparar con el borrador", status: "renta_preparacion", offset: 3, duration: 3, assignee: "agent:entrega",
            description: "Revisar deducciones aplicables y diferencias con el borrador.", acceptance: "Resumen de diferencias y resultado previsto." },
        ] },
        { name: "Revisión", tasks: [
          { title: "Revisar el resultado con el cliente y obtener conformidad", status: "renta_revision", offset: 6, duration: 2, assignee: "lead",
            acceptance: "Conformidad del cliente por escrito." },
        ] },
        { name: "Presentación y cierre", tasks: [
          { title: "Presentar la declaración y archivar el justificante", status: "renta_presentacion", offset: 8, duration: 1, assignee: "lead",
            description: "Acción con efectos oficiales: solo una persona autorizada.", acceptance: "Justificante de presentación en la carpeta." },
          { title: "Enviar justificante y pedir valoración", status: "todo", offset: 9, duration: 1, assignee: "agent:entrega",
            acceptance: "Mensaje preparado para enviar tras aprobación." },
        ] },
      ],
    },
  });
  const trim = await run("service.save", {
    code: "TRIM",
    name: "Trimestrales",
    description: "Impuestos trimestrales de empresas y autónomos (303 y 111): recogida, contabilización, conciliación, modelos y presentación antes del día 20.",
    recurrence: "quarterly",
    workflow_id: wfTrim.id,
    template: {
      project_days: 14,
      done_when: "Modelos presentados antes del día 20, justificantes archivados y resumen enviado al cliente.",
      phases: [
        { name: "Recogida", tasks: [
          { title: "Solicitar facturas emitidas, recibidas y extractos del trimestre", status: "trim_recogida", offset: 0, duration: 3, assignee: "agent:entrega",
            acceptance: "Inventario de documentos recibidos y faltantes." },
        ] },
        { name: "Contabilidad", tasks: [
          { title: "Contabilizar facturas y clasificar gastos", status: "trim_contabilizacion", offset: 3, duration: 4, assignee: "agent:entrega",
            acceptance: "Libros de ingresos y gastos del trimestre completos." },
          { title: "Conciliar bancos y listar diferencias", status: "trim_conciliacion", offset: 6, duration: 2, assignee: "agent:entrega",
            acceptance: "Lista de diferencias con su explicación o pregunta al cliente." },
        ] },
        { name: "Modelos", tasks: [
          { title: "Preparar borradores de los modelos 303 y 111", status: "trim_modelos", offset: 8, duration: 2, assignee: "lead",
            description: "Revisión profesional obligatoria.", acceptance: "Borradores revisados por la asesora." },
          { title: "Validación del cliente y aviso del cargo", status: "trim_modelos", offset: 10, duration: 1, assignee: "lead", acceptance: "Conformidad escrita del cliente." },
        ] },
        { name: "Presentación", tasks: [
          { title: "Presentar modelos y archivar justificantes", status: "trim_presentacion", offset: 11, duration: 1, assignee: "lead", due_slack: 0,
            description: "Acción con efectos oficiales: solo una persona con certificado.", acceptance: "Justificantes en la carpeta del cliente." },
        ] },
      ],
    },
  });
  await run("offer.version", { service_id: renta.id, price_minor: eur(80), tax_rate_bp: 2100, billing_unit: "declaración",
    conditions: "Incluye borrador, revisión y presentación. Pago por adelantado." });
  await run("offer.version", { service_id: renta.id, price_minor: eur(90), conditions: "Incluye borrador, revisión y presentación. Pago por adelantado. Campaña 2026." });
  await run("offer.version", { service_id: trim.id, price_minor: eur(150), tax_rate_bp: 2100, billing_unit: "trimestre",
    conditions: "Modelos 303 y 111 de un trimestre. Pago al inicio del trimestre de trabajo." });
  log("servicios y ofertas");

  // --- Agents, squad and roles --------------------------------------------
  const runtime = await waitFor(async () => {
    const r = await http("GET", `/api/runtimes?workspace_id=${ws}`);
    return (r.runtimes ?? r).find((x) => x.provider === "claude" && x.status === "online");
  }, "runtime Claude en línea", 90000);
  log("runtime", runtime.name);

  const roleDefs = [
    { area: "direccion", name: "Director", mission: "Fijar foco, objetivos y decisiones; proteger la caja y la calidad.", decisions: "Prioridades, precios, excepciones de crédito, contrataciones.", limits: "No ejecuta trabajo de entrega rutinario.", kpi_codes: ["DIR-OBJ", "DIR-DEC"], occupant: "me",
      manual: "## Rutina\n- Abrir el día con un foco y cerrarlo con un veredicto.\n- Lunes: reparto de la semana. Viernes: balance.\n- Revisión trimestral de objetivos." },
    { area: "ventas", name: "Comercial", mission: "Convertir interesados en clientes que pagan antes de empezar.", decisions: "Cualificación, propuesta desde la oferta vigente, seguimientos.", limits: "Sin descuentos fuera de política; ganada solo con cobro.", kpi_codes: ["VEN-WON", "VEN-CONV"], occupant: "me",
      manual: "## Proceso\nEntrada → cualificación → diagnóstico (guion v1) → propuesta → negociación → aceptada → ganada (cobro).\nGuion: Ventas/Guiones/diagnostico-v1.md" },
    { area: "entrega", name: "Implementador", mission: "Entregar cada declaración a tiempo y con su criterio de terminado.", decisions: "Planificación interna de tareas.", limits: "No cambia vencimientos comprometidos sin autorización.", kpi_codes: ["ENT-ONTIME", "ENT-OVERDUE"], occupant: "me",
      manual: "## Servicios\n- Renta: canvas de 5 columnas.\n- Trimestrales: canvas de 6 columnas, plazo día 20." },
    { area: "finanzas", name: "Financiero", mission: "Caja predecible, cobros a tiempo y trimestre preparado sin sustos.", decisions: "Reclamaciones, conciliaciones, paquete trimestral.", limits: "No presenta impuestos; no confirma cobros sin evidencia.", kpi_codes: ["FIN-RUNWAY", "FIN-AR"], occupant: "me",
      manual: "## Cierre trimestral\n1. Conciliar bancos.\n2. Justificantes completos.\n3. Paquete para la asesora.\n4. Aprobación, envío y justificantes." },
    { area: "marca", name: "Responsable de Marca", mission: "Generar conversaciones útiles con clientes ideales.", decisions: "Calendario editorial y pilares.", limits: "Publicar requiere aprobación y evidencia.", kpi_codes: ["MAR-QCONV", "MAR-PUB"], occupant: null,
      manual: "## Pilares\nRenta sin sustos · Autónomos al día · Casos · Calendario fiscal\nIdentidad: Marca/Identidad.md" },
    { area: "equipo", name: "Responsable de Equipo", mission: "Capacidad suficiente y sana entre personas y agentes.", decisions: "Asignación de roles, presupuestos de agentes.", limits: "Horas humanas y ejecuciones de agentes se miden por separado.", kpi_codes: ["EQU-HEALTH", "EQU-ROLES"], occupant: "me",
      manual: "## Revisión mensual\nSalud de agentes, coste, rutinas caídas y roles vacantes." },
  ];
  const roles = {};
  for (const r of roleDefs) {
    const { occupant, ...rest } = r;
    roles[r.area] = await run("role.save", { ...rest, ...(occupant ? { occupant_type: "member", occupant_id: me.id } : {}) });
  }

  const agents = {};
  for (const def of AGENTS) {
    const agent = await http("POST", "/api/agents", {
      name: def.name,
      description: def.description,
      instructions: def.instructions,
      runtime_id: runtime.id,
      visibility: "workspace",
      max_concurrent_tasks: 2,
    });
    agents[def.key] = agent;
    await run("agent.assign", {
      agent_id: agent.id,
      area: def.key,
      role_id: roles[def.key].id,
      is_coordinator: !!def.coordinator,
      budget_monthly_minor: eur(def.coordinator ? 40 : 25),
      max_delegation_depth: def.coordinator ? 2 : 1,
    });
  }
  const squad = await http("POST", "/api/squads", {
    name: "Comité de dirección",
    description: "Agentes de las seis áreas coordinados por Dirección. Preparan argumentos; decide una persona.",
    leader_id: agents.direccion.id,
  });
  for (const key of ["ventas", "entrega", "finanzas", "marca", "equipo"]) {
    await http("POST", `/api/squads/${squad.id}/members`, { member_type: "agent", member_id: agents[key].id, role: AGENTS.find((a) => a.key === key).role });
  }
  log("agentes", Object.keys(agents).length, "y comité");

  for (const [capability, mode] of Object.entries({ "VEN-08": "supervised", "FIN-07": "supervised", "MAR-06": "autonomous", "DIR-01": "assisted" })) {
    await run("policy.set", { capability, mode });
  }

  // --- Brand: content and conversations -----------------------------------
  const contents = {};
  const contentDefs = [
    { key: "gastos", title: "5 gastos que los autónomos olvidan deducir", pillar: "Autónomos al día", channel: "instagram", format: "carrusel", status: "publicado", evidence: "https://instagram.com/p/demo-gastos-autonomos" },
    { key: "calendario", title: "Calendario fiscal de octubre: el día 20 no se mueve", pillar: "Calendario fiscal", channel: "linkedin", format: "post", status: "publicado", evidence: "https://linkedin.com/posts/demo-calendario-octubre" },
    { key: "renta-temprana", title: "Reserva tu Renta 2026 y olvídate en abril", pillar: "Renta sin sustos", channel: "instagram", format: "reel", status: "publicado", evidence: "https://instagram.com/reel/demo-reserva-renta" },
    { key: "caso-panaderia", title: "Caso: cómo una panadería dejó de pagar recargos", pillar: "Casos", channel: "blog", format: "artículo", status: "revision" },
    { key: "303", title: "Qué es el modelo 303 en 60 segundos", pillar: "Autónomos al día", channel: "instagram", format: "reel", status: "aprobado" },
    { key: "facturas", title: "Checklist: facturas que tu gestoría necesita cada trimestre", pillar: "Autónomos al día", channel: "newsletter", format: "email", status: "borrador" },
    { key: "deducciones", title: "Deducciones autonómicas de la Comunitat Valenciana", pillar: "Renta sin sustos", channel: "blog", format: "artículo", status: "idea" },
  ];
  const flow = ["borrador", "revision", "aprobado", "publicado"];
  for (const c of contentDefs) {
    const row = await run("content.create", { title: c.title, pillar: c.pillar, channel: c.channel, format: c.format,
      body: c.status === "idea" ? "" : `Borrador de «${c.title}». Mensaje clave en tono cercano y claro.` });
    contents[c.key] = row;
    if (c.status === "idea" || c.status === "borrador") continue;
    for (const st of flow.slice(1)) {
      await run("content.move", { id: row.id, status: st, ...(st === "publicado" ? { evidence_url: c.evidence } : {}) });
      if (st === c.status) break;
    }
  }
  const convDefs = [
    { content: "gastos", channel: "instagram", handle: "@lucuma.estudio", summary: "Pregunta si llevamos trimestrales de un estudio de diseño con 3 socios.", qualify: { name: "Irene Lúcuma", email: "irene@lucuma.example", company: "Estudio Creativo Lúcuma SL", service_code: "TRIM" } },
    { content: "renta-temprana", channel: "instagram", handle: "@nerea.blasco", summary: "Quiere reservar la Renta 2026: alquila un piso y cambió de trabajo.", qualify: { name: "Nerea Blasco", email: "nerea.blasco@example.com", service_code: "RENTA" } },
    { content: "calendario", channel: "linkedin", handle: "Pedro Llorens", summary: "Comenta que su gestor actual se retrasa siempre con el 303.", qualify: null },
    { content: "gastos", channel: "instagram", handle: "@fotoviaje", summary: "Duda sobre deducir el coche; no es cliente potencial (vive fuera de España).", qualify: null },
  ];
  for (const c of convDefs) {
    const conv = await run("conversation.create", { channel: c.channel, handle: c.handle, summary: c.summary, content_id: contents[c.content].id });
    if (c.qualify) await run("conversation.qualify", { id: conv.id, ...c.qualify });
  }
  log("marca: contenidos y conversaciones");

  // --- Sales pipeline and customer journey ---------------------------------
  const lead = (contact, organization, service_code, channel, extra = {}) =>
    run("lead.create", { contact, organization, service_code, channel, ...extra });
  const advance = async (opp, upTo) => {
    for (const stage of ["cualificacion", "diagnostico"]) {
      await run("opportunity.move", { id: opp.id, stage });
      if (stage === upTo) return;
    }
    if (upTo === "diagnostico") return;
    await run("opportunity.proposal", { id: opp.id });
    if (upTo === "propuesta") return;
    await run("opportunity.move", { id: opp.id, stage: "negociacion" });
  };
  const win = async (opp, acceptedNote) => {
    await advance(opp, "propuesta");
    await run("opportunity.accept", { id: opp.id, evidence: acceptedNote });
    return waitFor(async () => (await list("invoice", `opportunity_id=${opp.id}`))[0], "factura en borrador");
  };

  // Renta 2025 clients (campaign April–June): paid by card at the office.
  const rentaClosed = [];
  for (const [name, email, issue, paid] of [
    ["Lucía Ferrer", "lucia.ferrer@example.com", "2026-05-06", "2026-05-06"],
    ["Marta Soler", "marta.soler@example.com", "2026-05-20", "2026-05-21"],
    ["Pablo Ruiz", "pablo.ruiz@example.com", "2026-06-03", "2026-06-03"],
  ]) {
    const opp = await lead({ name, email }, null, "RENTA", "referido");
    const inv = await win(opp, "Firma de la hoja de encargo en la oficina");
    await run("invoice.issue", { id: inv.id, issue_date: issue });
    await run("payment.confirm", { invoice_id: inv.id, amount_minor: inv.total_minor, paid_on: paid, method: "tarjeta", evidence: `Recibo TPV ${paid}` });
    rentaClosed.push(opp);
  }

  // Trimestrales T3 clients, paid at the start of the quarter's work.
  const trimClients = {};
  for (const [key, person, email, company, sector, issue] of [
    ["panaderia", "Rafael Sol", "rafa@hornosol.example", "Panadería Horno Sol SL", "Alimentación", "2026-07-05"],
    ["clinica", "Dra. Ana Pons", "ana@sonrisa.example", "Clínica Dental Sonrisa SLP", "Salud", "2026-07-08"],
  ]) {
    const opp = await lead({ name: person, email }, { name: company, sector, city: "Valencia" }, "TRIM", "referido");
    const inv = await win(opp, "Aceptación por correo de la propuesta trimestral");
    await run("invoice.issue", { id: inv.id, issue_date: issue });
    trimClients[key] = { opp, inv };
  }

  // Renta "fuera de plazo" in progress.
  const andres = await lead({ name: "Andrés Vidal", email: "andres.vidal@example.com" }, null, "RENTA", "web");
  const andresInv = await win(andres, "Aceptación por correo: declaración fuera de plazo");
  await run("invoice.issue", { id: andresInv.id, issue_date: "2026-09-15" });

  // Talleres Martín: accepted and invoiced; the payment is in the bank but not confirmed.
  const talleres = await lead({ name: "Jorge Martín", email: "jorge@talleresmartin.example" }, { name: "Talleres Martín e Hijos SL", sector: "Automoción", city: "Paterna" }, "TRIM", "llamada");
  const talleresInv = await win(talleres, "Llamada del 14/10 y correo de confirmación");
  await run("invoice.issue", { id: talleresInv.id, issue_date: "2026-10-15" });

  // Open pipeline.
  const nexo = await lead({ name: "Sergio Nexo", email: "sergio@nexo.example" }, { name: "Arquitectura Nexo SLP", sector: "Arquitectura" }, "TRIM", "linkedin");
  await advance(nexo, "propuesta");
  const frutas = await lead({ name: "Amparo Ribera", email: "amparo@frutasribera.example" }, { name: "Frutas Ribera SC", sector: "Agricultura", city: "Alzira" }, "TRIM", "feria");
  await advance(frutas, "diagnostico");
  const carlos = await lead({ name: "Carlos Gil", email: "carlos.gil@example.com" }, null, "RENTA", "referido", { notes: "Referido por Lucía Ferrer." });
  await advance(carlos, "cualificacion");
  const javier = await lead({ name: "Javier Ortega", email: "javier.ortega@example.com" }, null, "RENTA", "web");
  await advance(javier, "propuesta");
  const bar = await lead({ name: "Lola Plaza", email: "lola@barlaplaza.example" }, { name: "Bar La Plaza CB", sector: "Hostelería" }, "TRIM", "web");
  await advance(bar, "propuesta");
  await run("opportunity.move", { id: bar.id, stage: "perdida", lost_reason: "Precio: eligió una gestoría online a 59 €/trimestre." });
  log("ventas: embudo completo");

  // --- Finance: accounts, supplier invoices with receipts, bank statements ---
  const cc = await run("account.create", { name: "Cuenta corriente Banco Demo", iban_masked: "ES** **** **** **** 4821", opening_balance_minor: eur(18400), opening_on: "2026-06-30" });
  const ahorro = await run("account.create", { name: "Cuenta ahorro Banco Demo", iban_masked: "ES** **** **** **** 7730", opening_balance_minor: eur(5000), opening_on: "2026-06-30" });

  const supplier = async (supplier_name, number, issue_date, concept, base, tax, withholding, category, withDoc) => {
    let document_path;
    if (withDoc) {
      document_path = `Justificantes/${issue_date.slice(0, 7)}/${number.replace(/\W+/g, "-")}.pdf`;
      fakePdf(join(FOLDER, document_path), `${supplier_name} · Factura ${number}`, [`Fecha: ${issue_date}`, `Concepto: ${concept}`, `Base: ${base} EUR`, `IVA: ${tax} EUR`, `Retencion: ${withholding} EUR`, "DOCUMENTO FICTICIO DE DEMOSTRACION"]);
    }
    return run("invoice.received", { supplier_name, number, issue_date, concept, base_minor: eur(base), tax_minor: eur(tax), withholding_minor: eur(withholding), category, document_path });
  };
  const months = ["07", "08", "09", "10"];
  for (const m of months) {
    await supplier("Inmobiliaria Centro SL", `ALQ-2026-${m}`, `2026-${m}-01`, "Alquiler oficina", 650, 136.5, 123.5, "Alquiler", m !== "10");
    await supplier("Software Contable Nube SL", `SCN-26${m}`, `2026-${m}-05`, "Licencia software contable", 120, 25.2, 0, "Software", true);
    if (m !== "10") await supplier("Movil Levante SL", `ML-${m}-2026`, `2026-${m}-10`, "Telefonía e internet", 65, 13.65, 0, "Suministros", m !== "08");
  }

  // Bank statement: semicolon CSV with Spanish decimals and running balance.
  const fmt = (n) => n.toFixed(2).replace(".", ",");
  const ccRows = [];
  const add = (d, concept, amount) => ccRows.push({ d, concept, amount });
  for (const m of months) {
    add(`2026-${m}-01`, "RECIBO INMOBILIARIA CENTRO SL ALQUILER", -663.0);
    add(`2026-${m}-02`, "REMESA CUOTAS CLIENTES CARTERA", 3400);
    add(`2026-${m}-05`, "RECIBO SOFTWARE CONTABLE NUBE SL", -145.2);
    if (m !== "10") add(`2026-${m}-10`, "RECIBO MOVIL LEVANTE SL", -78.65);
    if (m !== "10") add(`2026-${m}-28`, "NOMINA OCTUBRE EMPLEADA".replace("OCTUBRE", { "07": "JULIO", "08": "AGOSTO", "09": "SEPTIEMBRE" }[m]), -1450);
    if (m !== "10") add(`2026-${m}-30`, "TGSS SEGUROS SOCIALES", -480);
  }
  add("2026-07-12", "TRANSFERENCIA DE PANADERIA HORNO SOL F-2026-0004", 181.5);
  add("2026-07-20", "TRANSFERENCIA DE CLINICA DENTAL SONRISA F-2026-0005", 181.5);
  add("2026-07-20", "AEAT MODELO 303 2T 2026", -640);
  add("2026-07-20", "AEAT MODELO 111 2T 2026", -290);
  add("2026-08-14", "TRASPASO A CUENTA AHORRO", -2000);
  add("2026-09-18", "TRANSFERENCIA DE ANDRES VIDAL F-2026-0006", 108.9);
  add("2026-09-30", "RETIRADA SOCIO DISPOSICION TITULAR", -800);
  add("2026-10-17", "TRANSFERENCIA DE TALLERES MARTIN E HIJOS SL", 181.5);
  ccRows.sort((a, b) => a.d.localeCompare(b.d));
  let bal = 18400;
  const csv = ["fecha;fecha_valor;concepto;importe;saldo"];
  for (const r of ccRows) {
    bal = Math.round((bal + r.amount) * 100) / 100;
    const [y, mo, d] = r.d.split("-");
    csv.push(`${d}/${mo}/${y};${d}/${mo}/${y};${r.concept};${fmt(r.amount)};${fmt(bal)}`);
  }
  writeStatic("Finanzas/Bancos/extractos/cuenta-corriente-2026-07-a-10.csv", csv.join("\n") + "\n");
  const imp1 = await run("bank.import", { account_id: cc.id, batch: "extracto-cc-2026-07-10", csv: csv.join("\n") });
  const imp2 = await run("bank.import", { account_id: cc.id, batch: "extracto-cc-2026-07-10-reimport", csv: csv.join("\n") });
  await run("bank.import", { account_id: ahorro.id, batch: "extracto-ahorro", csv: "fecha;fecha_valor;concepto;importe;saldo\n14/08/2026;14/08/2026;TRASPASO DESDE CUENTA CORRIENTE;2000,00;7000,00\n" });
  log(`extracto importado: ${imp1.inserted} nuevos, reimportación: ${imp2.inserted} nuevos / ${imp2.duplicates} duplicados`);

  // Confirm what the bank proves, except Talleres (left for the live demo).
  const movements = await list("movement");
  for (const m of movements.filter((x) => x.status === "proposed")) {
    if (m.description.includes("TALLERES")) continue;
    await run("payment.confirm", { invoice_id: m.invoice_id, movement_id: m.id });
  }
  for (const m of movements.filter((x) => x.description.startsWith("REMESA CUOTAS"))) {
    await run("movement.classify", { id: m.id, category: "Cuotas de cartera", notes: "Clientes de cartera facturados en el programa anterior; se migran en 2027.", ignore: true });
  }
  for (const m of movements.filter((x) => x.description.startsWith("TRASPASO") || x.description.startsWith("RETIRADA") || x.description.startsWith("AEAT") || x.description.startsWith("TGSS") || x.description.startsWith("NOMINA"))) {
    await run("movement.classify", { id: m.id, ignore: true, notes: "Sin factura asociada por naturaleza (impuestos, nómina, traspaso o retirada)." });
  }
  // Talleres paid by transfer, but the concept has no invoice number: the matcher proposed it by name.
  log("cobros y pagos conciliados");

  // Projects created by the payment events.
  const projects = await waitFor(async () => {
    const p = await http("GET", "/api/biz/projects");
    const linked = p.filter((x) => x.service_id);
    return linked.length >= 6 && linked.every((x) => x.tasks > 0) ? linked : null;
  }, "proyectos con tareas", 120000);
  log("proyectos creados por cobro:", projects.length);

  // Shift historical project dates so the demo timeline is believable.
  const byOpp = (opp) => projects.find((p) => p.opportunity_id === opp.id);
  const shift = (projectId, days) => {
    sql(`UPDATE issue SET start_date = start_date - ${days}, due_date = due_date - ${days} WHERE project_id='${projectId}';
         UPDATE project SET start_date = start_date - ${days} WHERE id='${projectId}'`);
  };
  const setStatus = async (projectId, statuses) => {
    const ids = sql(`SELECT id FROM issue WHERE project_id='${projectId}' ORDER BY start_date, number`).split("\n").filter(Boolean);
    for (let i = 0; i < ids.length && i < statuses.length; i++) {
      if (statuses[i]) await http("PUT", `/api/issues/${ids[i]}`, { status: statuses[i] });
    }
    return ids;
  };
  for (const [i, opp] of rentaClosed.entries()) {
    const p = byOpp(opp);
    shift(p.id, 150 - i * 12);
    await setStatus(p.id, ["done", "done", "done", "done", "done", "done"]);
    await run("project.close", { project_id: p.id, outcome: "Declaración presentada en plazo; resultado a devolver.", evidence: `Justificante de presentación archivado en la carpeta del cliente (${opp.title}).` });
  }
  const pan = byOpp(trimClients.panaderia.opp);
  shift(pan.id, 13);
  await setStatus(pan.id, ["done", "done", "trim_conciliacion", "trim_modelos"]);
  const cli = byOpp(trimClients.clinica.opp);
  shift(cli.id, 11);
  await setStatus(cli.id, ["done", "trim_contabilizacion"]);
  const andresP = byOpp(andres);
  shift(andresP.id, 6);
  await setStatus(andresP.id, ["done", "done", "renta_preparacion"]);
  // Done tasks were finished on their planned day (before the due date).
  const shifted = [...rentaClosed.map((o) => byOpp(o).id), pan.id, cli.id, andresP.id].map((id) => `'${id}'`).join(",");
  sql(`UPDATE issue SET updated_at = (start_date + 1)::timestamp + interval '11 hours' WHERE project_id IN (${shifted}) AND status='done'`);
  sql(`UPDATE biz_opportunity SET last_contact_at = now() - interval '21 days', created_at = now() - interval '30 days' WHERE id='${javier.id}';
       UPDATE biz_opportunity SET created_at = now() - interval '12 days', last_contact_at = now() - interval '5 days' WHERE id IN ('${nexo.id}','${frutas.id}');
       UPDATE biz_conversation SET created_at = now() - interval '5 days' WHERE qualified = false AND workspace_id='${ws}'`);
  log("línea temporal de proyectos ajustada");

  // --- Direction: objectives, decisions, routines; quarterly package ------
  for (const o of [
    { area: "ventas", title: "6.000 € de ventas cobradas al mes", kind: "cumulative", kpi_code: "VEN-WON", target: 6000 },
    { area: "entrega", title: "90 % de tareas de entrega a tiempo", kind: "level", kpi_code: "ENT-ONTIME", target: 90 },
    { area: "finanzas", title: "Mantener al menos 3 meses de caja", kind: "level", kpi_code: "FIN-RUNWAY", target: 3 },
    { area: "marca", title: "8 conversaciones cualificadas al mes", kind: "cumulative", kpi_code: "MAR-QCONV", target: 8 },
    { area: "direccion", title: "Trimestrales T3 de todos los clientes presentados antes del 20/10", kind: "compliance" },
    { area: "equipo", title: "Todos los roles con ocupante", kind: "level", kpi_code: "EQU-ROLES", target: 100 },
  ]) {
    await run("objective.save", { period: "2026-T4", ...o });
  }
  await run("decision.create", { area: "direccion", title: "Política de arranque: cobro confirmado antes de empezar",
    context: "En 2025 hubo trabajos entregados sin cobrar (dato ficticio).", decision: "Ningún proyecto arranca sin cobro confirmado o excepción de crédito registrada.",
    why: "Evitar trabajo sin cobrar y discusiones al final.", purpose: "Caja predecible y foco en clientes comprometidos." });
  await run("decision.create", { area: "ventas", title: "Precio Renta 2026: 90 €",
    decision: "La oferta de Renta pasa de 80 € a 90 € + IVA desde la campaña 2026.", why: "Más deducciones autonómicas y tiempo medio de 2,1 h por declaración.",
    purpose: "Margen del 30 % en Renta.", refs: [{ type: "service", id: renta.id }] });
  await run("decision.create", { area: "direccion", title: "¿Subir Trimestrales a 165 € desde T1 2027?",
    context: "Hemos perdido Bar La Plaza por precio (59 € online). Clínica y Panadería valoran el trato. Preparar argumentos a favor y en contra con datos de margen y pérdidas." });
  await run("decision.create", { area: "equipo", title: "¿Dejar que el agente Comercial envíe recordatorios de propuesta sin aprobación?",
    context: "Hoy cada seguimiento requiere aprobación (VEN-08 supervisado). Proponer límites: solo plantillas aprobadas, máximo 2 toques, nunca a contactos dados de baja." });
  await run("routine.save", { kind: "week", period_key: "2026-W42", plan: "Cerrar T3 de Panadería y Clínica; propuesta a Arquitectura Nexo.", review: "Panadería al día; Clínica va justa en contabilización. Nexo sin respuesta.", close: true });
  await run("routine.save", { kind: "day", period_key: daysAgo(3), focus: "Conciliar extractos de septiembre", verdict: "Hecho; quedan 2 gastos sin justificante.", close: true });

  await run("period.prepare", { year: 2026, quarter: 3 });
  log("dirección y paquete T3 preparados");

  // --- Static, human-authored files in the company folder -----------------
  writeStatic("Marca/Identidad.md", `---\ntls_type: brand_identity\nversion: 1\n---\n\n# Identidad de Asesoría Ribera (DEMO)\n\n- **A quién:** particulares con rentas con alquileres, cambios de trabajo o deducciones; pymes y autónomos de servicios en Valencia.\n- **Qué:** impuestos sin sustos ni recargos, con fechas claras.\n- **Tono:** cercano, claro, sin tecnicismos; nunca alarmista.\n- **Aspecto:** sobrio, verde oliva y blanco.\n`);
  writeStatic("Ventas/Guiones/diagnostico-v1.md", `---\ntls_type: script\nversion: 1\n---\n\n# Guion de diagnóstico v1\n\n1. ¿Qué te preocupa de tus impuestos ahora mismo?\n2. ¿Quién los lleva hoy y qué echas en falta?\n3. Situación: actividad, empleados, facturas al mes, bancos.\n4. Plazos y sustos recientes (recargos, requerimientos).\n5. Siguiente paso: propuesta desde la oferta vigente.\n\n> Cita literal lo que diga el cliente; los acuerdos se proponen, no se dan por aprobados.\n`);
  writeStatic("LEEME.md", `# Carpeta portable · Asesoría Ribera (DEMO)\n\nEmpresa ficticia de demostración. Cada fichero \`.md\` con \`tls_type\` es un registro: su identidad es el campo \`id\`.\n\n- **Ventas/** organizaciones, contactos, oportunidades, ofertas y guiones.\n- **Entrega/** servicios (canvas y plantillas).\n- **Finanzas/** año → trimestre → ingresos, gastos por proveedor, cobros y pagos; bancos; paquete para la gestoría.\n- **Dirección/** objetivos, decisiones, KPI y rutinas.\n- **Marca/** identidad, contenidos y conversaciones.\n- **Equipo/** roles.\n- **Justificantes/** documentos originales (PDF).\n\nNo hay secretos en esta carpeta. Índices y cachés viven en Application Support.\n`);
  await http("POST", "/api/biz/folder/export", {});

  // --- Go live: leave import mode, enable rituals, start real agent work ---
  await run("settings.set", { key: "import_mode", value: false });
  if (OFFLINE) {
    log(`listo (sin agentes en vivo) → http://localhost:3000/${SLUG}/empresa · carpeta: ${FOLDER}`);
    return;
  }
  await run("settings.set", { key: "rituals_enabled", value: true });
  const rosa = await lead({ name: "Rosa Campos", email: "rosa.campos@example.com", phone: "600 000 000" }, null, "RENTA", "web",
    { notes: "Formulario web: «Me han llegado dos certificados de retenciones y no sé si tengo que declarar. También tengo un piso alquilado.»" });
  const pkg = (await list("period")).find((p) => p.year === 2026 && p.quarter === 3);
  await http("POST", "/api/issues", {
    title: "Revisar el paquete T3 2026 y sus excepciones",
    description: `Revisa el periodo T3 2026 (\`multica biz get /record/period/${pkg.id}\`) y las excepciones de Finanzas. Lista exactamente qué falta antes de enviarlo a la asesora y qué movimientos o justificantes hay que resolver. No cambies el estado del periodo.`,
    status: "todo",
    priority: "high",
    assignee_type: "agent",
    assignee_id: agents.finanzas.id,
  });
  await http("POST", "/api/biz/events/process", {});
  log("en vivo: lead de Rosa Campos (agente Comercial) y revisión del paquete T3 (agente Financiero)");
  log(`listo → http://localhost:3000/${SLUG}/empresa · carpeta: ${FOLDER}`);
  console.log(JSON.stringify({ workspace: ws, slug: SLUG, folder: FOLDER, agents: Object.fromEntries(Object.entries(agents).map(([k, a]) => [k, a.id])), rosa: rosa.id }, null, 2));
}

main().catch((err) => {
  console.error("✗", err.message);
  process.exit(1);
});
