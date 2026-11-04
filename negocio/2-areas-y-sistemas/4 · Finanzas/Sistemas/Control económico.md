# Control económico

> 4 · Finanzas · Activo · Lo lleva Mika, con el cierre mensual y la revisión trimestral

## Para qué

Saber qué entra, qué sale y qué está pendiente en The Last y en el autónomo, leyendo los registros únicos sin crear tablas paralelas.

## Cuándo se usa

- En el cierre mensual (antes del día 5) y en la revisión trimestral del autónomo.
- Cada vez que llega un original (lo recoge el Cartero).

## Pasos

1. Incorporar las facturas recibidas con [Incorporar gasto](Control%20económico/Incorporar%20gasto.md): buscar primero por tercero, número e importe, guardar el original una sola vez y añadir la fila en `recibidas.csv`.
2. Para The Last, filtrar las filas con `ambito=The Last` y, si procede, su `proyecto_id`. Los importes pactados viven en la propuesta o el contrato y se enlazan desde `Proyecto.md`.
3. Cotejar documentos, cobros confirmados y pendientes por proyecto. No confundir previsión, factura y movimiento bancario.
4. Comprobar los recurrentes del mes como hechos documentados (RETA, gestoría…), sin clasificarlos fiscalmente, y que la cuenta personal no tenga cargos del negocio.
5. Validar los registros: identificadores únicos, documentos que existen, importes y evidencias.
6. Cada trimestre, preparar el paquete para la gestora como borrador con [Consulta gestora](Control%20económico/Consulta%20gestora.md); el envío necesita aprobación.
7. Si hace falta recuperar histórico, hacerlo con [Revisar archivo](Control%20económico/Revisar%20archivo.md), con procedencia y sin declararlo reconciliado.

## Quién lo hace

Mika cuadra y prepara; el Cartero recoge originales; el director aprueba lo que se envía a la gestora. No se infieren tratamientos fiscales.

## Rutina

Cierre mensual de finanzas y revisión trimestral del autónomo (autopilots activos). No hay umbral de pipeline ni objetivos mensuales.

## Qué deja hecho

Registros cotejados, pendientes por proyecto visibles y dudas documentadas para la gestora. Saldos de apertura e histórico: sin reconciliar; un CSV vacío no significa cero gastos ni cero deuda.

## Procedimientos

- [Incorporar gasto o factura recibida](Control%20económico/Incorporar%20gasto.md)
- [Consulta a la gestora](Control%20económico/Consulta%20gestora.md)
- [Revisar archivo fiscal](Control%20económico/Revisar%20archivo.md)
