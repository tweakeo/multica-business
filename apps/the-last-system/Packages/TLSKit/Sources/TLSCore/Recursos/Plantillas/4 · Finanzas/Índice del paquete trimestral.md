---
tls_type: period
tls_schema: 1
id: "{{id}}"
periodo: "{{trimestre}}"        # T4 2026
desde:
hasta:
estado: Preparando              # Preparando | Preparado | Enviado | Presentado
listo: false                    # true cuando no falta nada
enviado_el:
plantilla: "Índice del paquete trimestral v1"
---
# Paquete para la gestoría · {{periodo}}
> {{estado}} · del {{desde:corta}} al {{hasta:corta}} · falta {{faltan}}

> No es una declaración ni calcula lo que hay que pagar: la gestoría lo revisa y lo presenta.

## Qué contiene
| Fichero | Contenido | Registros |
|---|---|---|
| libro-ingresos.csv | Facturas emitidas del trimestre | |
| libro-gastos.csv | Facturas recibidas, con la ruta del original o FALTA | |
| movimientos.csv | Movimientos del banco con su conciliación | |
| diferencias.csv | Lo que hay que resolver o validar | |

> Guía: los CSV van con «;» y coma decimal para abrirlos en Excel. Cada fila lleva el identificador de su registro.

## Totales
| | Base | IVA | Retención | Total |
|---|---|---|---|---|
| Ingresos | | | | |
| Gastos | | | | |

## Lo que falta
> Guía: originales sin justificante, movimientos sin conciliar y dudas abiertas. Mientras haya algo, «listo» se queda en falso.

## Modelos del trimestre
| Modelo | Estado |
|---|---|
| | |

> Guía: los que diga tu gestoría. La app no decide qué modelos tocan.

## Dudas para la gestoría
> Guía: enlace a las dudas abiertas de este trimestre.
