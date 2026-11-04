---
tls_type: routine
tls_schema: 1
id: "{{id}}"
nombre: "{{titulo}}"
area: "{{area}}"
cadencia: semanal               # semanal | mensual | trimestral
dia:                            # lunes… o día del mes
hora:
duracion_min:
pregunta: "{{pregunta}}"
responsable: "{{yo}}"
activa: true
calendario: false               # true si se apunta en el Calendario del Mac
plantilla: "Rutina v1"
---
# {{titulo}}
> {{cadencia}} · {{dia}} {{hora}} · {{duracion_min}} min · «{{pregunta}}»

## Pregunta
{{pregunta}}

## Qué produce

## Qué no hace

## Cómo se hace
1. 

## Registro
> Guía: solo se añade. `- AAAA-MM-DD · hecha o saltada · N min · avanza o no avanza · [nota](./<rutina>/AAAA-MM-DD.md)`.
