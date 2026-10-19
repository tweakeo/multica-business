// Package biz is the TLS business layer ("Empresa") built on top of Multica:
// six business areas, CRM, offers, delivery lines, finance, brand, direction,
// approvals, durable events, audit and the portable company folder.
//
// Tasks and projects are Multica's own issues and projects; this package only
// adds the business records around them.
package biz

// Areas in presentation order (Dirección → Ventas → Entrega → Finanzas →
// Marca → Equipo).
var Areas = []AreaInfo{
	{Code: "direccion", Name: "Dirección", Color: "violet", Transforms: "Ruido en decisiones", Role: "Director"},
	{Code: "ventas", Name: "Ventas", Color: "green", Transforms: "Desconocidos en clientes", Role: "Comercial"},
	{Code: "entrega", Name: "Entrega", Color: "blue", Transforms: "Promesas en resultados", Role: "Implementador"},
	{Code: "finanzas", Name: "Finanzas", Color: "yellow", Transforms: "Actividad en caja y margen", Role: "Financiero"},
	{Code: "marca", Name: "Marca", Color: "pink", Transforms: "Mercado en demanda", Role: "Responsable de Marca"},
	{Code: "equipo", Name: "Equipo", Color: "red", Transforms: "Personas y agentes en capacidad", Role: "Responsable de Equipo"},
}

type AreaInfo struct {
	Code       string `json:"code"`
	Name       string `json:"name"`
	Color      string `json:"color"`
	Transforms string `json:"transforms"`
	Role       string `json:"role"`
}

func IsArea(code string) bool {
	for _, a := range Areas {
		if a.Code == code {
			return true
		}
	}
	return false
}

// Opportunity stages, in funnel order. "aceptada" means commercially accepted
// but not yet paid; "ganada" requires a confirmed payment (TLB policy).
var OpportunityStages = []string{
	"entrada", "cualificacion", "diagnostico", "propuesta", "negociacion", "aceptada", "ganada", "perdida", "pausada",
}

// Default stage probabilities for the weighted forecast (VEN-14).
var StageProbability = map[string]int{
	"entrada": 5, "cualificacion": 15, "diagnostico": 30, "propuesta": 50,
	"negociacion": 70, "aceptada": 90, "ganada": 100, "perdida": 0, "pausada": 5,
}

// Executors: H humano, A automatización, S script determinista, IA agente.
type Capability struct {
	Code     string   `json:"code"`
	Area     string   `json:"area"`
	Name     string   `json:"name"`
	Level    string   `json:"level"` // E esencial, R recomendable, O opcional
	Trigger  string   `json:"trigger"`
	Output   string   `json:"output"`
	Executor string   `json:"executor"`
	Requires []string `json:"requires,omitempty"`
	// Status in this build: implemented, partial, simulated, pending.
	Status string `json:"status"`
	// Where the behaviour lives, for traceability.
	Ref string `json:"ref,omitempty"`
	// Sensitive capabilities never execute an agent's request directly
	// unless the workspace policy is "autonomous"; they create an approval.
	Sensitive bool `json:"sensitive"`
}

