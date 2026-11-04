---
tls_type: meeting
tls_schema: 1
id: "{{id}}"
titulo: "Descubrimiento · {{servicio.nombre}} · {{empresa.nombre}}"
tipo: descubrimiento
estado: Prevista                # Prevista | Hecha | Cancelada
fecha: "{{fecha}}"
hora:
duracion_min: 45
personas: ["{{contacto.enlace}}"]
empresa: "{{empresa.enlace}}"
oportunidad: "{{oportunidad.enlace}}"
servicio: "{{servicio.enlace}}" # el servicio que pide; decide qué variante de preguntas se usa
area: ventas
lugar:                          # dirección o enlace de la videollamada
grabacion:
plantilla: "Reunión de descubrimiento v1"
---
# Descubrimiento · {{servicio.nombre}} · {{empresa.nombre}}
> {{estado}} · {{fecha:corta}} {{hora}} · {{duracion_min}} min · con {{contacto.nombre}}

> Guía: es la reunión que ocupa la etapa Diagnóstico de la oportunidad: entender el problema y ver si el servicio encaja. Esta es la plantilla general. Si el servicio tiene su variante (enlazada en su propiedad `descubrimiento`), la app usa esa al pulsar «Nueva reunión» en la ficha del cliente, de la oportunidad o del servicio. El nombre lo pone la plantilla: no hace falta escribirlo.

## Antes de la reunión
| Pregunta | Respuesta |
|---|---|
| Quién es y a qué se dedica | |
| Cómo llegó | |
| Qué ha pedido, con sus palabras | |
| Qué servicio creemos que encaja y por qué | |
| Qué queremos saber al terminar | |

> Guía: la ficha previa. La prepara el asistente Comercial con lo que ya hay en la ficha del cliente y tú la revisas.

## Preguntas guía
### Su situación
- ¿Qué te ha hecho buscar ayuda justo ahora?
- ¿Cómo lo resuelves hoy y qué es lo que más te cuesta?

### Lo que quiere conseguir
- Si esto sale bien, ¿qué habrá cambiado dentro de tres meses?
- ¿Cómo sabrás que ha funcionado?

### Encaje con el servicio
- ¿Qué parte quieres que hagamos nosotros y cuál prefieres seguir haciendo tú?
- ¿Hay alguna fecha que no se pueda mover?

### Decisión
- ¿Quién más tiene que estar de acuerdo?
- ¿Qué necesitas ver para decidir?

> Guía: son preguntas de partida, no un interrogatorio: no hace falta hacerlas todas ni en este orden. Cada variante por servicio cambia el bloque «Encaje con el servicio» por las preguntas propias de ese servicio.

## Qué se habló
> Guía: las frases del cliente, literales y entre comillas. De aquí sale el borrador de la propuesta: lo que no esté escrito aquí, el asistente no lo inventa.

## Lo que salió
| Salida | Respuesta |
|---|---|
| Su problema, en una frase | |
| Frase destino (literal) | |
| Servicio que encaja, o «ninguno» con su motivo | |
| Alcance: qué sí y qué no | |
| Quién decide y cuándo | |
| Fecha que no se mueve | |
| Siguiente paso y fecha | |

## Decisiones

## Acciones
> Guía: `- acción · @responsable · vence AAAA-MM-DD`. Lo normal: «Generar el borrador de propuesta desde esta reunión · @agente:comercial · vence {{fecha+2l}}». Al marcar la reunión como Hecha, la app la propone sola; el borrador queda enlazado a esta reunión y lo revisas y envías tú.

## Nota interna
