---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo                    # correo | mensaje | publicacion
accion: enviar_correo           # enviar_correo | escribir_cliente | publicar
estado: Borrador                # Borrador | Pendiente de tu OK | Aprobado | Enviado | Descartado (lo refleja la app)
para: []
asunto: "{{asunto}}"
en_respuesta_a:
tarea: "{{tarea.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
proyecto: "{{proyecto.enlace}}"
empresa: "{{empresa.enlace}}"
creado_por: "{{yo}}"
plantilla: "Borrador de mensaje v1"
---
# {{asunto}}
> {{estado}} · para {{para}} · {{tipo}}

## Mensaje
Hola, {{contacto.nombre}}:

{{cursor}}

Un saludo,
{{yo.nombre}}
{{mi_empresa.nombre}}

## Para ti
> Guía: esto no se envía. Por qué este mensaje, qué datos cita y qué falta. Enviar siempre pide tu OK.
