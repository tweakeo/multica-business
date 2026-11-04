# Incorporar gasto o factura recibida

## Entrada

Original recibido y ámbito profesional identificado.

## Comprobaciones

Buscar documento, tercero+número e importe en recibidas.csv y archivo anterior. Si ya está, enlazar la fila; no duplicar. Verificar legibilidad y transcribir fecha, tercero, número, moneda y total, dejando desconocidos vacíos. No decidir deducciones ni IVA desde criterios antiguos.

## Cambios

Guardar el original una sola vez en Fiscal/AAAA/Tn/Gastos o enlazar su ubicación existente. Añadir fila REC en recibidas.csv con fuente, ámbito y proyecto solo si corresponde. Pago únicamente en pagos.csv con evidencia real.

## Verificación

Abrir documento desde la fila, cotejar los campos e ID único; comprobar que TL consulta esa fila y no otra copia. Ante diferencia, mantener pendiente y documentar la duda para la gestora.

## A mano

Abrir el documento o ficha desde Inicio, editar los campos en texto o el CSV con un editor y guardar. Reabrir enlaces/originales y cotejar el resultado. Codex puede ayudar con esos mismos archivos; no hay servicio obligatorio. Los pasos externos se detienen para la aprobación concreta que corresponda.
