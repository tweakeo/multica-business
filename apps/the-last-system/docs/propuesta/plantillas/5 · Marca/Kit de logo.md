---
tls_type: asset
tls_schema: 1
id: "{{id}}"
nombre: "Logo de {{mi_empresa.nombre}}"
area: marca
sistema: "{{sistema.enlace}}"   # Identidad
estado: Borrador                # Provisional | Borrador | Aprobado | Retirado
origen:                         # aportado | web | tipografico | ia
fuente:                         # dirección web o herramienta; vacío si lo aportaste
obtenido_el: "{{fecha}}"
derechos: pendiente             # propio | licencia | pendiente
vectorial: false
fondo_transparente: false
resolucion_px:
colores: []                     # hex dominantes
contraste_claro:                # sobre fondo claro; mínimo 3:1
contraste_oscuro:               # sobre fondo oscuro; mínimo 3:1
aprobado_el:
version: 1
pdf:
plantilla: "Kit de logo v1"
---
# Logo de {{mi_empresa.nombre}}
> {{estado}} · origen: {{origen}} · versión {{version}}

## Variantes
| Variante | Fichero | Fondo | Uso |
|---|---|---|---|
| Logo en color | logo.svg | Claro | Documentos y web |
| Logo en blanco | logo-blanco.svg | Oscuro o de color | Portadas y fondos oscuros |
| Logo en negro | logo-negro.svg | Claro | Impresión en blanco y negro |
| Isotipo | isotipo.svg | Claro | Icono y avatar |
| Isotipo en blanco | isotipo-blanco.svg | Oscuro | Icono sobre color |
| Avatar | avatar-1024.png | Color principal | Redes y barra lateral de la app |
| Icono web | favicon-512.png | Color principal | Web y portal del cliente |
| Portada de redes | portada-social-1500x500.png | Color principal | Cabecera de redes |
| Para documentos | logo-documento.png | Claro | PDF (300 ppp) |

> Guía: el original se guarda sin tocar en `original/`. Las variantes de un solo color solo se generan si el logo es vectorial o tiene el fondo limpio; si no, la fila dice «No disponible» y por qué.

## Comprobaciones
| Comprobación | Resultado |
|---|---|
| Tamaño (1.000 px o vectorial) | |
| Fondo transparente | |
| Se lee sobre claro (3:1) | |
| Se lee sobre oscuro (3:1) | |
| Derechos de uso | |

## Espacio y tamaño mínimo
> Guía: el aire que hay que dejar alrededor y el tamaño más pequeño en que se lee bien.

## Usos incorrectos
- Deformarlo o cambiarle las proporciones.
- Cambiarle los colores fuera de sus variantes.
- Ponerlo sobre un fondo donde no se lee.

## Origen
> Guía: cómo se consiguió: aportado, traído de tu web (con la dirección y la fecha), generado en la app (tipografía y color) o con IA (herramienta y petición).

## Versiones anteriores
> Guía: solo se añade. Las anteriores se guardan en Archivo; los documentos ya emitidos conservan su logo.
