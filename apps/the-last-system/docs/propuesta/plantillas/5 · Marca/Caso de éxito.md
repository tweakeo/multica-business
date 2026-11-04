---
tls_type: content
tls_schema: 1
id: "{{id}}"
titulo: "{{titulo}}"
tipo: caso
estado: Idea                    # Idea | Borrador | En revisión | Aprobado | Programado | Publicado | Descartado
pilar:                          # educativo | inspirador | conversacion | venta
canales: []
objetivo: atraer                # atraer | nutrir | convertir
cta:                            # la única llamada a la acción
servicio:
publicar:                       # fecha prevista; la usa el calendario
publicado:
derivado_de:                    # pieza raíz de la que sale
responsable: "{{yo}}"
proyecto: "{{proyecto.enlace}}"
empresa: "{{empresa.enlace}}"
anonimo: false                  # true si no se dice el nombre del cliente
permiso: false                  # sin permiso no se publica
permiso_el:
cifra:                          # el resultado con número
pdf:
evidencia_url:                  # enlace a la publicación
alcance:
impresiones:
interacciones:
plantilla: "Caso de éxito v1"
---
# {{titulo}}
> {{estado}} · caso de {{empresa.nombre}} · {{cifra}} · permiso: {{permiso:sino}}

## Brief
| Pregunta | Respuesta |
|---|---|
| Para quién | |
| Qué tiene que pensar o sentir | |
| Qué tiene que hacer después | |
| De qué pieza raíz sale | |

## Cliente
> Guía: quién es, en dos líneas. Si es anónimo, solo el sector y el tamaño.

## Antes
> Guía: su frase literal del diagnóstico.

## Qué hicimos

## Después
> Guía: la cifra y de dónde sale (la evidencia del Cierre). Sin evidencia, no hay cifra.

## Cita
> Guía: del testimonio autorizado.

## Permiso
> Guía: quién lo autorizó, cuándo y para qué usos. Sin permiso no se publica ni sale en propuestas.

## Resultados
> Guía: tras publicar, el alcance y las interacciones van en las propiedades. Las conversaciones que trae esta pieza las cuenta la app.

## Notas
