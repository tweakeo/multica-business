# Finanzas

**Estado:** activa · **La llevan:** Mika, el Cartero y la revisión trimestral, sin agente nuevo · **Rol:** Mika prepara y cuadra; el director aprueba toda emisión, pago y envío a la gestora.

## Qué transforma

Documentos y movimientos en control económico y fiscal, juntos en esta área. Los registros únicos son los CSV de Registros; un mismo gasto o cobro no se vuelve a escribir en otra tabla.

## Sistemas

- [Facturación y cobros](Sistemas/Facturación%20y%20cobros.md).
- [Control económico](Sistemas/Control%20económico.md), con sus procedimientos: [incorporar gasto](Sistemas/Control%20económico/Incorporar%20gasto.md), [consulta a la gestora](Sistemas/Control%20económico/Consulta%20gestora.md) y [revisar archivo](Sistemas/Control%20económico/Revisar%20archivo.md).
- [Tesorería](Sistemas/Tesorería.md).

## Rutinas

- **Activas:** triaje de correo del Cartero (facturas y avisos), cierre mensual de finanzas y revisión trimestral del autónomo.
- **Preparadas, se activan con Ventas y Entrega:** borrador de factura al cerrar un hito de Entrega (nunca se emite sin el director) y cobros pendientes el día 5 de cada mes.

## Carpetas

- Fiscal: `AAAA/T1…T4/{Ingresos,Gastos,Modelos}`.
- Registros: `emitidas.csv`, `recibidas.csv` y `pagos.csv`. Los extractos por importar, en `Registros/importar/`.
- Gestoría: relación con la gestoría y sus libros.
- Trámites: Alta y trámites y Seguridad Social.
