---
tls_type: task
tls_schema: 1
id: "{{id}}"
numero: "{{numero}}"
titulo: "{{titulo}}"
estado: En revisión             # una pregunta nace esperando tu respuesta
tipo: pregunta
responsable: "{{yo}}"           # la persona que tiene que responder
vence:
area: "{{area}}"
proyecto: "{{proyecto.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
capacidad:
origen: "agente:{{asistente}}"
creada: "{{fecha}}"
creada_por: "agente:{{asistente}}"
plantilla: "Pregunta de asistente v1"
---
# {{titulo}}
> Pregunta de {{asistente.nombre}} (asistente) · espera tu respuesta

## Pregunta
> Guía: una sola pregunta, que se pueda contestar en una línea.

## Por qué la hago
> Guía: qué estaba haciendo y qué dato me falta para seguir.

## Lo que propongo
> Guía: si hay una respuesta probable, va aquí para que solo tengas que confirmarla.

## Actividad
