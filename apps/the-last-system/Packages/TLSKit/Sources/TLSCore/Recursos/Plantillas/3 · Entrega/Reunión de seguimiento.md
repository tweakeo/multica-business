---
tls_type: meeting
tls_schema: 1
id: "{{id}}"
titulo: "Seguimiento {{orden}} · {{empresa.nombre}}"
tipo: seguimiento
estado: Prevista                # Prevista | Hecha | Cancelada
fecha: "{{fecha}}"
hora:
duracion_min: 30
personas: ["{{contacto.enlace}}"]
empresa: "{{empresa.enlace}}"
proyecto: "{{proyecto.enlace}}"
servicio: "{{proyecto.servicio}}"
area: entrega
lugar:                          # dirección o enlace de la videollamada
grabacion:
plantilla: "Reunión de seguimiento v1"
---
# Seguimiento {{orden}} · {{empresa.nombre}}
> {{estado}} · {{fecha:corta}} {{hora}} · {{duracion_min}} min · {{proyecto.nombre}}

> Guía: la reunión periódica con un cliente activo. El número de orden y el nombre los pone la plantilla («Seguimiento 2 · Talleres Martín»). Se crea con «Nueva reunión» desde la ficha del cliente o del proyecto y nace en `Proyectos/<slug>/Reuniones/`.

## Antes de la reunión
| Pregunta | Respuesta |
|---|---|
| Qué acordamos en la anterior y qué se hizo | |
| Cómo van el proyecto y los cobros | |
| Qué tiene pendiente el cliente | |
| Qué queremos saber o decidir hoy | |

> Guía: la ficha previa. La prepara el asistente Implementador con las acciones del seguimiento anterior, el avance del proyecto, lo pendiente en el portal y las facturas sin cobrar. Tú la revisas.

## Preguntas guía
- ¿Qué ha cambiado desde la última vez?
- Lo que entregamos, ¿se está usando? ¿Qué sobra o qué falta?
- ¿Hay algo que te preocupe para las próximas semanas?
- ¿Hay algo nuevo en lo que te podamos ayudar?

> Guía: si sale un trabajo nuevo, la acción es «Nueva oportunidad» de continuidad (Referidos y continuidad), no una tarea dentro de este proyecto.

## Qué se habló
> Guía: las frases del cliente, literales y entre comillas.

## Decisiones

## Acciones
> Guía: una por línea, `- acción · @responsable · vence AAAA-MM-DD`. Al confirmarlas se convierten en tareas y la línea enlaza cada tarea.

## Para el cliente
> Guía: el resumen y los siguientes pasos que verá en su portal, con tu OK. Nada interno.

## Nota interna
