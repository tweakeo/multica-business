---
tls_type: invoice
tls_schema: 1
id: "{{id}}"
numero:                         # vacío hasta emitir; después F-AAAA-NNNN
serie: F
estado: Borrador                # Borrador | Emitida | Enviada | Cobrada | Rectificada
fecha:                          # fecha de expedición: se pone al emitir
fecha_operacion: "{{fecha}}"
vence:                          # fecha de emisión + días de las condiciones de cobro
empresa: "{{empresa.enlace}}"
contacto: "{{contacto.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
proyecto: "{{proyecto.enlace}}"
servicio: "{{servicio.enlace}}"
oferta_version: "{{oferta.enlace}}"
hito: inicial                   # inicial | final | unico | recurrente
periodo:                        # solo si es recurrente: «T4 2026», «octubre 2026»
iva_pct: "{{oferta.iva_pct}}"
retencion_pct:                  # la decide la configuración según emisor y cliente
base:
cuota_iva:
retencion:
total:
forma_pago: transferencia       # transferencia | domiciliación | tarjeta | efectivo
pdf:
pdf_sha256:
plantilla: "Factura v1"
---
# Factura {{numero}}
> {{estado}} · {{total:€}} · vence el {{vence:corta}} · {{empresa.nombre}}

## Partes
| Dato | Emisor | Cliente |
|---|---|---|
| Nombre | {{mi_empresa.nombre}} | {{empresa.razon_social}} |
| NIF | En el PDF | {{empresa.nif}} |
| Domicilio | En el PDF | {{empresa.domicilio}}, {{empresa.cp}} {{empresa.ciudad}} |
| Contacto | | {{contacto.nombre}} · {{empresa.email_facturacion}} |

> Guía: los datos fiscales y la cuenta del emisor no se escriben en la nota: la app los pone en el PDF desde Ajustes › Facturación.

## Conceptos
| Concepto | Cantidad | Precio | Dto. | IVA | Importe |
|---|---|---|---|---|---|
| {{linea.concepto}} | {{linea.cantidad}} | {{linea.precio:€}} | {{linea.descuento:%}} | {{linea.iva_pct:%}} | {{linea.importe:€}} |

> Guía: esta tabla es la fuente de las líneas. Importe = cantidad × precio − descuento. Los precios salen de la propuesta aceptada; no se teclean.

## Totales
| Concepto | Importe |
|---|---|
| Base imponible | {{base:€}} |
| IVA {{iva_pct:%}} | {{cuota_iva:€}} |
| Retención IRPF {{retencion_pct:%}} | −{{retencion:€}} |
| **Total a pagar** | **{{total:€}}** |

> Guía: si hay líneas con distintos tipos de IVA, va una fila de IVA por tipo. Total = base + IVA − retención. La app recalcula al guardar y avisa si alguien cambió un total a mano.

## Forma de pago
Pago por {{forma_pago}} antes del {{vence:larga}}. {{servicio.condiciones_cobro}}

## Notas

## Historial
> Guía: solo se añade. `- AAAA-MM-DD · qué pasó · quién`. Emitir y enviar siempre piden tu OK; el cobro solo cuenta con el movimiento del banco confirmado por una persona.
