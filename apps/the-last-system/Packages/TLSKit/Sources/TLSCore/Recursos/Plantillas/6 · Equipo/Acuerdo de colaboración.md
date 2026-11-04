---
tls_type: collaboration
tls_schema: 1
id: "{{id}}"
contacto: "{{contacto.enlace}}"
empresa: "{{empresa.enlace}}"
proyecto: "{{proyecto.enlace}}"
estado: Borrador                # Borrador | Enviado | Aceptado | Terminado
inicio:
fin:
compensacion:                   # € o % según lo acordado
forma_pago:
accesos: []                     # los mínimos para el encargo
exclusividad: false
aceptado_el:
pdf:
pdf_sha256:
plantilla: "Acuerdo de colaboración v1"
---
# Acuerdo de colaboración con {{contacto.nombre}}
> {{estado}} · {{proyecto.nombre}} · del {{inicio:corta}} al {{fin:corta}}

> Guía: texto de partida. Revísalo con tu asesor antes de usarlo.

## Partes
| Dato | Tú | Colaborador |
|---|---|---|
| Nombre | {{mi_empresa.nombre}} | {{contacto.nombre}} |
| NIF | En el PDF | {{empresa.nif}} |
| Contacto | {{yo.nombre}} | {{contacto.email}} |

## Qué se encarga

## Plazo y entregables
| Entregable | Fecha | Se acepta cuando |
|---|---|---|
| | | |

## Compensación
> Guía: importe o porcentaje, cuándo se paga y contra qué.

## Accesos
> Guía: solo los necesarios, y la fecha en que se retiran.

## Propiedad intelectual
Cada parte declara aquí lo que ya era suyo antes de empezar. Lo que se cree en común solo se vende con permiso de ambas partes.

## Confidencialidad y datos

## Fin del acuerdo
> Guía: cómo termina, qué se entrega al terminar y cuándo se retiran los accesos.

## Aceptación
| Parte | Nombre | Fecha |
|---|---|---|
| Tú | {{yo.nombre}} | |
| Colaborador | {{contacto.nombre}} | |
