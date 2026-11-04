---
tls_type: fragment
tls_schema: 1
id: "{{id}}"
forma: fila                     # seccion | fila | linea
donde: "4 · Finanzas/Registros/recibidas.csv"
sistema: "{{sistema.enlace}}"   # Control económico
plantilla: "Gasto v1"
---
## Gasto

| Campo | Qué se pone | Ejemplo |
|---|---|---|
| Fecha del documento | AAAA-MM-DD | 2026-10-01 |
| Proveedor | Nombre del proveedor (enlaza su Empresa) | Software Contable Nube SL |
| Número del documento | El de su factura | SCN-2610 |
| Base | € sin IVA | 120.00 |
| IVA | € | 25.20 |
| Retención | € (si la hay) | |
| Total | € | 145.20 |
| Categoría | Software, alquiler, telefonía, formación… | Software |
| Naturaleza | fijo, variable o inversión | fijo |
| Proyecto | Si es de un proyecto concreto | |
| Documento | Ruta del original en la carpeta del proveedor | Fiscal/2026/T4/Gastos/software-contable-nube/2026-10-01 Software Contable Nube SCN-2610 145,20€.pdf |

> Guía: el gasto no es una nota: es una fila de recibidas.csv y el original se guarda en su carpeta. Antes de añadir, la app busca si ya existe. Las cinco últimas columnas (base, iva, retencion, categoria, naturaleza) son nuevas y van al final de la cabecera.

Fila que se añade (cabecera de Esquema.md más las cinco columnas nuevas):

```
id,fecha_documento,tercero,numero_documento,moneda,total_documento,documento,ambito,proyecto_id,estado_revision,fuente,base,iva,retencion,categoria,naturaleza
REC-20261001-001,2026-10-01,Software Contable Nube SL,SCN-2610,EUR,145.20,"Fiscal/2026/T4/Gastos/software-contable-nube/2026-10-01 Software Contable Nube SCN-2610 145,20€.pdf",{{mi_empresa.nombre}},,pendiente,buzon,120.00,25.20,,Software,fijo
```