var Capabilities = []Capability{
	// Dirección
	{Code: "DIR-01", Area: "direccion", Name: "Registro de decisiones con su porqué y su para qué", Level: "E", Trigger: "Una decisión tomada", Output: "Decisión inmutable y enlazada", Executor: "H + IA", Status: "implemented", Ref: "biz/direction.go"},
	{Code: "DIR-02", Area: "direccion", Name: "Objetivos del periodo con un número comprobable", Level: "E", Trigger: "Inicio de trimestre", Output: "Objetivos con meta y fecha", Executor: "H", Status: "implemented", Ref: "biz/direction.go"},
	{Code: "DIR-03", Area: "direccion", Name: "Todo proyecto activo cuelga de un objetivo", Level: "E", Trigger: "Proyecto activo", Output: "Aviso en la revisión si no hay objetivo", Executor: "S", Requires: []string{"DIR-02"}, Status: "implemented", Ref: "biz/kpi.go exceptions"},
	{Code: "DIR-04", Area: "direccion", Name: "Panel de área: KPI con meta y alerta", Level: "E", Trigger: "Cambio en el dato de origen", Output: "Estado por área y alertas", Executor: "S", Status: "implemented", Ref: "biz/kpi.go"},
	{Code: "DIR-05", Area: "direccion", Name: "Ritmo del día: foco al abrir, veredicto al cerrar", Level: "E", Trigger: "Días laborables", Output: "Panel del día y cierre registrado", Executor: "A", Status: "implemented", Ref: "biz/direction.go routines"},
	{Code: "DIR-06", Area: "direccion", Name: "Ritmo de la semana: reparto y balance", Level: "E", Trigger: "Lunes y viernes", Output: "Semana repartida y balance", Executor: "A", Status: "implemented", Ref: "biz/direction.go routines"},
	{Code: "DIR-07", Area: "direccion", Name: "Capacidad declarada en horas y tope diario", Level: "R", Trigger: "Al repartir el día", Output: "Aviso si se supera el tope", Executor: "S", Status: "partial", Ref: "biz/kpi.go EQU capacity"},
	{Code: "DIR-08", Area: "direccion", Name: "Mapa de etapa por área y cuello de botella", Level: "R", Trigger: "Revisión trimestral", Output: "Etapa estimada y cuello señalado", Executor: "IA", Requires: []string{"DIR-04"}, Status: "implemented", Ref: "biz/kpi.go maturity + agente Director"},
	{Code: "DIR-09", Area: "direccion", Name: "Auditoría del sistema", Level: "R", Trigger: "Periódica", Output: "Informe con propuestas accionables", Executor: "IA", Status: "implemented", Ref: "biz/kpi.go audit + agente Director"},
	{Code: "DIR-10", Area: "direccion", Name: "Ritmo del trimestre", Level: "R", Trigger: "Cierre de trimestre", Output: "Plan del trimestre siguiente", Executor: "A", Requires: []string{"DIR-02"}, Status: "implemented", Ref: "biz/direction.go routines"},
	{Code: "DIR-11", Area: "direccion", Name: "Interruptor global y modo lectura", Level: "E", Trigger: "Manual", Output: "Agentes y automatismos comprueban antes de escribir", Executor: "S", Status: "implemented", Ref: "biz/guard.go + task claim"},
	{Code: "DIR-12", Area: "direccion", Name: "Simulación de escenarios", Level: "O", Trigger: "A petición", Output: "Escenarios comparados", Executor: "IA", Status: "pending"},
	{Code: "DIR-13", Area: "direccion", Name: "Debate entre agentes de área", Level: "O", Trigger: "A petición", Output: "Posiciones con datos de respaldo", Executor: "IA", Status: "implemented", Ref: "equipo de agentes Comité de dirección"},

	// Ventas
	{Code: "VEN-01", Area: "ventas", Name: "Alta en paquete: empresa + contacto + oportunidad", Level: "E", Trigger: "Entrada de un desconocido", Output: "Las tres entidades ligadas", Executor: "S", Status: "implemented", Ref: "biz/sales.go CreateLead"},
	{Code: "VEN-02", Area: "ventas", Name: "Formulario de entrada con origen y atribución", Level: "E", Trigger: "El interesado lo envía", Output: "Contacto con canal real", Executor: "S", Requires: []string{"VEN-01"}, Status: "implemented", Ref: "POST /api/biz/leads"},
	{Code: "VEN-03", Area: "ventas", Name: "Oportunidad con valor, estado, producto y responsable", Level: "E", Trigger: "Alta o avance de etapa", Output: "Rechazo si falta algún dato de la etapa", Executor: "S", Status: "implemented", Ref: "biz/sales.go stage rules"},
	{Code: "VEN-04", Area: "ventas", Name: "Agendar la sesión de diagnóstico", Level: "E", Trigger: "contacto.creado", Output: "Reunión propuesta, sujeta a autorización", Executor: "A", Requires: []string{"VEN-01"}, Status: "simulated", Ref: "tarea de diagnóstico; sin calendario conectado", Sensitive: true},
	{Code: "VEN-05", Area: "ventas", Name: "Guion de diagnóstico versionado", Level: "E", Trigger: "Preparación de la sesión", Output: "Guion vigente único", Executor: "H", Status: "implemented", Ref: "carpeta Ventas/Guiones"},
	{Code: "VEN-06", Area: "ventas", Name: "Propuesta desde la oferta única con precio de su fuente", Level: "E", Trigger: "Fin del diagnóstico", Output: "Propuesta con instantánea de condiciones", Executor: "S", Requires: []string{"VEN-03"}, Status: "implemented", Ref: "biz/sales.go GenerateProposal"},
	{Code: "VEN-07", Area: "ventas", Name: "Ganada solo con cobro confirmado y creación del proyecto", Level: "E", Trigger: "cobro.confirmado", Output: "Proyecto ligado a empresa, producto y oportunidad", Executor: "S", Requires: []string{"VEN-06", "FIN-02"}, Status: "implemented", Ref: "biz/events.go onPaymentConfirmed"},
	{Code: "VEN-08", Area: "ventas", Name: "Secuencia de seguimiento por toques", Level: "R", Trigger: "Oportunidad sin movimiento", Output: "Toque redactado (borrador)", Executor: "A", Status: "implemented", Ref: "agente Comercial + aprobación de envío", Sensitive: true},
	{Code: "VEN-09", Area: "ventas", Name: "Alerta de oportunidad quieta", Level: "R", Trigger: "Paso del tiempo", Output: "Aviso con la antigüedad", Executor: "S", Status: "implemented", Ref: "biz/kpi.go exceptions"},
	{Code: "VEN-10", Area: "ventas", Name: "Cliente ideal como filtro de entrada", Level: "R", Trigger: "contacto.creado", Output: "Encaje estimado y motivo", Executor: "IA", Requires: []string{"MAR-01"}, Status: "implemented", Ref: "biz/events.go onLeadCreated → agente Comercial"},
	{Code: "VEN-11", Area: "ventas", Name: "Investigación previa del interesado", Level: "R", Trigger: "Reunión agendada", Output: "Ficha de contexto", Executor: "IA", Status: "implemented", Ref: "agente Comercial"},
	{Code: "VEN-12", Area: "ventas", Name: "Proceso de referidos", Level: "R", Trigger: "proyecto.cerrado", Output: "Petición preparada", Executor: "A", Status: "partial", Ref: "plantilla de cierre de proyecto", Sensitive: true},
	{Code: "VEN-13", Area: "ventas", Name: "Recuperación de oportunidades perdidas", Level: "O", Trigger: "Tiempo desde la pérdida", Output: "Toque que corresponde", Executor: "A", Status: "pending", Sensitive: true},
	{Code: "VEN-14", Area: "ventas", Name: "Previsión ponderada", Level: "O", Trigger: "Consulta", Output: "Importe esperado (previsión)", Executor: "S", Status: "implemented", Ref: "biz/kpi.go"},
	{Code: "VEN-15", Area: "ventas", Name: "Comisión al referidor", Level: "O", Trigger: "oportunidad.ganada", Output: "Movimiento pendiente en Finanzas", Executor: "S", Status: "pending"},

	// Entrega
	{Code: "ENT-01", Area: "entrega", Name: "El proyecto nace del cobro, ligado", Level: "E", Trigger: "cobro.confirmado", Output: "Proyecto creado una sola vez", Executor: "S", Requires: []string{"VEN-07"}, Status: "implemented", Ref: "biz/events.go"},
	{Code: "ENT-02", Area: "entrega", Name: "Plantilla de entrega por producto", Level: "E", Trigger: "proyecto.creado", Output: "Plan del proyecto poblado", Executor: "S", Requires: []string{"ENT-01"}, Status: "implemented", Ref: "biz/delivery.go materialize"},
	{Code: "ENT-03", Area: "entrega", Name: "Onboarding y contexto del cliente", Level: "E", Trigger: "proyecto.creado", Output: "Contexto del cliente como dato", Executor: "A", Requires: []string{"ENT-02"}, Status: "implemented", Ref: "tarea de onboarding en plantilla"},
	{Code: "ENT-04", Area: "entrega", Name: "Tareas con planificación y vencimiento distintos", Level: "E", Trigger: "Plan del proyecto", Output: "Tareas repartidas en días laborables", Executor: "S", Status: "implemented", Ref: "issue.start_date / due_date"},
	{Code: "ENT-05", Area: "entrega", Name: "Criterio de terminado y cierre formal", Level: "E", Trigger: "Fin de la última fase", Output: "Proyecto cerrado con balance", Executor: "H", Status: "implemented", Ref: "biz/delivery.go CloseProject"},
	{Code: "ENT-06", Area: "entrega", Name: "Incidencias con investigación de causa", Level: "R", Trigger: "incidencia.registrada", Output: "Causa y cambio de proceso", Executor: "H + IA", Status: "partial", Ref: "etiqueta Incidencia"},
	{Code: "ENT-07", Area: "entrega", Name: "Alerta de proyecto en riesgo o quieto", Level: "E", Trigger: "Paso del tiempo", Output: "Aviso con lo que falta", Executor: "S", Status: "implemented", Ref: "biz/kpi.go exceptions"},
	{Code: "ENT-08", Area: "entrega", Name: "Portal del cliente", Level: "R", Trigger: "onboarding.lanzado", Output: "Vista acotada al cliente", Executor: "S", Status: "pending"},
	{Code: "ENT-09", Area: "entrega", Name: "Actas convertidas en tareas propuestas", Level: "R", Trigger: "sesion.realizada", Output: "Tareas propuestas enlazadas", Executor: "IA", Status: "implemented", Ref: "agente Implementador"},
	{Code: "ENT-10", Area: "entrega", Name: "Capacidad y ocupación por ejecutor", Level: "R", Trigger: "Al planificar", Output: "Holgura disponible", Executor: "S", Status: "implemented", Ref: "biz/kpi.go workload"},
	{Code: "ENT-11", Area: "entrega", Name: "Petición del testimonio en el cierre", Level: "R", Trigger: "proyecto.cerrado", Output: "Petición preparada para Marca", Executor: "A", Status: "partial", Sensitive: true},
	{Code: "ENT-12", Area: "entrega", Name: "Custodia de credenciales del cliente", Level: "R", Trigger: "Onboarding", Output: "Secreto guardado y auditado", Executor: "S", Status: "pending"},
	{Code: "ENT-13", Area: "entrega", Name: "Reglas de servicio y escalado", Level: "O", Trigger: "Incumplimiento", Output: "Escalado disparado", Executor: "S", Status: "pending"},

	// Finanzas
	{Code: "FIN-01", Area: "finanzas", Name: "Movimiento con banco obligatorio", Level: "E", Trigger: "Alta de movimiento", Output: "Rechazo si falta la cuenta", Executor: "S", Status: "implemented", Ref: "biz/finance.go"},
	{Code: "FIN-02", Area: "finanzas", Name: "Factura emitida con precio leído de la oferta", Level: "E", Trigger: "Aceptación autorizada", Output: "Factura numerada", Executor: "S", Requires: []string{"VEN-06"}, Status: "implemented", Ref: "biz/finance.go IssueInvoice", Sensitive: true},
	{Code: "FIN-03", Area: "finanzas", Name: "Condiciones de pago y vencimiento", Level: "E", Trigger: "factura.emitida", Output: "Fecha de vencimiento", Executor: "S", Requires: []string{"FIN-02"}, Status: "implemented", Ref: "biz/finance.go"},
	{Code: "FIN-04", Area: "finanzas", Name: "Cobro pendiente y reclamación escalonada", Level: "E", Trigger: "Vencimiento cumplido", Output: "Aviso y reclamación redactada", Executor: "A", Requires: []string{"FIN-03"}, Status: "implemented", Ref: "excepciones + agente Financiero", Sensitive: true},
	{Code: "FIN-05", Area: "finanzas", Name: "Meses de caja", Level: "E", Trigger: "Cambio de saldo o gasto", Output: "Runway con su alerta", Executor: "S", Requires: []string{"FIN-01"}, Status: "implemented", Ref: "biz/kpi.go runway"},
	{Code: "FIN-06", Area: "finanzas", Name: "Margen por proyecto", Level: "R", Trigger: "Consulta", Output: "Margen por proyecto y producto", Executor: "S", Status: "partial", Ref: "biz/kpi.go margin"},
	{Code: "FIN-07", Area: "finanzas", Name: "Conciliación bancaria por extracto", Level: "R", Trigger: "Importación", Output: "Movimientos casados y diferencias", Executor: "S + A", Requires: []string{"FIN-01"}, Status: "implemented", Ref: "biz/finance.go ImportStatement/Reconcile"},
	{Code: "FIN-08", Area: "finanzas", Name: "Gasto separado de inversión", Level: "R", Trigger: "Alta de movimiento", Output: "Clasificación", Executor: "S", Status: "partial", Ref: "naturaleza del movimiento"},
	{Code: "FIN-09", Area: "finanzas", Name: "Calendario de obligaciones y paquete para la gestoría", Level: "R", Trigger: "Fecha del calendario", Output: "Paquete trimestral trazable", Executor: "A", Requires: []string{"FIN-07"}, Status: "implemented", Ref: "biz/finance.go PreparePeriod"},
	{Code: "FIN-10", Area: "finanzas", Name: "Contrato desde plantilla", Level: "E", Trigger: "oportunidad.aceptada", Output: "Contrato listo para firma", Executor: "S", Status: "partial", Ref: "instantánea de condiciones en la propuesta"},
	{Code: "FIN-11", Area: "finanzas", Name: "Multidivisa y regímenes por país", Level: "O", Trigger: "País del cliente", Output: "Importes e impuestos correctos", Executor: "S", Status: "pending"},
	{Code: "FIN-12", Area: "finanzas", Name: "Previsión de tesorería", Level: "O", Trigger: "Consulta", Output: "Caja proyectada por semanas", Executor: "S", Status: "implemented", Ref: "biz/kpi.go cashflow"},

	// Marca
	{Code: "MAR-01", Area: "marca", Name: "Identidad y mensaje en un solo sitio", Level: "E", Trigger: "Una vez, y se revisa", Output: "Activo de marca referenciado", Executor: "H", Status: "implemented", Ref: "carpeta Marca/Identidad.md"},
	{Code: "MAR-02", Area: "marca", Name: "Calendario editorial con pilares", Level: "E", Trigger: "Planificación", Output: "Piezas por pilar y fecha", Executor: "S", Status: "implemented", Ref: "biz/brand.go"},
	{Code: "MAR-03", Area: "marca", Name: "Pieza de contenido con estado", Level: "E", Trigger: "Alta de idea", Output: "Recorrido trazable", Executor: "S", Status: "implemented", Ref: "biz/brand.go"},
	{Code: "MAR-04", Area: "marca", Name: "Publicación por API y registro del resultado", Level: "R", Trigger: "Fecha programada", Output: "Publicación con evidencia", Executor: "A", Status: "simulated", Ref: "sin red social conectada: evidencia manual", Sensitive: true},
	{Code: "MAR-05", Area: "marca", Name: "Caso de cliente con cifra", Level: "R", Trigger: "testimonio.solicitado", Output: "Caso publicable", Executor: "A + H", Status: "partial", Sensitive: true},
	{Code: "MAR-06", Area: "marca", Name: "Escucha convertida en conversaciones", Level: "R", Trigger: "Actividad en el canal", Output: "Conversación con origen", Executor: "A", Status: "implemented", Ref: "biz/brand.go conversations"},
	{Code: "MAR-07", Area: "marca", Name: "Conversación cualificada pasa a Ventas", Level: "R", Trigger: "conversacion.cualificada", Output: "contacto.creado con origen real", Executor: "A", Requires: []string{"VEN-01"}, Status: "implemented", Ref: "biz/brand.go QualifyConversation"},
	{Code: "MAR-08", Area: "marca", Name: "KPI de conversaciones cualificadas", Level: "E", Trigger: "Continuo", Output: "El número del área", Executor: "S", Status: "implemented", Ref: "biz/kpi.go"},
	{Code: "MAR-09", Area: "marca", Name: "Banco de material", Level: "R", Trigger: "Continuo", Output: "Material localizable", Executor: "S", Status: "partial", Ref: "carpeta Marca/Material"},
	{Code: "MAR-10", Area: "marca", Name: "Guiones propuestos", Level: "O", Trigger: "A petición", Output: "Borradores por pilar", Executor: "IA", Status: "implemented", Ref: "agente de Marca"},
	{Code: "MAR-11", Area: "marca", Name: "Reutilización en varios formatos", Level: "O", Trigger: "contenido.publicado", Output: "Versiones derivadas propuestas", Executor: "IA", Status: "implemented", Ref: "agente de Marca"},
	{Code: "MAR-12", Area: "marca", Name: "Atribución de contacto a pieza", Level: "R", Trigger: "contacto.creado", Output: "Origen ligado a la pieza", Executor: "S", Status: "implemented", Ref: "source_content_id"},

	// Equipo
	{Code: "EQU-01", Area: "equipo", Name: "Ficha de rol", Level: "E", Trigger: "Al crear un rol", Output: "Rol antes que su ocupante", Executor: "H", Status: "implemented", Ref: "biz/team.go"},
	{Code: "EQU-02", Area: "equipo", Name: "Mapa de roles con dueño", Level: "E", Trigger: "Asignación", Output: "Quién responde de cada área", Executor: "S", Requires: []string{"EQU-01"}, Status: "implemented", Ref: "biz/team.go"},
	{Code: "EQU-03", Area: "equipo", Name: "Vista por rol", Level: "E", Trigger: "Entrada al sistema", Output: "Proyección filtrada por políticas", Executor: "S", Requires: []string{"EQU-02"}, Status: "partial", Ref: "perspectivas Ejecución/Área/Empresa"},
	{Code: "EQU-04", Area: "equipo", Name: "Registro de trabajadores agénticos", Level: "E", Trigger: "Alta de un agente", Output: "El agente como miembro con rol, permisos y coste", Executor: "S", Status: "implemented", Ref: "biz_agent + agentes Multica"},
	{Code: "EQU-05", Area: "equipo", Name: "Bitácora auditable de acciones de agentes", Level: "E", Trigger: "Toda acción de un agente", Output: "Registro quién/qué/resultado", Executor: "S", Status: "implemented", Ref: "biz_audit"},
	{Code: "EQU-06", Area: "equipo", Name: "Permisos por agente: solo o con visto bueno", Level: "E", Trigger: "Intento de acción", Output: "Ejecución o petición de aprobación", Executor: "S", Requires: []string{"EQU-04"}, Status: "implemented", Ref: "biz/guard.go"},
	{Code: "EQU-07", Area: "equipo", Name: "Salud de cada pieza automática", Level: "E", Trigger: "Cada ejecución y su ausencia", Output: "Estado y aviso sin señal", Executor: "S", Status: "implemented", Ref: "biz/team.go health"},
	{Code: "EQU-08", Area: "equipo", Name: "Plan de incorporación", Level: "R", Trigger: "Alta de miembro", Output: "Pasos hasta que rinde solo", Executor: "A", Status: "partial"},
	{Code: "EQU-09", Area: "equipo", Name: "Rutina de equipo mensual", Level: "R", Trigger: "Mensual", Output: "Pregunta contestada por escrito", Executor: "A", Status: "implemented", Ref: "rutina month"},
	{Code: "EQU-10", Area: "equipo", Name: "Ocupación por ejecutor, personas y agentes", Level: "R", Trigger: "Al planificar", Output: "Holgura real en unidades separadas", Executor: "S", Status: "implemented", Ref: "biz/kpi.go workload"},
	{Code: "EQU-11", Area: "equipo", Name: "Evaluación y salida con retirada de accesos", Level: "O", Trigger: "Fin de la relación", Output: "Accesos cerrados", Executor: "H + S", Status: "pending"},
	{Code: "EQU-12", Area: "equipo", Name: "Promoción de capacidades", Level: "R", Trigger: "Periódica", Output: "Propuesta de bajar de ejecutor", Executor: "IA", Status: "partial", Ref: "agente de Equipo sobre la bitácora"},
	{Code: "EQU-13", Area: "equipo", Name: "Coste por agente y presupuesto", Level: "R", Trigger: "Cada ejecución", Output: "Coste por agente y área", Executor: "S", Status: "implemented", Ref: "task_usage + biz_agent.budget"},
}

