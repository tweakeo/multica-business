---
tls_type: content
tls_schema: 1
id: "{{id}}"
titulo: "{{titulo}}"
tipo: testimonio
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
autor: "{{contacto.enlace}}"
empresa: "{{empresa.enlace}}"
proyecto: "{{proyecto.enlace}}"
autorizado: false
autorizado_el:
medio: texto                    # texto | video | audio
usos: []                        # web | redes | propuestas
evidencia_url:                  # enlace a la publicación
alcance:
impresiones:
interacciones:
plantilla: "Testimonio v1"
---
# {{titulo}}
> {{estado}} · {{autor.nombre}} · autorizado: {{autorizado:sino}}

## Cita literal
> Guía: tal cual lo dijo. Si se acorta, se marca con «[…]» y se le enseña.

## Quién
> Guía: nombre, cargo y empresa, o solo lo que haya autorizado.

## Contexto
> Guía: qué proyecto y qué resultado.

## Permiso
> Guía: cómo lo autorizó (correo, firma) y para qué usos. Sin permiso no se publica.

## Resultados
> Guía: tras publicar, el alcance y las interacciones van en las propiedades. Las conversaciones que trae esta pieza las cuenta la app.

## Notas
