---
tls_type: opportunity
tls_schema: 1
id: "{{id}}"
nombre: "{{contacto.nombre}} · {{servicio.nombre}}"
estado: Prospecto               # Prospecto | Diagnóstico | Propuesta | Aceptada | Ganada | Perdida | Pausada
empresa: "{{empresa.enlace}}"
contacto: "{{contacto.enlace}}"
servicio: "{{servicio.enlace}}"
oferta_version:                 # se congela al enviar la propuesta
precio_congelado:
valor:
probabilidad:
responsable: "{{yo}}"
canal:
conversacion:
referido_por:
siguiente_paso:
siguiente_fecha:
despertar:
creada: "{{fecha}}"
aceptada:
cerrada:
motivo_perdida:
origen: manual
plantilla: "Oportunidad v1"
---
# {{nombre}}
> {{estado}} · {{valor:€}} · {{probabilidad}} % · siguiente: {{siguiente_paso}} el {{siguiente_fecha:corta}}

## Cliente
> Guía: quién es, quién decide y por qué ahora.

## Qué pide y alcance
> Guía: primero su frase literal; después, lo que entra y lo que no.

## Condiciones por acordar

## Decisión
> Guía: Aceptada, Perdida (con motivo) o Pausada (con fecha para despertar). Ganada solo llega con un cobro confirmado por una persona.

## Seguimiento
> Guía: solo se añade. `- AAAA-MM-DD · qué pasó · siguiente paso`.

## Documentos
> Guía: la app enlaza aquí la propuesta, el presupuesto, el contrato y las facturas.

Fuente: {{fuente}} · {{fecha}}
