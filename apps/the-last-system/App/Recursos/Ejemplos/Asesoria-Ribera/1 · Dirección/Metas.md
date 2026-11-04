---
tls_type: log
tls_schema: 1
id: 182ba186-2527-5f55-b87b-231b3b55a1f4
registro: metas
---
# Metas
> Un número por pregunta. La meta y la alerta se escriben antes de ver el dato.

| Código | Indicador | Meta | Alerta | Por qué |
|---|---|---|---|---|
| DIR-APR | Aprobaciones pendientes | 3 | 10 |  |
| DIR-DEC | Decisiones abiertas | 3 | 8 |  |
| DIR-OBJ | Objetivos del trimestre en trayectoria | 80 % | 50 % |  |
| ENT-ACTIVE | Proyectos activos |  |  |  |
| ENT-ONTIME | Tareas de entrega a tiempo | 90 % | 75 % |  |
| ENT-OVERDUE | Tareas vencidas | 0 | 5 |  |
| EQU-COST | Coste de los asistentes del mes |  |  |  |
| EQU-HEALTH | Asistentes sanos | 100 % | 80 % |  |
| EQU-ROLES | Roles con ocupante | 100 % | 70 % |  |
| FIN-AR | Cobros vencidos | 0 € | 1000 € |  |
| FIN-CASH | Caja disponible |  |  |  |
| FIN-MARGIN | Margen de gestión del mes | 30 % | 15 % |  |
| FIN-RUNWAY | Meses de caja | 3 meses | 2 meses |  |
| FIN-UNREC | Movimientos sin conciliar | 0 | 10 |  |
| MAR-PUB | Piezas publicadas del mes | 6 | 2 |  |
| MAR-QCONV | Conversaciones cualificadas del mes | 8 | 3 |  |
| VEN-CONV | Conversión propuesta → aceptada | 40 % | 20 % |  |
| VEN-FCST | Previsión ponderada |  |  |  |
| VEN-PIPE | Cartera abierta |  |  |  |
| VEN-STALE | Oportunidades quietas (>14 días) | 0 | 3 |  |
| VEN-WON | Ventas cobradas del mes | 6000 € | 3000 € |  |

## Cómo se mide
- DIR-APR · aprobaciones pendientes · ahora · menos es mejor
- DIR-DEC · decisiones con estado abierta · ahora · menos es mejor
- DIR-OBJ · objetivos en trayectoria / objetivos activos · cada trimestre · más es mejor
- ENT-ACTIVE · proyectos en curso ligados a un servicio · ahora · dentro de un rango
- ENT-ONTIME · tareas hechas antes del vencimiento / hechas con vencimiento (30 días) · últimos 30 días · más es mejor
- ENT-OVERDUE · tareas abiertas con vencimiento pasado · ahora · menos es mejor
- EQU-COST · Σ coste de ejecuciones registrado por el proveedor · cada mes · menos es mejor
- EQU-HEALTH · asistentes sin fallo en su último trabajo / asistentes de área · ahora · más es mejor
- EQU-ROLES · roles con ocupante / roles · ahora · más es mejor
- FIN-AR · Σ pendiente de facturas emitidas vencidas · ahora · menos es mejor
- FIN-CASH · saldo inicial + movimientos importados (desconocido sin saldo inicial) · ahora · más es mejor
- FIN-MARGIN · (ingresos facturados − gastos recibidos) / ingresos (devengo) · cada mes · más es mejor
- FIN-RUNWAY · caja disponible / salida fija mensual normalizada (media 3 meses) · ahora · más es mejor
- FIN-UNREC · movimientos sin conciliar ni ignorar · ahora · menos es mejor
- MAR-PUB · contenidos publicados con evidencia en el mes · cada mes · más es mejor
- MAR-QCONV · conversaciones cualificadas en el mes · cada mes · más es mejor
- VEN-CONV · aceptadas+ganadas / con propuesta (90 días) · últimos 90 días · más es mejor
- VEN-FCST · Σ valor × probabilidad de la etapa (previsión) · ahora · más es mejor
- VEN-PIPE · suma del valor de oportunidades abiertas · ahora · más es mejor
- VEN-STALE · abiertas sin contacto en 14 días · ahora · menos es mejor
- VEN-WON · Σ valor de oportunidades ganadas (cobro confirmado) en el mes · cada mes · más es mejor
