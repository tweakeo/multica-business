# TLS — Formatos

## Extracto bancario (CSV)

Separador `;`, codificación UTF-8, decimales con coma, primera línea de cabecera opcional.

```
fecha;fecha_valor;concepto;importe;saldo
01/10/2026;01/10/2026;RECIBO INMOBILIARIA CENTRO SL ALQUILER;-663,00;20.716,15
```

| Columna | Obligatoria | Formato |
|---|---|---|
| fecha | sí | `DD/MM/AAAA` o `AAAA-MM-DD` |
| fecha_valor | no | igual |
| concepto | sí | texto del banco |
| importe | sí | negativo = salida. `1.234,56` o `1234.56` |
| saldo | no | saldo tras el movimiento según el banco |

- Con cabecera, las columnas se leen por nombre y el separador puede ser `,` (como `Registros/importar/*.csv`). Si hay columna `id`, la huella es ese id.
- Si además hay `iva` (y `retencion_irpf`), `importe` es la base, como en el libro antiguo: lo que se movió es importe + IVA − retención. Una fila con IVA o retención negativos (devoluciones, rectificativas) o un borrador no dice qué se movió: no se importa y se informa con su motivo.
- Reimportar no duplica: cada movimiento lleva una huella de cuenta, fecha, importe, concepto y saldo.
- Clasificación automática: traspasos, impuestos (AEAT, TGSS, modelo NNN), nóminas, retiradas del titular y préstamos. El resto es ingreso o gasto operativo.
- Conciliación propuesta: importe exacto + número de factura en el concepto o contraparte coincidente, una factura por movimiento y fecha más próxima. **Propuesta no es confirmación.**
- Saldo: se usa el último saldo informado por el banco; si no hay, el saldo inicial declarado más los movimientos; si no hay ninguno, **desconocido**.

## Carpeta de la empresa

```
<carpeta>/
  Empresa.md                     identidad y perfil (sin secretos)
  LEEME.md
  Ventas/Organizaciones|Contactos|Oportunidades|Ofertas|Guiones/
  Entrega/Servicios/<codigo>.md  canvas y plantilla
  Finanzas/<año>/T<n>/Ingresos|Gastos/<proveedor>|Cobros y pagos/
  Finanzas/<año>/T<n>/periodo.md
  Finanzas/<año>/T<n>/Paquete gestoría/   indice.md + CSV
  Finanzas/Bancos/<cuenta>/...
  Dirección/Objetivos|Decisiones|KPI|Rutinas/
  Marca/Identidad.md, Contenidos/, Conversaciones/
  Equipo/Roles/
  Justificantes/<AAAA-MM>/*.pdf
```

Cada registro es Markdown con frontmatter YAML:

```markdown
---
tls_type: opportunity
tls_schema: 1
id: 3f7c…                 # identidad
version: 4
stage: propuesta
value_minor: 15000
…
---

Notas en texto libre (cuerpo).
```

- `tls_type` y `tls_schema` versionan el formato; `id` es la identidad.
- Campos desconocidos se conservan (`attrs`) al reconstruir.
- Índices, cachés, sockets y servicios viven en `~/Library/Application Support/TLS` y en PostgreSQL, nunca en la carpeta.

### Estructura humana (`.tls/layout.json`)

Sin `.tls/layout.json` la carpeta usa la estructura de arriba (la de la demo). Con `{"preset": "humana"}` usa la estructura de The Last:

```
Empresa.md
1 · Dirección/   Decisiones.md · Sistemas/ · Recursos/ · Contratos/
2 · Ventas/      Empresas/ · Contactos/ · Oportunidades/ · Productos/
3 · Entrega/ … 6 · Equipo/   Sistemas/ · Recursos/
4 · Finanzas/    Fiscal/<año>/T<n>/{Ingresos,Gastos,Modelos} · Registros/{emitidas,recibidas,pagos}.csv
Buzón/ · Archivo/
```

Cualquier clave del preset se puede cambiar en el mismo archivo (`areas`, `dirs`, `quarter`, `package`, `registros`, `decisiones`, `archivo`, `skeleton`, `skip`).

- **Texto humano**: si una nota la escribió o editó una persona, la app solo actualiza su frontmatter (sin añadir campos vacíos y respetando `nombre`/`titulo`). El cuerpo no se toca; `Empresa.md` igual.
- **No se borra nada**: dentro de su carpeta una nota conserva su nombre; si cambia de carpeta se mueve, y lo que se retira (o estorba) va a `Archivo/<misma ruta>`.
- **Decisiones**: una línea por decisión en `Decisiones.md`, con el registro completo en un comentario `<!-- tls:decision … -->`. Las demás líneas no se tocan.
- **Registros únicos**: las facturas emitidas o recibidas (no los borradores) y los pagos confirmados se escriben como fila en `Registros/*.csv`, por `id` (o `registro_id` de la factura). Los pagos no tienen nota propia. Al reconstruir, el CSV manda en fecha, número, moneda y total; las filas añadidas a mano se listan como `sin_vincular` y no se importan solas.
- **Notas sin `tls_type`**: el tipo se deduce por la carpeta o por `tipo:` (empresa, persona, oportunidad) si tienen `id`. Las que no se pueden leer salen como propuestas; `POST /folder/adopt` con `apply` añade solo `tls_type`, `tls_schema` e `id`.

## Paquete trimestral para la gestoría

`Finanzas/<año>/T<n>/Paquete gestoría/`:

| Fichero | Contenido |
|---|---|
| `indice.md` | Estado del periodo, totales y advertencia de que no es una declaración oficial |
| `libro-ingresos.csv` | Facturas emitidas con base, IVA, retención y total |
| `libro-gastos.csv` | Facturas recibidas con ruta del justificante o `FALTA` |
| `movimientos.csv` | Movimientos con conciliación y factura |
| `diferencias.csv` | Lo que hay que resolver o validar |

Cada fila lleva el `id` del registro de origen.
