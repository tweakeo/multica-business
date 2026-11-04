---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo                    # correo | mensaje
accion: escribir_cliente
motivo: ofrecer_diagnostico     # ofrecer_diagnostico | enviar_propuesta | confirmar_cita | otro
estado: Borrador                # Borrador | Pendiente de tu OK | Aprobado | Enviado | Descartado (lo refleja la app)
para: ["{{contacto.email}}"]
asunto: "{{asunto}}"
oportunidad: "{{oportunidad.enlace}}"
tarea: "{{tarea.enlace}}"
creado_por: "{{yo}}"
plantilla: "Mensaje v1"
---
# {{asunto}}
> {{estado}} · para {{contacto.nombre}} · {{motivo}}

## Mensaje
Hola, {{contacto.nombre}}:

Gracias por escribirnos. Por lo que nos cuentas, lo más útil es una sesión de diagnóstico de 60 minutos: salimos con tu cuello de botella claro y con el siguiente paso, lo hagamos juntos o no.

¿Te va bien el {{hueco.1}} o el {{hueco.2}}?

Un saludo,
{{yo.nombre}}
{{mi_empresa.nombre}}

## Para ti
> Guía: esto no se envía. Qué frase suya cita, por qué estos huecos y qué falta. Una sola llamada a la acción por mensaje. Enviar siempre pide tu OK.
