---
tls_type: log
tls_schema: 1
id: "{{id}}"
registro: incidencias
proyecto: "{{proyecto.enlace}}"
plantilla: "Registro de incidencias v1"
---
# Incidencias · {{proyecto.nombre}}
> Plazo de respuesta: grave, 24 h hábiles · media, 48 h · leve, 72 h. Solo se añaden filas.

| ID | Fecha | Quién reporta | Email | Tipo | Severidad | Estado | Descripción | Responsable | Resolución |
|---|---|---|---|---|---|---|---|---|---|

> Guía: ID correlativo INC-001. Tipo: Técnica, Accesos, Automatización, Negocio u Otro. Severidad: Leve, Media o Grave. Estado: Recibida, En curso, Resuelta o Cerrada. Se cierra cuando el cliente lo confirma o a las 72 h sin respuesta. Si es grave o se repite, también lleva ficha en Incidencias/. El cliente no ve el email, el responsable ni la resolución.
