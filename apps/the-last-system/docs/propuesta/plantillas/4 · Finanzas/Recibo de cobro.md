---
tls_type: receipt
tls_schema: 1
id: "{{id}}"
numero: "{{numero}}"            # CB-AAAA-NNNN: lo da el contador al confirmar el cobro
factura: "{{factura.enlace}}"
empresa: "{{factura.empresa}}"
importe:
fecha:                          # día en que llegó el dinero
metodo: transferencia           # transferencia | domiciliación | tarjeta | efectivo
evidencia:                      # Registros/Bancos/<cuenta>/movimientos.csv#MOV-…
pago_id:                        # PAG-AAAAMMDD-NNN en pagos.csv
confirmado_por: "{{yo}}"
pdf:
pdf_sha256:
plantilla: "Recibo de cobro v1"
---
# Recibo {{numero}}
> {{importe:€}} · cobrado el {{fecha:corta}} · factura {{factura.numero}}

Hemos recibido de {{empresa.razon_social}} la cantidad de {{importe:€}} ({{importe:letra}}) por la factura {{factura.numero}} del {{factura.fecha:larga}}.

## Detalle
| Dato | Valor |
|---|---|
| Factura | {{factura.numero}} |
| Total de la factura | {{factura.total:€}} |
| Este cobro | {{importe:€}} |
| Pendiente después de este cobro | {{factura.pendiente:€}} |
| Forma de pago | {{metodo}} |
| Fecha | {{fecha:larga}} |

> Guía: el recibo solo existe después de que una persona confirme el cobro con el movimiento del banco.
