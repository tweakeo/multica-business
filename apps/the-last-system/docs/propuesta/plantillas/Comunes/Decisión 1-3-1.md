---
tls_type: task
tls_schema: 1
id: "{{id}}"
numero: "{{numero}}"
titulo: "{{titulo}}"
estado: En revisión
tipo: decision
responsable: "{{yo}}"           # quien decide
vence:                          # a los 14 días sin decidir se pone en rojo (DIR-DEC14)
area: "{{area}}"
proyecto: "{{proyecto.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
origen: manual
creada: "{{fecha}}"
creada_por: "{{yo}}"
plantilla: "Decisión 1-3-1 v1"
---
# {{titulo}}
> Decisión pendiente · {{area.nombre}} · recomendada: opción 1

## Problema
> Guía: una frase. Qué hay que decidir y para cuándo.

## Opciones
| # | Opción | A favor | En contra | Coste o riesgo |
|---|---|---|---|---|
| 1 | (recomendada) | | | |
| 2 | | | | |
| 3 | | | | |

> Guía: un problema, hasta tres opciones y una recomendada.

## Por qué recomiendo la 1

## Datos que hay
> Guía: enlaces a las fichas, cifras o mensajes que sostienen las opciones.

## Qué cambia si se aprueba
> Guía: documentos que habrá que poner al día (Oferta, Rumbo, un sistema…).

## Actividad
> Guía: aquí queda tu respuesta (apruebo, apruebo con cambios, respondo o pospongo) y el enlace a la línea de Decisiones.
