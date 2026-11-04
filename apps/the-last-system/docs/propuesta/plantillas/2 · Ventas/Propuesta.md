---
tls_type: proposal
tls_schema: 1
id: "{{id}}"
ref: "PR-{{fecha}}-{{empresa.slug}}"
oportunidad: "{{oportunidad.enlace}}"
reunion: "{{reunion.enlace}}"   # la reunión de descubrimiento de la que sale el borrador
version: "{{version}}"
estado: Borrador                # Borrador | Aprobada | Enviada | Aceptada | Rechazada | Caducada
fecha: "{{fecha}}"
valida_hasta: "{{fecha+14}}"
empresa: "{{empresa.enlace}}"
contacto: "{{contacto.enlace}}"
servicio: "{{servicio.enlace}}"
oferta_version: "{{oferta.enlace}}"
iva_pct: "{{oferta.iva_pct}}"
retencion_pct:
base:
cuota_iva:
retencion:
total:
pdf:
pdf_sha256:
origen: manual                  # manual | agente:comercial (generada desde la reunión de descubrimiento)
plantilla: "Propuesta v1"
---
# Propuesta para {{empresa.nombre}}
> {{estado}} · {{total:€}} · válida hasta el {{valida_hasta:corta}} · versión {{version}}

> Guía: el borrador lo genera el asistente Comercial al marcar Hecha la reunión de descubrimiento. «Lo que nos contaste» sale de sus notas; Incluye, No incluye, precio y pagos, de la versión de la oferta; el calendario, del plan de entrega; y la forma, de las propuestas que el sistema Embudo tiene en Referencias y ejemplos. Lo que no esté en la reunión ni en la oferta queda «[falta: …]», nunca inventado. Tú la revisas, la apruebas y la envías: nunca sale sola.

## Lo que nos contaste
> Guía: sale de «Qué se habló» y «Lo que salió» de la reunión de descubrimiento: la frase destino literal y los dolores, con sus palabras. Nada que el cliente no haya dicho.

## Lo que proponemos
> Guía: el servicio que encaja (de «Lo que salió») y el resultado que promete, en dos o tres frases.

## Incluye

## No incluye
> Guía: «Incluye» y «No incluye» se copian de la versión de la oferta. Se baja de alcance, no de precio.

## Calendario
| Fase | Qué hacemos | Cuándo |
|---|---|---|
| {{fase.nombre}} | {{fase.resumen}} | {{fase.cuando}} |

## Inversión
| Concepto | Cantidad | Precio | IVA | Importe |
|---|---|---|---|---|
| {{linea.concepto}} | {{linea.cantidad}} | {{linea.precio:€}} | {{linea.iva_pct:%}} | {{linea.importe:€}} |

| Total | Importe |
|---|---|
| Base imponible | {{base:€}} |
| IVA {{iva_pct:%}} | {{cuota_iva:€}} |
| Retención IRPF {{retencion_pct:%}} | −{{retencion:€}} |
| **Total** | **{{total:€}}** |

> Guía: el precio sale de la versión de la oferta; no se teclea. La retención solo aparece si el emisor es profesional y el cliente es empresa o profesional.

## Pagos
| Pago | Cuándo | Base | IVA | Retención | Total |
|---|---|---|---|---|---|
| {{pago.nombre}} ({{pago.pct:%}}) | {{pago.cuando}} | {{pago.base:€}} | {{pago.iva:€}} | −{{pago.retencion:€}} | {{pago.total:€}} |

## Condiciones
> Guía: las condiciones de cobro del servicio y lo esencial del acuerdo. El texto completo va en el contrato.

## Siguientes pasos
1. Nos dices que sí respondiendo a este correo.
2. Te enviamos el acuerdo y la factura del primer pago.
3. Con el pago confirmado, cerramos la fecha de la primera sesión en menos de 48 horas.

## Aceptación
> Guía: cómo se acepta (con el pago o con firma) y qué pasa si caduca.

## Para ti (no se envía)
| Qué | De dónde sale |
|---|---|
| Frase destino y dolores | {{reunion.enlace}}, «Lo que salió» |
| Incluye, no incluye, precio y pagos | {{oferta.enlace}} |
| Calendario | Plan de entrega de {{servicio.enlace}} |
| Lo que falta o hay que decidir | |

> Guía: la deja el asistente al generar el borrador. No sale en el PDF ni en el correo. Si cambias algo al revisar, la diferencia es la pista para su «¿qué aprendimos?».
