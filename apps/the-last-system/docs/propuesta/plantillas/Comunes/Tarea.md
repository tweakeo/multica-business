---
tls_type: task
tls_schema: 1
id: "{{id}}"
numero: "{{numero}}"            # T-0042: lo da el contador de la carpeta
titulo: "{{titulo}}"
estado: Sin programar           # Sin programar | Por hacer | En curso | En revisión | Bloqueada | Hecha | Cancelada
prioridad:                      # Urgente | Alta | Media | Baja
tipo: tarea                     # tarea | pregunta | decision
responsable: "{{responsable}}"  # una persona o agente:<nombre>
planificada:                    # cuándo se hará; se puede mover y nunca cae en sábado ni domingo
vence:                          # límite real; ningún asistente lo mueve
estimacion_h:
dedicadas_h:
area: "{{area}}"
proyecto: "{{proyecto.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
empresa: "{{empresa.enlace}}"
padre:
bloqueada_por: []
capacidad:                      # código de la función, p. ej. VEN-08
despertar:                      # fecha en la que vuelve a aparecer (seguimientos)
origen: manual                  # manual | rutina:<nombre> | regla:<evento> | agente:<nombre> | importacion
creada: "{{fecha}}"
creada_por: "{{yo}}"
cerrada:
plantilla: "Tarea v1"
---
# {{titulo}}
> {{estado}} · {{responsable}} · vence el {{vence:corta}}

## Descripción
> Guía: qué hay que hacer y cómo sabrás que está hecho. Si pones casillas aquí, son pasos de esta tarea, no tareas nuevas.

## Actividad
> Guía: solo se añade. Cada entrada empieza por `### AAAA-MM-DD HH:MM · autor`. Para comentar, escribe debajo de la última entrada.
