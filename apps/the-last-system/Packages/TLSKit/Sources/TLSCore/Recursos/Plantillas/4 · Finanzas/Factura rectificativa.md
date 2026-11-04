---
tls_type: invoice
tls_schema: 1
id: "{{id}}"
numero:                         # vacío hasta emitir; después R-AAAA-NNNN
serie: R
estado: Borrador                # Borrador | Emitida | Enviada | Cobrada
rectifica: "{{factura.enlace}}" # la factura original, que pasará a Rectificada
rectifica_numero: "{{factura.numero}}"
rectifica_fecha: "{{factura.fecha}}"
metodo: diferencias             # diferencias | sustitucion
motivo: ""
fecha:
fecha_operacion: "{{factura.fecha_operacion}}"
empresa: "{{factura.empresa}}"
proyecto: "{{factura.proyecto}}"
iva_pct: "{{factura.iva_pct}}"
retencion_pct: "{{factura.retencion_pct}}"
base:
cuota_iva:
retencion:
total:                          # negativo si devuelve dinero
forma_pago:
pdf:
pdf_sha256:
plantilla: "Factura rectificativa v1"
---
# Factura rectificativa {{numero}}
> {{estado}} · {{total:€}} · rectifica la {{rectifica_numero}} del {{rectifica_fecha:corta}}

## Qué rectifica
Rectifica la factura {{rectifica_numero}} del {{rectifica_fecha:larga}}.

## Motivo
> Guía: qué estaba mal, en una o dos frases.

## Partes
| Dato | Emisor | Cliente |
|---|---|---|
| Nombre | {{mi_empresa.nombre}} | {{empresa.razon_social}} |
| NIF | En el PDF | {{empresa.nif}} |
| Domicilio | En el PDF | {{empresa.domicilio}}, {{empresa.cp}} {{empresa.ciudad}} |

## Conceptos
| Concepto | Cantidad | Precio | Dto. | IVA | Importe |
|---|---|---|---|---|---|
| {{linea.concepto}} | {{linea.cantidad}} | {{linea.precio:€}} | {{linea.descuento:%}} | {{linea.iva_pct:%}} | {{linea.importe:€}} |

> Guía: por diferencias, solo la diferencia (en negativo si resta). Si se anula entera, todas las líneas de la original en negativo. Por sustitución, todas las líneas con los importes correctos.

## Totales
| Concepto | Importe |
|---|---|
| Base imponible | {{base:€}} |
| IVA {{iva_pct:%}} | {{cuota_iva:€}} |
| Retención IRPF {{retencion_pct:%}} | −{{retencion:€}} |
| **Total** | **{{total:€}}** |

## Forma de pago o devolución

## Historial
> Guía: solo se añade. Al emitirla, la original pasa a «Rectificada» y enlaza esta.
