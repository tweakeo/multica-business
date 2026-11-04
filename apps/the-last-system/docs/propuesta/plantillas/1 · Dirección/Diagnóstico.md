---
tls_type: diagnosis
tls_schema: 1
id: "{{id}}"
fecha: "{{fecha}}"
estado: Borrador                # Borrador | Confirmado
etapa_global:                   # la del área más atrasada entre Ventas, Entrega y Finanzas
cuello:                         # área que hace de cuello de botella
version: 1
plantilla: "Diagnóstico v1"
---
# Diagnóstico de {{mi_empresa.nombre}}
> {{estado}} · {{fecha:corta}} · etapa {{etapa_global}} · cuello: {{cuello.nombre}}

## Frase del negocio
> Guía: «Ayudamos a [cliente] a conseguir [resultado] en [plazo] con [método], sin [dolor]».

## Frase destino
> Guía: lo que quieres conseguir, con tus palabras literales.

## Cliente ideal y anticliente
| Cliente ideal | Anticliente |
|---|---|
| | |

## Las seis áreas
| Área | Funciona (1–5) | Depende de ti (1–5) | Etapa | Lo que dijiste |
|---|---|---|---|---|
| 1 · Dirección | | | | |
| 2 · Ventas | | | | |
| 3 · Entrega | | | | |
| 4 · Finanzas | | | | |
| 5 · Marca | | | | |
| 6 · Equipo | | | | |

> Guía: «Depende de ti» se mide con una pregunta: si paras dos semanas, ¿sigue? La etapa es la primera pregunta respondida con «no». La cita va literal.

## Cuello de botella
> Guía: el área con dependencia de 4 o más, entre las que tienen sus requisitos cumplidos: Marca exige una Entrega consistente y Equipo, una Entrega escrita.

## Síntoma, causa y pieza que falta
| Área | Síntoma (tu frase) | Causa | Pieza que falta |
|---|---|---|---|
| | | | |

## Siguiente paso
> Guía: el enlace al plan de 4 semanas para el cuello. Solo se trabaja el cuello y después se vuelve a diagnosticar.

## Revisiones
> Guía: solo se añade. `- AAAA-MM-DD · área · nota anterior → nota nueva · por qué`.