func CapabilityByCode(code string) (Capability, bool) {
	for _, c := range Capabilities {
		if c.Code == code {
			return c, true
		}
	}
	return Capability{}, false
}

// KPIDefault seeds biz_kpi. Values are computed in kpi.go, never stored.
type KPIDefault struct {
	Code, Area, Name, Unit, Formula, Direction, Period string
	Target, Alert                                    *float64
}

func f(v float64) *float64 { return &v }

var DefaultKPIs = []KPIDefault{
	{Code: "DIR-OBJ", Area: "direccion", Name: "Objetivos del trimestre en trayectoria", Unit: "%", Formula: "objetivos en trayectoria / objetivos activos", Direction: "up", Period: "quarter", Target: f(80), Alert: f(50)},
	{Code: "DIR-DEC", Area: "direccion", Name: "Decisiones abiertas", Unit: "n", Formula: "decisiones con estado abierta", Direction: "down", Period: "now", Target: f(3), Alert: f(8)},
	{Code: "DIR-APR", Area: "direccion", Name: "Aprobaciones pendientes", Unit: "n", Formula: "aprobaciones pendientes", Direction: "down", Period: "now", Target: f(3), Alert: f(10)},
	{Code: "VEN-PIPE", Area: "ventas", Name: "Cartera abierta", Unit: "EUR", Formula: "suma del valor de oportunidades abiertas", Direction: "up", Period: "now"},
	{Code: "VEN-FCST", Area: "ventas", Name: "Previsión ponderada", Unit: "EUR", Formula: "Σ valor × probabilidad de la etapa (previsión)", Direction: "up", Period: "now"},
	{Code: "VEN-WON", Area: "ventas", Name: "Ventas cobradas del mes", Unit: "EUR", Formula: "Σ valor de oportunidades ganadas (cobro confirmado) en el mes", Direction: "up", Period: "month", Target: f(6000), Alert: f(3000)},
	{Code: "VEN-CONV", Area: "ventas", Name: "Conversión propuesta → aceptada", Unit: "%", Formula: "aceptadas+ganadas / con propuesta (90 días)", Direction: "up", Period: "90d", Target: f(40), Alert: f(20)},
	{Code: "VEN-STALE", Area: "ventas", Name: "Oportunidades quietas (>14 días)", Unit: "n", Formula: "abiertas sin contacto en 14 días", Direction: "down", Period: "now", Target: f(0), Alert: f(3)},
	{Code: "ENT-ONTIME", Area: "entrega", Name: "Tareas de entrega a tiempo", Unit: "%", Formula: "tareas hechas antes del vencimiento / hechas con vencimiento (30 días)", Direction: "up", Period: "30d", Target: f(90), Alert: f(75)},
	{Code: "ENT-OVERDUE", Area: "entrega", Name: "Tareas vencidas", Unit: "n", Formula: "tareas abiertas con vencimiento pasado", Direction: "down", Period: "now", Target: f(0), Alert: f(5)},
	{Code: "ENT-ACTIVE", Area: "entrega", Name: "Proyectos activos", Unit: "n", Formula: "proyectos en curso ligados a un servicio", Direction: "range", Period: "now"},
	{Code: "FIN-CASH", Area: "finanzas", Name: "Caja disponible", Unit: "EUR", Formula: "saldo inicial + movimientos importados (desconocido sin saldo inicial)", Direction: "up", Period: "now"},
	{Code: "FIN-RUNWAY", Area: "finanzas", Name: "Meses de caja (runway)", Unit: "meses", Formula: "caja disponible / salida fija mensual normalizada (media 3 meses)", Direction: "up", Period: "now", Target: f(3), Alert: f(2)},
	{Code: "FIN-AR", Area: "finanzas", Name: "Cobros vencidos", Unit: "EUR", Formula: "Σ pendiente de facturas emitidas vencidas", Direction: "down", Period: "now", Target: f(0), Alert: f(1000)},
	{Code: "FIN-UNREC", Area: "finanzas", Name: "Movimientos sin conciliar", Unit: "n", Formula: "movimientos sin conciliar ni ignorar", Direction: "down", Period: "now", Target: f(0), Alert: f(10)},
	{Code: "FIN-MARGIN", Area: "finanzas", Name: "Margen de gestión del mes", Unit: "%", Formula: "(ingresos facturados − gastos recibidos) / ingresos (devengo)", Direction: "up", Period: "month", Target: f(30), Alert: f(15)},
	{Code: "MAR-QCONV", Area: "marca", Name: "Conversaciones cualificadas del mes", Unit: "n", Formula: "conversaciones cualificadas en el mes", Direction: "up", Period: "month", Target: f(8), Alert: f(3)},
	{Code: "MAR-PUB", Area: "marca", Name: "Piezas publicadas del mes", Unit: "n", Formula: "contenidos publicados con evidencia en el mes", Direction: "up", Period: "month", Target: f(6), Alert: f(2)},
	{Code: "EQU-HEALTH", Area: "equipo", Name: "Agentes sanos", Unit: "%", Formula: "agentes sin fallo en su última ejecución / agentes de área", Direction: "up", Period: "now", Target: f(100), Alert: f(80)},
	{Code: "EQU-COST", Area: "equipo", Name: "Coste de agentes del mes", Unit: "USD", Formula: "Σ coste de ejecuciones registrado por el proveedor", Direction: "down", Period: "month"},
	{Code: "EQU-ROLES", Area: "equipo", Name: "Roles con ocupante", Unit: "%", Formula: "roles con ocupante / roles", Direction: "up", Period: "now", Target: f(100), Alert: f(70)},
}
