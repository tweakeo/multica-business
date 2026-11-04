---
tls_type: project
tls_schema: 1
id: "{{id}}"
nombre: "Plan de 4 semanas · {{cuello.nombre}}"
clase: interno
estado: Sin empezar             # Sin empezar | En curso | Pausado | Cerrado | Archivado
area: "{{cuello}}"
responsable: "{{yo}}"
inicio: "{{fecha+1l}}"
fin: "{{fecha+20l}}"
diagnostico: "{{diagnostico.enlace}}"
plantilla: "Plan de 4 semanas v1"
---
# Plan de 4 semanas · {{cuello.nombre}}
> {{estado}} · del {{inicio:corta}} al {{fin:corta}} · solo el cuello

## Por qué esta área
> Guía: tu frase del diagnóstico y la nota de dependencia.

## Las tres acciones
| Semana | Acción | Deja hecho | Quién |
|---|---|---|---|
| 1 | | | |
| 2 | | | |
| 3 | | | |
| 4 | Volver a diagnosticar el área | Notas nuevas en el Diagnóstico | Tú |

## Cómo sabremos que funcionó
> Guía: un área sube cuando desaparecen los síntomas, no cuando se ha hecho el trabajo.

## Lo que no tocamos estas cuatro semanas
