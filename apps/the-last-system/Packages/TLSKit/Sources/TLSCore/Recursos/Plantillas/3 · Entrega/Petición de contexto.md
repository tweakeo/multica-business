---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo
accion: escribir_cliente
motivo: pedir_contexto
estado: Borrador
para: ["{{contacto.email}}"]
asunto: "Para preparar tu primera sesión"
proyecto: "{{proyecto.enlace}}"
creado_por: "{{yo}}"
plantilla: "Petición de contexto v1"
---
# Para preparar tu primera sesión
> {{estado}} · para {{contacto.nombre}} · {{proyecto.nombre}}

## Mensaje
Hola, {{contacto.nombre}}:

Para que la primera sesión sea práctica desde el minuto uno, nos ayudaría tener esto antes del {{primera_sesion:larga}}. No hace falta que esté perfecto; con lo que tengas, vale:

1. Qué vendes y a quién (una o dos frases).
2. Cómo trabajas hoy: un vídeo de pantalla de 10 minutos enseñando dónde apuntas clientes, trabajos y facturas.
3. Tu logo (mejor en SVG o en PNG grande) y tu manual de marca, si lo tienes.

Lo que ya nos contaste en el diagnóstico no te lo volvemos a pedir.

Un saludo,
{{yo.nombre}}

## Para ti
> Guía: no se pide nada que ya esté en el diagnóstico o la propuesta. Con lo que llegue, el asistente comprueba si el contexto basta, lo resume, prepara el diagnóstico de arranque y un plan de 30 días, sin repetir pasos. Nunca se piden contraseñas.
