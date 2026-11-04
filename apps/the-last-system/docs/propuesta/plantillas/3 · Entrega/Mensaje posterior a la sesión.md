---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo
accion: escribir_cliente
motivo: mensaje_posterior
estado: Borrador
para: ["{{contacto.email}}"]
asunto: "Lo que hicimos hoy y lo siguiente"
proyecto: "{{proyecto.enlace}}"
reunion: "{{reunion.enlace}}"
creado_por: "{{yo}}"
plantilla: "Mensaje posterior a la sesión v1"
---
# Lo que hicimos hoy y lo siguiente
> {{estado}} · para {{contacto.nombre}} · después de {{sesion.nombre}}

## Mensaje
Hola, {{contacto.nombre}}:

Gracias por la sesión de hoy. En resumen:

- Lo que hicimos: {{acta.resumen}}
- Lo que ya queda aplicado: {{acta.aplicado}}
- Lo siguiente: {{siguiente_sesion.nombre_cliente}}, el {{siguiente_sesion.fecha:larga}}.

{{tareas_cliente}}

Tienes todo en tu portal: {{portal.enlace}}

Un saludo,
{{yo.nombre}}

## Para ti
> Guía: sale del acta. Si se le pide algo al cliente, como mucho tres cosas y con fecha. Se envía en menos de 24 h.
