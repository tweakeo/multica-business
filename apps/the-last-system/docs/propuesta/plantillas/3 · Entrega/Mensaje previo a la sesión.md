---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo
accion: escribir_cliente
motivo: mensaje_previo
estado: Borrador
para: ["{{contacto.email}}"]
asunto: "{{sesion.nombre}}: {{sesion.fecha:larga}}"
proyecto: "{{proyecto.enlace}}"
reunion: "{{reunion.enlace}}"
creado_por: "{{yo}}"
plantilla: "Mensaje previo a la sesión v1"
---
# {{sesion.nombre}}: {{sesion.fecha:larga}}
> {{estado}} · para {{contacto.nombre}} · se envía 24 h antes

## Mensaje
Hola, {{contacto.nombre}}:

Mañana a las {{sesion.hora}} tenemos tu sesión de {{sesion.nombre_cliente}}. Antes, dedica {{video.minutos}} minutos a este vídeo: {{video.enlace}}

Si te da tiempo, rellena esto: {{recogida.enlace}}. Si no, no pasa nada: lo vemos juntos.

Enlace para entrar: {{sesion.enlace}}

Hasta mañana,
{{yo.nombre}}

## Para ti
> Guía: corto y con un solo enlace principal. Nada de vocabulario interno: se dice «tu sesión de flujos», no «S3» ni «kit».
