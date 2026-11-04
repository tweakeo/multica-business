---
tls_type: service
tls_schema: 1
id: "{{id}}"
nombre: "{{titulo}}"
codigo:                         # corto y en mayúsculas: TRIM, RENTA
tipo: servicio                  # servicio | producto | formación | auditoría | análisis | suscripción
estado: En pruebas              # En pruebas | Activo | Retirado. Retirado no se ofrece en propuestas nuevas, pero conserva sus clientes, proyectos y versiones
version: 1                      # sube al aprobar un cambio de precio o de alcance
valido_desde: "{{fecha}}"
modelo_precio: fijo             # fijo | por unidad | a medida
precio:                         # € sin IVA. Es la única fuente de precios
precio_min:                     # solo si es a medida: el rango dentro del que fijas tú el precio de cada propuesta
precio_max:
unidad: proyecto                # sesión | hora | mes | trimestre | proyecto | declaración
iva_pct: 21
retencion_pct:                  # vacío: la decide la configuración según el emisor y el cliente
recurrencia: ninguna            # ninguna | mensual | trimestral | anual
plan: "{{plan.enlace}}"         # plan de entrega: la única fuente de sus fases
descubrimiento:                 # enlace a su variante de reunión de descubrimiento, con las preguntas guía de este servicio
responsable: "{{yo}}"
plantilla: "Servicio v1"
---
# {{titulo}}
> {{tipo}} · {{estado}} · {{precio:€}} por {{unidad}} + IVA · de {{precio_min:€}} a {{precio_max:€}} + IVA · versión {{version}}

> Guía: es la ficha central del servicio. Arriba, su estado: las vistas de la Oferta lo enseñan en Activos, En pruebas o Retirados. Retirar no borra nada.

## Para quién
> Guía: a quién ayuda, en una frase. El detalle va en «Cliente ideal y anticliente».

## Qué resuelve
> Guía: la promesa en una frase, con el resultado y el plazo.

## Incluye

## No incluye

## Fases
> Guía: no se escriben aquí. La app enseña las fases del plan de entrega enlazado en `plan`, que es su única fuente, y la propuesta las copia en su calendario. Si el servicio aún no tiene plan, «Crear plan de entrega» lo crea desde aquí.

## Condiciones de cobro
| Pago | % | Cuándo | Vence a |
|---|---|---|---|
| Inicial | 50 | Al aceptar | 7 días |
| Final | 50 | Al entregar | 7 días |

> Guía: valores de partida; pon los tuyos. Es la única fuente de plazos de cobro: la leen la propuesta, el contrato y la factura.

## Cliente ideal y anticliente

## Objeciones
> Guía: enlace al activo de objeciones de este servicio.

## Reunión de descubrimiento
> Guía: las preguntas guía de este servicio no se escriben aquí: viven en su variante de reunión de descubrimiento, enlazada en `descubrimiento`. «Crear variante» la crea a partir de la general; desde ese momento, «Nueva reunión» en la ficha de un cliente interesado en este servicio usa esa.

## Clientes y proyectos
> Guía: no se escribe. La app enseña aquí sola los clientes de este servicio (por estado), sus oportunidades abiertas, sus proyectos y los ingresos del año.

## Versiones
> Guía: la lista la pone la app. Al aprobar un cambio, la versión anterior se congela en Productos › Versiones.
