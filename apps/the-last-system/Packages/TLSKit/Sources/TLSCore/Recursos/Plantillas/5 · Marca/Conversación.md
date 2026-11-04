---
tls_type: conversation
tls_schema: 1
id: "{{id}}"
contacto: "{{contacto.enlace}}"
canal:                          # linkedin | instagram | correo | web | evento | otro
contenido: "{{contenido.enlace}}"   # la pieza que la originó
fecha: "{{fecha}}"
estado: Nueva                   # Nueva | Propuesta a Ventas | Cualificada | No cualifica
decidido_por:
oportunidad:                    # si se cualifica, la oportunidad que nace
motivo:
plantilla: "Conversación v1"
---
# {{contacto.nombre}} en {{canal}}
> {{estado}} · {{fecha:corta}} · viene de «{{contenido.titulo}}»

## Lo que dijo
> Guía: su mensaje, literal.

## Contexto

## Decisión de Ventas
> Guía: Marca no cualifica: «Proponer a Ventas» crea una tarea en Ventas. Si cualifica, nacen el contacto, la empresa y la oportunidad con esta conversación como origen.
