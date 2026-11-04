---
tls_type: meeting
tls_schema: 1
id: "{{id}}"
titulo: "Diagnóstico · {{empresa.nombre}}"
tipo: descubrimiento            # es la variante de descubrimiento de un servicio de diagnóstico de empresa
estado: Prevista                # Prevista | Hecha | Cancelada
fecha: "{{fecha}}"
hora:
duracion_min: 60
personas: ["{{contacto.enlace}}"]
empresa: "{{empresa.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
servicio: "{{servicio.enlace}}" # el servicio de diagnóstico que la enlaza en `descubrimiento`
area: ventas
lugar:
grabacion:
guion: "{{guion.enlace}}"
plantilla: "Reunión de diagnóstico v1"
---
# Diagnóstico · {{empresa.nombre}}
> {{estado}} · {{fecha:corta}} {{hora}} · 60 min · con {{contacto.nombre}}

> Guía: variante de la reunión de descubrimiento para un servicio que diagnostica la empresa entera, como el de The Last. En lugar de las preguntas de un servicio, sigue el guion de seis bloques. Al marcarla Hecha, el asistente genera el borrador de propuesta desde «Qué se habló» y «Lo que salió».

## Antes de la sesión
| Pregunta | Respuesta |
|---|---|
| Quién es y a qué se dedica | |
| Cómo llegó | |
| Qué ha pedido, con sus palabras | |
| Qué sospechamos que le duele | |
| Qué queremos saber al terminar | |

> Guía: la ficha previa. La prepara el asistente Comercial y tú la revisas antes de la sesión.

## Qué se habló
> Guía: por bloques del guion. Las frases del cliente, literales y entre comillas.

## Lo que salió
| Salida | Respuesta |
|---|---|
| Frase del negocio | |
| Cliente ideal y anticliente | |
| Problema principal por área | |
| Cuello de botella confirmado | |
| Frase destino (literal) | |

## Decisiones

## Acciones
> Guía: `- acción · @responsable · vence AAAA-MM-DD`. Lo normal: «Generar el borrador de propuesta desde esta reunión · @agente:comercial · vence …». Al marcar la reunión como Hecha, la app la propone sola.

## Nota interna
