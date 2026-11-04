---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo
accion: escribir_cliente
motivo: continuidad
estado: Borrador
para: ["{{contacto.email}}"]
asunto: "El siguiente paso para {{empresa.nombre}}"
proyecto: "{{proyecto.enlace}}"
empresa: "{{empresa.enlace}}"
servicio: "{{servicio.enlace}}"
creado_por: "{{yo}}"
plantilla: "Mensaje de continuidad v1"
---
# El siguiente paso para {{empresa.nombre}}
> {{estado}} · para {{contacto.nombre}} · propone {{servicio.nombre}}

## Mensaje
Hola, {{contacto.nombre}}:

En estas semanas hemos conseguido {{resultado.1}} y {{resultado.2}}. Lo siguiente que más te ayudaría es {{servicio.promesa}}.

Si te encaja, te preparo una propuesta corta. ¿Lo vemos {{hueco.1}}?

Un saludo,
{{yo.nombre}}

## Para ti
> Guía: enseña dos o tres resultados antes de proponer nada. El siguiente paso sale de la Oferta; si no hay uno que encaje, no se envía.
