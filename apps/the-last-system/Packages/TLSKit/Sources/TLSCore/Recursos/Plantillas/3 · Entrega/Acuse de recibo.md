---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo
accion: escribir_cliente
motivo: acuse_incidencia
estado: Borrador
para: ["{{contacto.email}}"]
asunto: "Lo hemos recibido: {{incidencia.titulo}}"
proyecto: "{{proyecto.enlace}}"
incidencia: "{{incidencia.enlace}}"
creado_por: "{{yo}}"
plantilla: "Acuse de recibo v1"
---
# Lo hemos recibido: {{incidencia.titulo}}
> {{estado}} · para {{contacto.nombre}} · {{incidencia.numero}} · {{incidencia.gravedad}}

## Mensaje
Hola, {{contacto.nombre}}:

Hemos recibido lo que nos cuentas sobre {{incidencia.resumen}}. Ya está en manos de {{responsable.nombre}} y te diremos algo antes del {{incidencia.plazo:larga}}.

Si mientras tanto cambia algo, responde a este correo.

Un saludo,
{{yo.nombre}}

## Para ti
> Guía: se prepara al registrar la incidencia. Con el cliente no se dice «incidencia»: se dice «duda», «bloqueo» o «problema».
