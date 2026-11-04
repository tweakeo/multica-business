---
tls_type: root_cause
tls_schema: 1
id: "{{id}}"
titulo: "{{titulo}}"
fecha: "{{fecha}}"
area: "{{area}}"
sistema: "{{sistema.enlace}}"
proyecto: "{{proyecto.enlace}}"
repeticiones: 2                 # se abre a la segunda vez que pasa lo mismo
estado: Abierto                 # Abierto | Arreglado | Comprobado
plantilla: "Cinco porqués v1"
---
# {{titulo}}
> {{estado}} · {{repeticiones}} veces · {{sistema.nombre}}

## Qué pasó
| Fecha | Dónde | Qué pasó |
|---|---|---|
| | | |
| | | |

## Cinco porqués
1. ¿Por qué pasó?
2. ¿Por qué?
3. ¿Por qué?
4. ¿Por qué?
5. ¿Por qué?

> Guía: la respuesta final apunta a un paso, un criterio o una plantilla del sistema. Nunca a una persona.

## Causa en el sistema

## Arreglo
> Guía: el cambio en la ficha del sistema. Queda también como línea en su «Aprendido».

## Cómo comprobamos que no vuelve
