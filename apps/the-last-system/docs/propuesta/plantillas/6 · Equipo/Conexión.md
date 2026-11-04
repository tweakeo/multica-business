---
tls_type: connection
tls_schema: 1
id: "{{id}}"
nombre: "{{titulo}}"
tipo: otro                      # correo | calendario | banco | otro programa
estado: Desconectada            # Conectada | En pausa | Desconectada
conectada_el:
asistentes: []                  # quién puede usarla
responsable: "{{yo}}"
plantilla: "Conexión v1"
---
# {{titulo}}
> {{estado}} · {{tipo}} · la usan {{asistentes}}

> Guía: describe la conexión para que la entiendas tú. Los permisos de verdad están en la configuración de la app; cambiar esta ficha no los cambia.

## Para qué

## Qué lee

## Qué puede hacer
> Guía: lo que deja dentro de la carpeta (fichas, filas, borradores). Lo que sale fuera siempre pide tu OK.

## Qué nunca hace

## Permisos por asistente
| Asistente | Leer | Preparar borradores | Ejecutar con tu OK |
|---|---|---|---|
| | Sí | No | No |

## Si falla
> Guía: qué avisa la app, qué se para y cómo se vuelve a conectar.
