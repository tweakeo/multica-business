// Formatting for business values. Money arrives in integer minor units and
// is formatted, never computed, on the client.

const eurFmt = new Intl.NumberFormat("es-ES", { style: "currency", currency: "EUR" });
const numFmt = new Intl.NumberFormat("es-ES", { maximumFractionDigits: 1 });

export function formatMinor(minor: unknown, currency = "EUR"): string {
  if (typeof minor !== "number" || Number.isNaN(minor)) return "—";
  if (currency !== "EUR") {
    return new Intl.NumberFormat("es-ES", { style: "currency", currency }).format(minor / 100);
  }
  return eurFmt.format(minor / 100);
}

export function formatKpiValue(value: number | null | undefined, unit: string): string {
  if (value === null || value === undefined) return "Desconocido";
  switch (unit) {
    case "EUR":
      return eurFmt.format(value);
    case "USD":
      return new Intl.NumberFormat("es-ES", { style: "currency", currency: "USD" }).format(value);
    case "%":
      return `${numFmt.format(value)} %`;
    case "meses":
      return `${numFmt.format(value)} meses`;
    default:
      return numFmt.format(value);
  }
}

/** Calendar dates (YYYY-MM-DD) keep their day: no timezone conversion. */
export function formatDate(value: unknown): string {
  if (typeof value !== "string" || value === "") return "—";
  const day = value.slice(0, 10);
  const [y, m, d] = day.split("-");
  if (!y || !m || !d) return value;
  if (value.length > 10) {
    const dt = new Date(value);
    if (!Number.isNaN(dt.getTime())) {
      return dt.toLocaleDateString("es-ES", { day: "2-digit", month: "short", year: "numeric", timeZone: "Europe/Madrid" });
    }
  }
  return `${d}/${m}/${y}`;
}

export function formatDateTime(value: unknown): string {
  if (typeof value !== "string" || value === "") return "—";
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return value;
  return dt.toLocaleString("es-ES", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", timeZone: "Europe/Madrid" });
}

export const BIZ_AREA_ORDER = ["direccion", "ventas", "entrega", "finanzas", "marca", "equipo"] as const;
export type BizAreaCode = (typeof BIZ_AREA_ORDER)[number];

export const STAGE_LABELS: Record<string, string> = {
  entrada: "Entrada",
  cualificacion: "Cualificación",
  diagnostico: "Diagnóstico",
  propuesta: "Propuesta",
  negociacion: "Negociación",
  aceptada: "Aceptada · pendiente de cobro",
  ganada: "Ganada · cobrada",
  perdida: "Perdida",
  pausada: "Pausada",
};

export const INVOICE_STATUS_LABELS: Record<string, string> = {
  draft: "Borrador",
  issued: "Emitida",
  partially_paid: "Cobro parcial",
  paid: "Cobrada",
  void: "Anulada",
  rectified: "Rectificada",
};

export const MOVEMENT_STATUS_LABELS: Record<string, string> = {
  unreconciled: "Sin conciliar",
  proposed: "Conciliación propuesta",
  reconciled: "Conciliado",
  ignored: "Sin factura (justificado)",
};

export const NATURE_LABELS: Record<string, string> = {
  unclassified: "Sin clasificar",
  operating_income: "Ingreso operativo",
  operating_expense: "Gasto operativo",
  tax: "Impuestos",
  payroll: "Nómina",
  internal_transfer: "Traspaso interno",
  owner_withdrawal: "Retirada del titular",
  loan: "Préstamo",
  investment: "Inversión",
};

export const PERIOD_STATUS_LABELS: Record<string, string> = {
  open: "Abierto",
  prepared: "Preparado",
  approved: "Aprobado para envío",
  sent: "Enviado a la asesora",
  filed: "Presentado con justificante",
  archived: "Justificantes archivados",
  settled: "Liquidación verificada",
  not_applicable: "No aplica",
};

export const PERIOD_NEXT: Record<string, string> = {
  open: "prepared",
  prepared: "approved",
  approved: "sent",
  sent: "filed",
  filed: "archived",
  archived: "settled",
};

export const CONTENT_STATUS_ORDER = ["idea", "borrador", "revision", "aprobado", "programado", "publicado", "fallido"] as const;
export const CONTENT_STATUS_LABELS: Record<string, string> = {
  idea: "Idea",
  borrador: "Borrador",
  revision: "Revisión",
  aprobado: "Aprobado",
  programado: "Programado",
  publicado: "Publicado",
  fallido: "Fallido",
};

export const MODE_LABELS: Record<string, string> = {
  off: "Desactivada",
  manual: "Manual",
  assisted: "Asistido (borradores)",
  supervised: "Supervisado (aprobación)",
  autonomous: "Autónomo con límites",
};

export const ENTITY_LABELS: Record<string, string> = {
  organization: "Organización",
  contact: "Contacto",
  opportunity: "Oportunidad",
  service: "Servicio",
  offer: "Oferta",
  invoice: "Factura",
  payment: "Cobro/pago",
  account: "Cuenta",
  movement: "Movimiento",
  period: "Trimestre",
  kpi: "KPI",
  objective: "Objetivo",
  decision: "Decisión",
  content: "Contenido",
  conversation: "Conversación",
  routine: "Rutina",
  role: "Rol",
  document: "Documento",
  approval: "Aprobación",
  project: "Proyecto",
  issue: "Tarea",
  agent: "Agente",
};
