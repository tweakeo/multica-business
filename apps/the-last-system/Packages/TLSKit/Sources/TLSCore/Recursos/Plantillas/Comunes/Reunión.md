---
tls_type: meeting
tls_schema: 1
id: "{{id}}"
titulo: "{{titulo}}"
tipo: otra                      # descubrimiento | seguimiento | sesion | interna | otra. Descubrimiento, seguimiento y sesión tienen su propia plantilla
estado: Prevista                # Prevista | Hecha | Cancelada
fecha: "{{fecha}}"
hora:
duracion_min: 60
personas: []                    # contactos y personas del equipo que asisten
empresa: "{{empresa.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
proyecto: "{{proyecto.enlace}}"
area: "{{area}}"
lugar:                          # dirección o enlace de la videollamada
grabacion:
plantilla: "Reunión v1"
---
# {{titulo}}
> {{estado}} · {{fecha:corta}} {{hora}} · {{duracion_min}} min · {{empresa.nombre}}

## Antes de la reunión
| Pregunta | Respuesta |
|---|---|
| Qué sabemos ya | |
| Qué queremos saber | |
| Qué tiene que pasar al terminar | |

> Guía: es la ficha previa. Se rellena mientras la reunión está «Prevista».

## Objetivo

## Qué se habló

## Decisiones

## Acciones
> Guía: una por línea, `- acción · @responsable · vence AAAA-MM-DD`. Al confirmarlas se convierten en tareas y la línea enlaza cada tarea.

## Para el cliente
> Guía: el resumen y los siguientes pasos que verá el cliente. Nada interno.

## Nota interna
