---
tls_type: log
tls_schema: 1
id: "{{id}}"
registro: metas
plantilla: "Metas v1"
---
# Metas
> Un número por pregunta. La meta y la alerta se escriben antes de ver el dato.

| Código | Indicador | Meta | Alerta | Por qué |
|---|---|---|---|---|
| BUZ-PEND | Entradas del Buzón sin ordenar más de 2 días | | | Propuesta: meta 0, alerta 5 |
| DIR-DEC14 | Decisiones sin tomar a los 14 días | | | Propuesta: meta 0, alerta 1 |
| VEN-STALE7 | Oportunidades quietas 7 días o más | | | Propuesta: meta 0, alerta 1 |
| VEN-WON | Ventas cobradas del mes | | | Alerta: dos meses seguidos por debajo |
| FIN-AR | Cobros vencidos | | | Propuesta: meta 0 €; alerta con una sola factura vencida |
| FIN-RUNWAY | Meses de caja | | | Propuesta: meta 3 meses, alerta 1 mes |
| FIN-FISCAL | Paquete trimestral a tiempo | | | |
| EQU-HEALTH | Asistentes sanos | | | Propuesta: meta 100 % |
| EQU-COST | Coste de los asistentes del mes | | | |

> Guía: la app solo cambia las columnas Meta y Alerta. Al instalar un sistema añade la fila de su número, sin meta. Sin meta se ve «Sin meta» y sin dato «Sin dato», nunca 0.
