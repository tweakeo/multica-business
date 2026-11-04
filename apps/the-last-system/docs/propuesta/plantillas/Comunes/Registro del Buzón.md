---
tls_type: log
tls_schema: 1
id: "{{id}}"
registro: correo
mes: "{{mes}}"                  # AAAA-MM
plantilla: "Registro del Buzón v1"
---
# Correo de {{mes:larga}}
> Lo que entró por el Buzón este mes y adónde fue. Solo se añade.

> Guía: una sección `## AAAA-MM-DD` por día de triaje y una línea por entrada:
> `- hora · de · asunto · tipo · destino · estado`.
> Tipo: cliente, interesado, proveedor, administración o ruido. Estado: Propuesto, Hecho o Deshecho.
> Un plazo oficial lleva al final «· PLAZO AAAA-MM-DD».

## {{fecha}}
