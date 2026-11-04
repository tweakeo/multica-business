---
tls_type: delivery_template
tls_schema: 1
id: "{{id}}"
nombre: "Plan de incorporación · {{rol.nombre}}"
clase: incorporacion            # entrega | incorporacion
rol: "{{rol.enlace}}"
version: 1
estado: En uso                  # Borrador | En uso | Retirado
dias_proyecto: 63               # unos 90 días naturales
terminado_cuando: "Lleva el rol solo y lo revisamos a los 90 días"
plantilla: "Plan de incorporación v1"
---
# Plan de incorporación · {{rol.nombre}}
> {{estado}} · 90 días · cuatro fases, de mirar a hacerlo solo

## Fase 1 · Día 1 · Mira
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Dar los accesos mínimos | 0 | 1 | 0 | responsable | Entra y no ve nada que no necesite |
| Leer la empresa, su rol y los sistemas que tocará | 0 | 2 | 1 | incorporado | Lo explica con sus palabras |

## Fase 2 · Semana 1 · Lo hacéis juntos
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Hacer el paso principal del sistema contigo | 2 | 3 | 1 | responsable | Lo ha hecho dos veces a tu lado |

## Fase 3 · Mes 1 · Lo hace y tú miras
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Llevar el sistema con tu revisión semanal | 5 | 15 | 2 | responsable | Tres semanas sin correcciones graves |

## Fase 4 · Día 90 · Lo hace solo y te informa
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Revisión de los 90 días | 62 | 1 | 0 | responsable | Decidís seguir, ajustar o terminar |

> Guía: «Quién» es responsable (tú) o incorporado (la persona que entra). Las tareas nacen al aceptar el acuerdo de colaboración, en días laborables. Las cuatro fases van de mirar a hacerlo solo: es la misma escalera que siguen los asistentes.
