---
tls_type: task
tls_schema: 1
id: "{{id}}"
numero: "{{numero}}"
titulo: "Seguimiento día {{dia}} · {{oportunidad.nombre}}"
estado: Sin programar           # pasa sola a «Por hacer» el día de despertar
tipo: tarea
responsable: "agente:comercial"
despertar: "{{fecha+7}}"
vence:
area: ventas
oportunidad: "{{oportunidad.enlace}}"
empresa: "{{empresa.enlace}}"
capacidad: VEN-08
origen: "regla:propuesta.enviada"
creada: "{{fecha}}"
creada_por: sistema
plantilla: "Seguimiento v1"
---
# Seguimiento día {{dia}} · {{oportunidad.nombre}}
> {{estado}} · despierta el {{despertar:corta}} · propuesta enviada el {{propuesta.fecha:corta}}

## Descripción
| Día | Qué toca |
|---|---|
| 7 | Recordar la propuesta con una sola pregunta |
| 14 | Aportar algo útil: un dato, un caso o una respuesta a su duda |
| 21 | Última pregunta directa: «¿Lo dejamos para más adelante?» |
| 30 | Proponer pasarla a Perdida, con su motivo |

> Guía: el asistente Comercial prepara el mensaje del día que toque; enviarlo siempre pide tu OK. Si la oportunidad cambia de estado, los seguimientos pendientes se cancelan solos. Este sistema puede estar apagado (en The Last lo está).

## Actividad
