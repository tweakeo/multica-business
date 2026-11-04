---
tls_type: contact
tls_schema: 1
id: "{{id}}"
nombre: "{{titulo}}"
aliases: []
empresa: "{{empresa.enlace}}"
cargo:
email:
telefono:
relacion: [cliente]             # su papel: cliente | proveedor | colaborador | gestoría | otro
estado: Interesado              # ciclo de vida: Interesado | Activo | Antiguo cliente | Archivado. Archivar no borra: sale de las vistas de trabajo y lo conserva todo
canal:                          # web | recomendación | redes | evento | llamada | buzón | importación | otro
referido_por:                   # enlace al contacto que lo recomendó
conversacion:                   # enlace a la conversación de Marca que lo trajo
verificacion: pendiente         # pendiente | verificado
no_contactar: false             # true si pidió no recibir comunicaciones
origen: manual                  # manual | regla:<evento> | agente:<nombre> | importacion
creada: "{{fecha}}"
plantilla: "Contacto v1"
---
# {{titulo}}
> {{cargo}} · {{empresa.nombre}} · {{estado}}

## Cómo llegó
> Guía: por qué canal, cuándo y, si lo hay, quién lo recomendó o qué publicación lo trajo.

## Lo que le importa
> Guía: frases suyas, literales y entre comillas. Sirven para la reunión de descubrimiento y la propuesta.

## Notas

## Historial
> Guía: solo se añade. `- AAAA-MM-DD · llamada, correo o reunión · qué pasó · quién`. Es el registro de lo que pasó; las fichas enlazadas van en «Todo lo relacionado».

## Todo lo relacionado
> Guía: esta sección no se escribe. La app enseña aquí sola, agrupado por relación, todo lo que enlaza a esta persona: oportunidades, reuniones (por tipo), propuestas y presupuestos, proyectos, facturas y cobros, incidencias y conversaciones. Los botones «Nueva reunión», «Nueva propuesta», «Nuevo proyecto» y «Nueva factura» crean la nota en su carpeta, con su nombre y con esta persona y su empresa ya enlazadas. En Obsidian no hace falta Dataview: con el módulo «Vistas para Obsidian», aquí se incrusta la vista equivalente.

Fuente: {{fuente}} · {{fecha}}
