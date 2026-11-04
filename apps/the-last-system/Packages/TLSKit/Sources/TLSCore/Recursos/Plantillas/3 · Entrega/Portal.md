---
tls_type: portal
tls_schema: 1
id: "{{id}}"
proyecto: "{{proyecto.enlace}}"
empresa: "{{empresa.enlace}}"
estado: Borrador                # Borrador | Publicado | Cerrado
publicado_el:
plantilla: "Portal v1"
---
# Portal de {{empresa.nombre}}
> {{estado}} · {{sesiones_hechas}} de {{sesiones_incluidas}} sesiones · {{proyecto.nombre}}

## Viaje
| Sesión | Estado | Fecha | Resumen para el cliente | Nota interna |
|---|---|---|---|---|
| {{sesion.nombre}} | Pendiente | | | |

> Guía: una fila por sesión del plan. Estado: Pendiente, Programada, Kit listo, Hecha o No incluida. El cliente nunca ve la columna «Nota interna».

## Tareas del cliente
- [ ] {{tarea_cliente}} · {{sesion.codigo}} · vence AAAA-MM-DD

> Guía: estas casillas son deberes del cliente, no fichas de tarea.

## Documentos

## Dudas y problemas
> Guía: el cliente añade aquí una duda o un problema desde su vista; se convierte en una fila de Incidencias.
