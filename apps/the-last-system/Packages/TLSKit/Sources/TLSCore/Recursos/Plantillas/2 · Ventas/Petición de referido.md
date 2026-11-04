---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo
accion: escribir_cliente
motivo: pedir_referido
estado: Borrador
para: ["{{contacto.email}}"]
asunto: "¿Conoces a alguien a quien le venga bien?"
proyecto: "{{proyecto.enlace}}"
empresa: "{{empresa.enlace}}"
creado_por: "{{yo}}"
plantilla: "Petición de referido v1"
---
# ¿Conoces a alguien a quien le venga bien?
> {{estado}} · para {{contacto.nombre}} · tras el cierre de {{proyecto.nombre}}

## Mensaje
Hola, {{contacto.nombre}}:

Me alegra ver que {{resultado}}. Si conoces a alguien que esté como estabas tú al empezar, me encantaría que nos presentaras. Basta con que me digas su nombre y le escribo yo, sin compromiso para nadie.

Gracias por la confianza,
{{yo.nombre}}

## Para ti
> Guía: solo se pide con un resultado que enseñar. Cita el resultado con su cifra y su evidencia del Cierre. Si alguien te presenta a una persona, la oportunidad nueva lleva «referido por».
