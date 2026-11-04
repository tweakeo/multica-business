---
tls_type: draft
tls_schema: 1
id: "{{id}}"
tipo: correo
accion: enviar_correo
motivo: recordatorio_cobro
estado: Borrador
para: ["{{empresa.email_facturacion}}"]
asunto: "Factura {{factura.numero}}: recordatorio"
factura: "{{factura.enlace}}"
empresa: "{{empresa.enlace}}"
creado_por: "{{yo}}"
plantilla: "Recordatorio de cobro v1"
---
# Factura {{factura.numero}}: recordatorio
> {{estado}} · {{factura.pendiente:€}} pendientes · venció el {{factura.vence:corta}}

## Mensaje
Hola, {{contacto.nombre}}:

Te escribo por la factura {{factura.numero}}, de {{factura.total:€}}, que venció el {{factura.vence:larga}}. Por lo que vemos en el banco, aún no nos ha llegado.

Si ya la habéis pagado, ignora este mensaje y perdona la molestia. Si no, puedes hacer la transferencia a la cuenta {{emisor.cuenta}}. Te adjunto la factura otra vez.

Gracias,
{{yo.nombre}}
{{mi_empresa.nombre}}

## Para ti
> Guía: se prepara cuando una factura vence. Al mismo tiempo aparece en Decisiones «¿Seguimos entregando?». La cuenta del emisor no se escribe en la nota: la app la pone en el correo al enviarlo, con tu OK.
