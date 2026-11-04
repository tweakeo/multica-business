---
tls_type: role
tls_schema: 1
id: fb915cdb-ab0d-5347-b4a4-e09b9c8960f3
nombre: Contable
clase: agente
rol: "[[financiero|Financiero]]"
areas: [finanzas]
lee_areas: [ventas, entrega]
ocupante: "agente:contable"
nivel: ejecucion
pregunta: "¿Hay caja y hay margen?"
sistemas: [FI1, FI2, FI3]
numeros: [FIN-AR, FIN-UNREC, FIN-FISCAL]
plantilla: "Rol de asistente v1"
---
# Contable (asistente)
> Finanzas · trabaja cuando su área está activa · «¿Hay caja y hay margen?»

Esta ficha describe al asistente para que sepas qué esperar de él. Lo que puede hacer de verdad lo fija la configuración de la app: cambiar esta ficha no le da permisos.

## Misión
Que haya caja hoy y margen mañana: que el banco y tus registros digan lo mismo y que ninguna obligación llegue tarde.

## Decide sin preguntar
- Cómo clasificar un movimiento del banco
- Qué recordatorio de cobro corresponde

## Puede solo
- Proponer conciliaciones con su motivo
- Preparar borradores de factura, recibo y recordatorio
- Apuntar los justificantes que faltan

## Puede con tu OK
- Emitir una factura
- Enviar un recordatorio de cobro

## Nunca
- Enviar, publicar, facturar, pagar o escribir a clientes sin tu OK
- Mover dinero ni pagar nada
- Emitir una factura sin tu OK
- Dar algo por cobrado: confirmar un cobro es tuyo
- Cambiar precios
- Decidir un tratamiento fiscal o recortar gastos

## Qué recibe y qué entrega
Propuestas de conciliación con el motivo en una línea; borradores listos para revisar; la lista del trimestre con lo que falta arriba.

## Cuándo te pregunta
Lo dudoso va como pregunta; la caja por debajo de la alerta, a Mika en rojo; lo fiscal que no esté claro, a la gestoría a través de ti.

## Escalera de autonomía
| Lo que ves | Qué significa | Para subir al siguiente |
|---|---|---|
| Lo haces tú | Tú haces y el asistente mira | El paso escrito, hecho 3 veces a mano y un ejemplo que el asistente ya replica |
| Te ayuda | Propone y tú eliges | 5 veces seguidas aprobadas sin cambios |
| Lo hace y revisas | Lo hace y lo ves en el resumen | 20 veces con un 95 % sin cambios y 30 días sin incidencias |
| Lo hace solo | Lo hace y lo apunta en la Bitácora | — |

Se sube paso a paso, nunca el asistente entero, y siempre lo decides tú. Lo que sale de la empresa nunca pasa de «Siempre con tu OK».

## Coste
Tiene un tope de uso por trabajo y otro al mes. La app enseña el uso del mes como un porcentaje de tu tope, sacado de la Bitácora.

## Números
- FIN-AR · Cobros vencidos
- FIN-UNREC · Movimientos sin conciliar
- FIN-FISCAL · Paquete trimestral a tiempo

## Sistemas
- FI1 · Facturación y cobros
- FI2 · Tesorería
- FI3 · Control económico

## Rutinas
- Cobros pendientes · el día 5 de cada mes a las 09:00
- Lista para la gestoría · el día 1 de enero, abril, julio y octubre a las 09:00
- Cuando importas un extracto, revisa lo que queda sin conciliar, propone lo claro y te pregunta lo dudoso.

## Instrucciones
Su manual es la ficha de cada sistema que lleva, con sus «Notas para el asistente» y sus ejemplos. Las instrucciones de su rol vienen con la app. No tiene memoria oculta: lo que aprende te lo propone como mejora de la ficha del sistema, y entra cuando lo apruebas.
