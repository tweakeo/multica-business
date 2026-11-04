# Facturación y cobros

> 4 · Finanzas · Activo para los encargos que haya; sus rutinas se activan con Ventas y Entrega · Lo lleva Mika

## Para qué

Que cada hito cobrable tenga su factura trazable y su cobro verificado, sin emitir nada sin el director.

## Cuándo se usa

- Al cerrar un hito de Entrega: pago inicial antes de arrancar y cobro final al cierre.
- El día 5 de cada mes, en la revisión de cobros pendientes.

## Pasos

1. Comprobar el acuerdo, el entregable, los datos fiscales del destinatario y si ya existe un documento previo.
2. Preparar el borrador en `Fiscal/Borradores/` con proyecto, concepto y condiciones conocidas, sin número definitivo.
3. El director aprueba el documento y el mecanismo de emisión. El mecanismo está por elegir (a través de una tercera persona o directamente; no Holded, y un PDF no resuelve por sí solo la emisión). Un criterio legal nuevo necesita fuente oficial vigente o confirmación de la gestora.
4. Solo con la emisión verificada: archivar el original en `Fiscal/AAAA/Tn/Ingresos/` y añadir la fila `EMI` en `emitidas.csv` (Registros).
5. El envío al cliente necesita el OK concreto del director.
6. Cobro: verificarlo en el banco y añadir la fila en `pagos.csv` enlazada a la factura, solo con evidencia.
7. El día 5: listar lo emitido sin cobrar y preparar un borrador de recordatorio para el director.

## Quién lo hace

Mika prepara borradores y filas; el director aprueba, emite y envía.

## Rutina

Preparadas, se activan con Ventas y Entrega: borrador de factura al cerrar un hito de Entrega y cobros pendientes el día 5 de cada mes.

## Qué deja hecho

Un borrador pendiente de emisión, o una factura emitida con su fila y su cobro conciliado. Sin mecanismo aprobado, el estado es «Borrador pendiente de emisión»: no se declara emitida ni se crea número definitivo.
