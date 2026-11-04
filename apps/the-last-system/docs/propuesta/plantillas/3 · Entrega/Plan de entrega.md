---
tls_type: delivery_template
tls_schema: 1
id: "{{id}}"
nombre: "Plan de entrega · {{servicio.nombre}}"
clase: entrega                  # entrega | incorporacion
servicio: "{{servicio.enlace}}"
version: 1
estado: En uso                  # Borrador | En uso | Retirado
dias_proyecto:                  # días laborables de principio a fin
sesiones_incluidas:
terminado_cuando: ""
plantilla: "Plan de entrega v1"
---
# Plan de entrega · {{servicio.nombre}}
> {{estado}} · {{dias_proyecto}} días laborables · {{sesiones_incluidas}} sesiones

## Terminado cuando
> Guía: una frase comprobable. Es el criterio para cerrar el proyecto.

## Fase 1 · Arranque
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Comprobar el traspaso de Ventas | 0 | 1 | 0 | agente:implementador | No falta ninguna pieza del traspaso |
| Enviar la bienvenida y fijar la franja | 0 | 1 | 1 | responsable | Primera sesión con fecha |

## Fase 2 · 
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| | | | | | |

## Fase 3 · Cierre
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Revisar lo prometido con el cliente | | 1 | 0 | responsable | Acta de entrega con conformidad |

> Guía: «Día» es el día laborable en que empieza, contando desde el arranque (día 0). «Dura» y «Margen» van en días laborables. «Quién»: `responsable`, `cliente` o `agente:<nombre>`. Al crear un proyecto, cada fila se convierte en una tarea con fecha, nunca en sábado ni domingo.

## Pagos por fase
| Pago | Cae al terminar |
|---|---|
| Inicial | Arranque |
| Final | Cierre |

> Guía: los porcentajes y plazos salen de las condiciones de cobro del servicio; aquí solo se dice en qué fase cae cada pago.

## Kit por sesión
> Guía: si el servicio tiene sesiones, enlaza aquí las piezas de su kit.
