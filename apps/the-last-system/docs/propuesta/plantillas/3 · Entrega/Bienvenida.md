---
tls_type: welcome
tls_schema: 1
id: "{{id}}"
proyecto: "{{proyecto.enlace}}"
contacto: "{{contacto.enlace}}"
estado: Borrador                # Borrador | Pendiente de tu OK | Publicada
franja:                         # «martes 10:00»
primera_sesion:
portal:
pdf:
plantilla: "Bienvenida v1"
---
# Bienvenida, {{contacto.nombre}}
> {{estado}} · primera sesión el {{primera_sesion:corta}} · cada {{franja}}

## Lo que vamos a conseguir
«{{proyecto.resultado_prometido}}»

## Cómo vamos a trabajar
| Sesión | Qué hacemos | Fecha |
|---|---|---|
| {{sesion.nombre}} | {{sesion.objetivo}} | {{sesion.fecha:corta}} |

## Lo que necesitamos de ti
1. 
2. 
3. 

> Guía: como mucho tres cosas. Pasan a «Tareas del cliente» del portal.

## Tus accesos
> Guía: enlaces, nunca contraseñas.

## Cómo hablar con nosotros
> Guía: un canal para dudas y otro para problemas urgentes, con el plazo de respuesta.
