---
tls_type: area
tls_schema: 1
id: "{{id}}"
codigo: "{{area}}"              # direccion | ventas | entrega | finanzas | marca | equipo
nombre: "{{area.nombre}}"
estado: preparada               # activa | preparada | en reposo
convierte: "{{area.convierte}}"
rol: "{{rol.enlace}}"
ocupante:                       # una persona o agente:<nombre>
pregunta: "{{area.pregunta}}"
numero_clave:
etapa:                          # 1 a 6: la propone la app y la confirmas tú
plantilla: "Cabecera de área v1"
---
# {{area.nombre}}
> {{estado}} · La lleva {{ocupante}} · {{pregunta}}

## Qué transforma
> Guía: «Convierte X en Y» y cómo se nota cuando está rota.

## Sistemas
| Código | Sistema | Estado |
|---|---|---|
| | | |

## Rutina
> Guía: día, hora y pregunta fija. La ficha de la rutina vive en Dirección › Rutinas.

## Carpetas

## Pendiente
