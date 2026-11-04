---
tls_type: meeting
tls_schema: 1
id: "{{id}}"
titulo: "{{sesion.nombre}} · {{empresa.nombre}}"
tipo: sesion
sesion: "{{sesion.codigo}}"     # S1 … S9
estado: Prevista                # Prevista | Hecha | Cancelada
fecha: "{{fecha}}"
hora:
duracion_min: 60
personas: ["{{contacto.enlace}}"]
empresa: "{{empresa.enlace}}"
proyecto: "{{proyecto.enlace}}"
area: entrega
lugar:
grabacion:
plantilla: "Acta de sesión v1"
---
# {{sesion.nombre}} · {{empresa.nombre}}
> {{estado}} · {{fecha:corta}} {{hora}} · {{sesion.codigo}} · kit {{kit_listo}} de 6

## Kit
| Pieza | Estado | Enlace |
|---|---|---|
| Mensaje previo | Pendiente | |
| Vídeo de enfoque | Pendiente | |
| Plantilla de recogida | Pendiente | |
| Sesión de 60 minutos | Prevista | |
| Transformación con IA | Pendiente | |
| Mensaje posterior | Pendiente | |

> Guía: el kit se prepara 24 h antes. Estado: Pendiente, Listo o Hecho.

## Objetivo

## Qué se habló

## Decisiones

## Qué queda aplicado

## Acciones
> Guía: `- acción · @responsable · vence AAAA-MM-DD`. Al confirmarlas se convierten en tareas.

## Para el cliente
> Guía: pasa al «Resumen de la sesión» del portal cuando lo apruebas. Sin vocabulario interno.

## Nota interna
