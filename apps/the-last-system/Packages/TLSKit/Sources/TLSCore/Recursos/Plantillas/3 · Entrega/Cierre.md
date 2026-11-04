---
tls_type: closure
tls_schema: 1
id: "{{id}}"
proyecto: "{{proyecto.enlace}}"
empresa: "{{empresa.enlace}}"
fecha: "{{fecha}}"
estado: Borrador                # Borrador | Conforme
cobro_final: false              # sin cobro final no se entrega
nota:                           # de 1 a 12, la que da el cliente
testimonio:                     # enlace al testimonio, si hay permiso
revisiones: ["{{fecha+30}}", "{{fecha+60}}", "{{fecha+90}}"]
pdf:
pdf_sha256:
plantilla: "Cierre v1"
---
# Cierre · {{proyecto.nombre}}
> {{estado}} · {{fecha:corta}} · {{cumplidas}} de {{promesas}} promesas cumplidas · nota {{nota}}

## Punto de partida
> Guía: cómo estaba al empezar, con su frase del diagnóstico.

## Lo prometido
| Promesa | Resultado | Evidencia |
|---|---|---|
| | Cumplida | |

> Guía: Resultado: Cumplida, Parcial o No. Sin evidencia no hay «Cumplida».

## Antes y después por área
| Área | Antes | Después |
|---|---|---|
| | | |

## Lo que ya haces sin nosotros

## Continuidad
> Guía: el siguiente paso que propone la Oferta, si encaja. Lo prepara Ventas.

## Revisiones
| Revisión | Fecha | Qué miramos |
|---|---|---|
| 30 días | {{fecha+30}} | ¿Lo sigue usando? |
| 60 días | {{fecha+60}} | ¿Algo se ha caído? |
| 90 días | {{fecha+90}} | ¿Se mantiene el resultado? |

## Conformidad
> Guía: la frase del cliente aceptando la entrega y la fecha. Al cerrar se avisa a Finanzas (margen), a Ventas (continuidad y referido) y a Marca (caso).
