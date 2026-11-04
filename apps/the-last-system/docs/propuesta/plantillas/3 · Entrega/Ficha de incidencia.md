---
tls_type: incident
tls_schema: 1
id: "{{id}}"
numero: "{{numero}}"            # INC-007, el mismo de la fila
titulo: "{{titulo}}"
proyecto: "{{proyecto.enlace}}"
tarea: "{{tarea.enlace}}"
reporta: "{{contacto.enlace}}"
tipo:                           # Técnica | Accesos | Automatización | Negocio | Otro
gravedad: Media                 # Leve | Media | Grave
estado: Recibida                # Recibida | En curso | Resuelta | Cerrada
recibida: "{{fecha}}"
plazo:                          # lo calcula la app en horas hábiles
cerrada:
repeticion: 1                   # a la segunda, cinco porqués
plantilla: "Ficha de incidencia v1"
---
# {{numero}} · {{titulo}}
> {{estado}} · {{gravedad}} · responder antes del {{plazo:corta}}

## Qué pasó
> Guía: con las palabras del cliente y lo que se comprobó.

## Cinco porqués
1. 
2. 
3. 
4. 
5. 

> Guía: la causa final apunta al sistema (un paso, un criterio, una plantilla), nunca a una persona.

## Causa en el sistema

## Arreglo

## Cómo comprobamos que no vuelve

## Actividad
