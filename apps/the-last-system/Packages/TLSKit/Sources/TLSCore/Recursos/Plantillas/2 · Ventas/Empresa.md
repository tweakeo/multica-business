---
tls_type: organization
tls_schema: 1
id: "{{id}}"
nombre: "{{titulo}}"
aliases: []
tipo: empresa                   # empresa | profesional | particular | administración
razon_social:
nif:
domicilio:
cp:
ciudad:
provincia:
pais: España
email_facturacion:
web:
sector:
personas:                       # cuántas personas trabajan en ella
relacion: [cliente]             # su papel: cliente | proveedor | colaborador | gestoría | otro
estado: Interesado              # ciclo de vida: Interesado | Activo | Antiguo cliente | Archivado (un proveedor o colaborador solo usa Activo y Archivado). Archivar no borra
logo:                           # imagen en 2 · Ventas/Empresas/Logos/ (la aporta la empresa o sale de su web)
verificacion: pendiente         # pendiente | verificado
origen: manual
creada: "{{fecha}}"
plantilla: "Empresa v1"
---
# {{titulo}}
> {{sector}} · {{ciudad}} · {{relacion}} · {{estado}}

> Guía: es la ficha de cliente, el nodo central: desde aquí se ve y se crea todo lo suyo. Los datos de facturación son las propiedades de arriba. Los leen la propuesta, el contrato y la factura; si falta uno, el documento sale con «[falta: …]».

## Qué hace

## Cómo trabajamos con ella

## Notas

## Historial
> Guía: solo se añade. `- AAAA-MM-DD · qué pasó · quién`. Es el registro de lo que pasó; las fichas enlazadas van en «Todo lo relacionado».

## Todo lo relacionado
> Guía: esta sección no se escribe. La app enseña aquí sola, agrupado por relación, todo lo que enlaza a esta empresa: personas, servicios contratados (salen de sus oportunidades), oportunidades, reuniones (por tipo), propuestas y presupuestos, proyectos, facturas y cobros, incidencias, conversaciones y casos. Los botones «Nueva reunión», «Nueva propuesta», «Nuevo proyecto» y «Nueva factura» crean la nota en su carpeta, con su nombre estándar y con la empresa, el contacto y la oportunidad ya enlazados. Si el cliente está Interesado, «Nueva reunión» propone la de descubrimiento de su servicio; si está Activo, la de seguimiento. En Obsidian no hace falta Dataview: con el módulo «Vistas para Obsidian», aquí se incrusta la vista equivalente.

Fuente: {{fuente}} · {{fecha}}
