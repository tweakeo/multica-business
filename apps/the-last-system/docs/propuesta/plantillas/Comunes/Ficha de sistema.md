---
tls_type: system
tls_schema: 1
id: "{{id}}"
codigo: "{{codigo}}"            # CO1, DI1… VE2, FI1…
area: "{{area}}"
estado: a medias                # falta | a medias | montado | funciona sin ti
etapa:                          # etapa (1 a 6) en la que se instala
rol: "{{rol.enlace}}"
numero_clave:                   # código de Metas.md, p. ej. FIN-AR
funciones: []                   # códigos de función que cubre, p. ej. FIN-02
modulos: []                     # módulos de la app que enciende
conexiones: []                  # programas conectados que usa, p. ej. "[[mail|Mail]]"; los permisos viven en la configuración
revisar_cada: mensual           # mensual | trimestral
revisado:
plantilla: "Ficha de sistema v2"
---
# {{titulo}}
> {{area.nombre}} · {{estado}} · Lo lleva {{rol.ocupante}} · Número: {{numero_clave.nombre}}

> Guía: un sistema es una carpeta con el qué, el cómo, ejemplos y una forma de comprobarlo. Aquí el qué es Para qué, Cuándo se usa y Entradas; el cómo, Pasos; los ejemplos, Referencias y ejemplos; y la comprobación, Salida esperada y criterio de «bien hecho». Sus ejecuciones (tareas, proyectos y documentos que salieron de él) las enseña la app debajo de la ficha: no se escriben.

## Para qué
> Guía: una frase.

## Cuándo se usa
> Guía: cuándo empieza y cuándo termina.

## Entradas
| Necesita | De | Si falta |
|---|---|---|
| | | |

> Guía: lo que tiene que estar antes de empezar y qué persona o sistema lo da. Si falta algo, el sistema no arranca: lo pide.

## Pasos
| # | Paso | Quién | Modo | Deja hecho |
|---|---|---|---|---|
| 1 | | | Lo haces tú | |

> Guía: cada paso empieza por un verbo y deja algo comprobable. Modos: Lo haces tú · Te ayuda · Lo hace y revisas · Lo hace solo. Enviar, publicar, facturar, pagar o escribir a clientes es siempre «Siempre con tu OK». Esta columna refleja la configuración de la app: cambiarla aquí no da permisos.

> Guía: si un paso ya va solo sin asistente, añade debajo `### Automático: <paso>` con Disparador · Pasos · Qué deja · Si falla.

## Quién lo hace
> Guía: una línea: quién es el dueño, qué hace el asistente y qué apruebas tú.

## Salida esperada y criterio de «bien hecho»
| Entrega | A |
|---|---|
| | |

Está bien hecho si:
-

> Guía: qué deja hecho y a quién se lo pasa. Debajo, de 3 a 5 frases que se respondan con sí o no, escritas antes de la primera ejecución: es lo que se comprueba antes de dar algo por terminado.

## Lo que nunca hace

## Herramientas y conexiones
> Guía: qué programas conectados, módulos de la app y automatismos usa, y para qué cada uno. La lista sale de `conexiones` y `modulos`; los permisos de verdad viven en la configuración, no aquí.

## Plantillas y activos

## Procedimientos

## Referencias y ejemplos
> Guía: de 1 a 3 enlaces a resultados buenos, tuyos o de fuera, guardados como activos con `ejemplo_bueno: true`. Antes de delegarle un paso, el asistente replica uno hasta que dices «así sí».

## Cómo sabemos que va bien
> Guía: el código del número clave. La meta y la alerta viven en Metas, no aquí.

## Rutina
> Guía: cuándo se revisa y con qué pregunta fija.

## Aprendido
> Guía: los aprendizajes, con fecha. Solo se añade: `- AAAA-MM-DD · qué cambia · por qué · quién lo aprobó`. Cada ejecución se cierra con «¿qué aprendimos?»: el asistente lo trae como propuesta de mejora y la línea entra aquí cuando la apruebas.

## Notas para el asistente
> Guía: opcional. Tono y formato exacto de lo que entrega.

## Origen
Escrito el {{fecha}}.
