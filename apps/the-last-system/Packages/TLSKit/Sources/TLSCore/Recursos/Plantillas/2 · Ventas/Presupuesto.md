---
tls_type: quote
tls_schema: 1
id: "{{id}}"
numero:                         # P-AAAA-NNNN: lo da el contador al aprobarlo
oportunidad: "{{oportunidad.enlace}}"
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
plantilla: "Presupuesto v1"
---
# Presupuesto {{numero}}
> {{estado}} · {{total:€}} · válido hasta el {{valida_hasta:corta}} · {{empresa.nombre}}

## Para
| Dato | Valor |
|---|---|
| Cliente | {{empresa.razon_social}} |
| NIF | {{empresa.nif}} |
| Contacto | {{contacto.nombre}} · {{contacto.email}} |

## Conceptos
| Concepto | Cantidad | Precio | Dto. | IVA | Importe |
|---|---|---|---|---|---|
| {{linea.concepto}} | {{linea.cantidad}} | {{linea.precio:€}} | {{linea.descuento:%}} | {{linea.iva_pct:%}} | {{linea.importe:€}} |

## Totales
| Concepto | Importe |
|---|---|
| Base imponible | {{base:€}} |
| IVA {{iva_pct:%}} | {{cuota_iva:€}} |
| Retención IRPF {{retencion_pct:%}} | −{{retencion:€}} |
| **Total** | **{{total:€}}** |

## Validez y forma de pago
Válido hasta el {{valida_hasta:larga}}. {{servicio.condiciones_cobro}}

## Aceptación
> Guía: «Para aceptarlo, responde a este correo». Al aceptarlo, la oportunidad pasa a Aceptada y se preparan el contrato y la factura.
