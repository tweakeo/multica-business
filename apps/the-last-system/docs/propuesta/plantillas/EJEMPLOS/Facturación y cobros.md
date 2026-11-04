---
tls_type: system
tls_schema: 1
id: 5ca76007-e922-453a-90c5-dff2636020ab
codigo: FI1
area: finanzas
estado: montado
etapa: 1
rol: "[[financiero|Financiero]]"
numero_clave: FIN-AR
funciones: [FIN-02, FIN-03, FIN-04, FIN-10]
modulos: [facturas-y-cobros]
conexiones: ["[[mail|Mail]]"]
revisar_cada: mensual
revisado: 2026-10-05
plantilla: "Ficha de sistema v2"
---
# Facturación y cobros
> 4 · Finanzas · Montado · Lo lleva Elena con el asistente Contable · Número: cobrado en plazo

## Para qué
Que cada servicio vendido tenga su factura sin errores y que cada cobro esté comprobado en el banco.

## Cuándo se usa
Empieza cuando una oportunidad pasa a Aceptada, cuando vence una factura y el día 5 de cada mes. Termina cuando la factura está cobrada y su recibo, guardado.

## Entradas
| Necesita | De | Si falta |
|---|---|---|
| Oportunidad aceptada con el precio congelado | Embudo (Ventas) | No se prepara ninguna factura |
| NIF, domicilio y correo de facturación del cliente | Ficha de la empresa | El borrador sale con «[falta: …]» y la pregunta va en la tarea |
| Condiciones de cobro del servicio | Versión de la oferta | Se pregunta a Elena; nunca se pone un plazo fijo |
| Movimiento del banco conciliado | Tesorería | No hay recibo: la factura sigue sin cobrar |

## Pasos
| # | Paso | Quién | Modo | Deja hecho |
|---|---|---|---|---|
| 1 | Comprobar NIF, domicilio y correo de facturación del cliente | Contable (asistente) | Lo hace y revisas | Datos completos o una pregunta |
| 2 | Preparar el borrador con las líneas de la propuesta | Contable (asistente) | Te ayuda | Factura en Borradores |
| 3 | Revisar y emitir | Elena | Siempre con tu OK | Número, fecha y PDF |
| 4 | Enviar la factura al cliente | Elena | Siempre con tu OK | Correo enviado |
| 5 | Confirmar el cobro con el movimiento del banco | Elena | Lo haces tú | Fila en pagos.csv y recibo |
| 6 | Si vence, preparar el recordatorio | Contable (asistente) | Te ayuda | Borrador y tarjeta en Decisiones |

## Quién lo hace
Lo lleva Elena Castell (rol Financiero). El asistente Contable prepara datos, borradores y recordatorios; Elena emite, envía y confirma los cobros.

## Salida esperada y criterio de «bien hecho»
| Entrega | A |
|---|---|
| Factura en borrador | Elena, para emitir |
| Factura emitida con su PDF y su fila en emitidas.csv | Cliente, con el OK de Elena |
| Recibo de cobro enlazado al movimiento del banco | Carpeta del trimestre |
| Recordatorio en borrador y la pregunta «¿Seguimos?», si vence | Elena, en Decisiones |

Está bien hecho si:
- el precio coincide con la versión de la oferta que cita la factura;
- no queda ningún «[falta: …]» al emitir;
- el vencimiento sale de las condiciones del servicio;
- ningún cobro cuenta sin un movimiento del banco confirmado por una persona.

## Lo que nunca hace
- Emitir o enviar sin OK · dar una factura por cobrada · cambiar precios · hacer descuentos · decidir cómo se trata un impuesto

## Herramientas y conexiones
- Mail: la factura sale como borrador de correo con el PDF adjunto; se envía solo con el OK de Elena.
- Maqueta de PDF de la app, sin internet, con el logo y los colores del manual de marca.
- El extracto del banco no se conecta aquí: lo trae Tesorería.
- Ningún asistente ni programa conectado lee los datos fiscales ni la cuenta del emisor.

## Plantillas y activos
- Plantillas: [Factura](Plantillas/Factura.md) · [Factura rectificativa](Plantillas/Factura%20rectificativa.md) · [Recibo de cobro](Plantillas/Recibo%20de%20cobro.md) · [Recordatorio de cobro](Plantillas/Recordatorio%20de%20cobro.md) · [Contrato](Plantillas/Contrato.md) · [Condiciones de cobro](Plantillas/Condiciones%20de%20cobro.md)
- Activos: ninguno todavía

## Procedimientos
Ninguno: el sistema cabe en esta ficha.

## Referencias y ejemplos
- [F-2026-0004 · Panadería Horno Sol](../Fiscal/2026/T3/Ingresos/f-2026-0004.md): emitida el mismo día de la aceptación y cobrada a los cinco días. El asistente Contable la replicó antes de preparar su primer borrador real.

## Cómo sabemos que va bien
Cobrado en plazo (FIN-AR). La meta y la alerta están en [Metas](../../1%20·%20Dirección/Metas.md).

## Rutina
El día 5 de cada mes, en la rutina financiera: «¿Qué está sin cobrar y qué margen dejó lo cobrado?»

## Aprendido
- 2026-09-12 · El asistente comprueba los datos fiscales antes de preparar el borrador · tres borradores se quedaron parados por falta de NIF · aprobado por Elena
- 2026-10-05 · El vencimiento sale de la oferta (15 días en Trimestrales), no de un valor fijo · dos facturas salieron a 7 días por error · aprobado por Elena
- 2026-10-15 · Si faltan datos fiscales, la pregunta va con una mención a quien llevó la venta, no a la titular · en T-0031 los consiguió Lucía en tres horas · propuesta del asistente Contable al cerrar la tarea, aprobada por Elena

## Notas para el asistente
- Concepto de cada línea: «Servicio periodo · qué incluye», por ejemplo «Trimestrales T4 2026 · modelos 303 y 111».
- Asesoría Ribera es una sociedad: retención 0 %, aunque el cliente sea empresa.
- Si falta un dato, escribe «[falta: …]» y pregúntalo en la tarea. Nunca lo deduzcas.

## Origen
Ficha de G3 pasada a la versión 2 el 2026-10-05. Ejemplo ficticio de Asesoría Ribera.
