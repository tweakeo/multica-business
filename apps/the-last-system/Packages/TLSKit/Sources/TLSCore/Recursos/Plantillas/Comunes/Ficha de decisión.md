---
tls_type: decision
tls_schema: 1
id: "{{id}}"
titulo: "{{titulo}}"
fecha: "{{fecha}}"
area: "{{area}}"
estado: Tomada                  # Tomada | Sustituida
decidido_por: "{{yo}}"
sustituye:                      # enlace a la decisión que deja sin efecto
afecta: []                      # enlaces a lo que cambia: Oferta, Rumbo, un sistema…
revisar_el:
plantilla: "Ficha de decisión v1"
---
# {{titulo}}
> {{estado}} el {{fecha:corta}} · {{area.nombre}} · decide {{decidido_por}}

## Qué se decide
> Guía: una o dos frases, sin matices.

## Por qué

## Para qué

## Alcance
> Guía: a qué afecta, a qué no y desde cuándo.

## Datos que había

## Opciones descartadas
| Opción | Por qué no |
|---|---|
| | |

## Qué hay que poner al día
> Guía: la app propone el cambio en cada documento afectado, cada uno con tu OK.

## Revisiones
> Guía: solo se añade. `- AAAA-MM-DD · qué se comprobó · se mantiene o se sustituye`.
