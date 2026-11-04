---
tls_type: delivery_template
tls_schema: 1
id: e010d31f-dd54-5b20-b052-7c8af8bdb8f0
nombre: Plan de entrega · Renta
clase: entrega
servicio: "[[2 · Ventas/Productos/renta|Renta]]"
version: 1
estado: En uso
dias_proyecto: 10
terminado_cuando: Declaración presentada, justificante archivado y enviado al cliente.
---
# Plan de entrega · Renta
> En uso · 10 días

## Terminado cuando
Declaración presentada, justificante archivado y enviado al cliente.

## Fase 1 · Onboarding
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Solicitar documentación al cliente | 0 | 2 |  | agente:implementador | Lista de documentos recibidos y pendientes en un comentario. |

- Solicitar documentación al cliente: Datos fiscales, certificados de retenciones, deducciones (vivienda, donativos, alquiler) y cambios familiares.

## Fase 2 · Preparación
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Descargar datos fiscales y borrador de la AEAT | 2 | 1 |  | responsable | Datos fiscales guardados en la carpeta del cliente. |
| Preparar la declaración y comparar con el borrador | 3 | 3 |  | agente:implementador | Resumen de diferencias y resultado previsto. |

- Descargar datos fiscales y borrador de la AEAT: Requiere acceso con certificado o Cl@ve del cliente: lo hace una persona.
- Preparar la declaración y comparar con el borrador: Revisar deducciones aplicables y diferencias con el borrador.

## Fase 3 · Revisión
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Revisar el resultado con el cliente y obtener conformidad | 6 | 2 |  | responsable | Conformidad del cliente por escrito. |

## Fase 4 · Presentación y cierre
| Tarea | Día | Dura | Margen | Quién | Se acepta cuando |
|---|---|---|---|---|---|
| Presentar la declaración y archivar el justificante | 8 | 1 |  | responsable | Justificante de presentación en la carpeta. |
| Enviar justificante y pedir valoración | 9 | 1 |  | agente:implementador | Mensaje preparado para enviar tras aprobación. |

- Presentar la declaración y archivar el justificante: Acción con efectos oficiales: solo una persona autorizada.

## Pagos por fase

## Kit por sesión
