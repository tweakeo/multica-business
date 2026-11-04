---
tls_type: task
tls_schema: 1
id: "{{id}}"
numero: "{{numero}}"
titulo: "Valorar: {{titulo}}"
estado: En revisión
tipo: decision
responsable: "{{yo}}"
vence: "{{fecha+7}}"            # a los 7 días sin decidir se avisa
area: direccion
empresa: "{{empresa.enlace}}"
contacto: "{{contacto.enlace}}"
origen: "regla:buzon.entrada"
creada: "{{fecha}}"
creada_por: "agente:mika"
plantilla: "Petición de encargo v1"
---
# Valorar: {{titulo}}
> Petición de {{contacto.nombre}} · espera tu decisión · recomendada: opción 1

## Lo que pide
> Guía: su frase literal, entre comillas.

## Quién decide en su lado

## Encaje con la Oferta
| Pregunta | Respuesta |
|---|---|
| ¿Es para nuestro cliente ideal? | |
| ¿Encaja en un servicio que ya vendemos? | |
| ¿Es estándar o a medida? | |

## Capacidad
> Guía: horas que pediría y fechas posibles frente a la carga de Entrega.

## ¿Nos hace más vendibles, más fáciles de entregar o más sencillos?

## Opciones
| # | Opción | Qué pasa después |
|---|---|---|
| 1 | (recomendada) | |
| 2 | | |
| 3 | | |

> Guía: las tres salidas posibles son aceptar (pasa a Ventas o a Entrega), reconducir a una sesión de diagnóstico o rechazar (no nace nada).

## Actividad
