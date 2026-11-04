# Registros

CSV UTF-8, separados por coma, con cabecera fija, fechas ISO `AAAA-MM-DD` e importes decimales con punto, sin separador de millares. Un campo desconocido queda **vacío**, nunca a cero. Cada fila tiene un identificador estable y único (`REC-20261015-001`), que es un ID interno, no un número fiscal.

## Fuentes editables únicas

- `recibidas.csv`: id, fecha_documento, tercero, numero_documento, moneda, total_documento, documento, ambito, proyecto_id, estado_revision, fuente. Es captura documental: no decide qué es deducible. `documento` es la ruta relativa a esta carpeta.
- `emitidas.csv`: id, fecha_documento, tercero, numero_documento, moneda, total_documento, documento, ambito, proyecto_id, estado_emision, fuente. Solo documentos emitidos y verificados; los borradores viven fuera.
- `pagos.csv`: id, fecha, direccion, importe, moneda, cuenta, documento_id, proyecto_id, evidencia, verificacion. `direccion` es `cobro` o `pago`, con importe positivo. Se enlaza a la REC/EMI que corresponda. Solo con evidencia real: tener la factura no prueba el pago.

`estado_revision`: `pendiente` o `revisado`. `verificacion` de pagos: `confirmado`. Las filas sin proyecto no se inventan uno.

## Extractos por importar

`importar/*.csv` con cabecera `id,fecha,concepto,importe,saldo` (importe negativo = salida). La app los importa sin duplicar y **propone** la conciliación; confirmarla es de una persona.

Un control o un resumen se calcula leyendo estos registros; no se mantiene otra tabla editable.
