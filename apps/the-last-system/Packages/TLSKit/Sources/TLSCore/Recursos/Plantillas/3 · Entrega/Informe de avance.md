---
tls_type: report
tls_schema: 1
id: "{{id}}"
proyecto: "{{proyecto.enlace}}"
semana: "{{semana}}"
fecha: "{{fecha}}"
estado: En plazo                # En plazo | En riesgo | Retrasado
sesiones_hechas:
sesiones_incluidas:
horas_reales:
horas_previstas:
cobrado_pct:
avance_pct:
pdf:
plantilla: "Informe de avance v1"
---
# Avance · {{proyecto.nombre}} · {{semana}}
> {{estado}} · {{sesiones_hechas}} de {{sesiones_incluidas}} sesiones · {{cobrado_pct}} % cobrado

## Hecho

## Siguiente

## Lo que necesitamos de ti

## Riesgos

## Las preguntas del viernes
| Pregunta | Respuesta |
|---|---|
| ¿La sesión real va con la planificada? | |
| ¿Horas reales frente a previstas? | |
| ¿Entregamos más de lo cobrado? | |
| ¿Algo lleva más de una semana de retraso? | |

> Guía: lo rellena el asistente Implementador con las tareas y los cobros; tú das el estado final. Un retraso de más de una semana se escala.

## Solo interno
> Guía: esta sección no sale en la versión para el cliente.
