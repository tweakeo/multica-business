---
tls_type: agreement
tls_schema: 1
id: "{{id}}"
ref: "AC-{{fecha}}-{{empresa.slug}}"
oportunidad: "{{oportunidad.enlace}}"
empresa: "{{empresa.enlace}}"
contacto: "{{contacto.enlace}}"
servicio: "{{servicio.enlace}}"
oferta_version: "{{oferta.enlace}}"
estado: Borrador                # Borrador | Enviado | Aceptado | Terminado
aceptacion: pago                # pago | firma
aceptado_el:
inicio:
duracion:                       # «8 semanas», «12 meses»
fin:
base:
iva_pct:
retencion_pct:
total:
pdf:
pdf_sha256:
plantilla: "Contrato v1"
---
# Acuerdo de servicios con {{empresa.razon_social}}
> {{estado}} · {{servicio.nombre}} · {{total:€}} · se acepta con el {{aceptacion}}

## Partes
| Dato | Prestador | Cliente |
|---|---|---|
| Nombre | {{mi_empresa.nombre}} | {{empresa.razon_social}} |
| NIF | En el PDF | {{empresa.nif}} |
| Domicilio | En el PDF | {{empresa.domicilio}}, {{empresa.cp}} {{empresa.ciudad}} |
| Representante | {{yo.nombre}} | {{contacto.nombre}} |

## Cómo se acepta
Este acuerdo se acepta con el pago de la primera factura o con la firma de ambas partes, lo que ocurra antes. El Anexo I prevalece sobre las cláusulas generales.

## Cláusulas
> Guía: textos de partida, cortos y generales. Revísalos con tu asesor antes de usarlos.

1. **Objeto.** El prestador realiza para el cliente el servicio descrito en el Anexo I.
2. **Alcance.** Se incluye lo que aparece en el Anexo I. Lo demás se presupuesta aparte.
3. **Forma de trabajo.** El servicio se presta en sesiones y tareas según el calendario del Anexo I.
4. **Obligaciones del prestador.** Hacer el trabajo con diligencia, en plazo, e informar del avance.
5. **Obligaciones del cliente.** Facilitar a tiempo la información y los accesos necesarios y asistir a las sesiones.
6. **Plazo e inactividad.** Si el cliente no responde durante el plazo indicado en el Anexo I, el calendario se desplaza y puede darse por terminado.
7. **Precio y pago.** El precio y los plazos de pago son los del Anexo I. Las facturas vencen en los días indicados.
8. **Propiedad intelectual.** Lo entregado es del cliente una vez pagado. El prestador conserva sus métodos y plantillas.
9. **Confidencialidad.** Ninguna parte comparte información de la otra sin permiso.
10. **Protección de datos.** Si el prestador trata datos personales del cliente, se aplica el Anexo II.
11. **Garantía.** El prestador corrige sin coste los errores suyos que se comuniquen en el plazo indicado.
12. **Responsabilidad.** La responsabilidad del prestador se limita al importe cobrado por el servicio.
13. **Fuerza mayor.** Ninguna parte responde de lo que no pueda evitar razonablemente.
14. **Terminación.** Cualquiera de las partes puede terminar el acuerdo con preaviso escrito; se paga lo hecho hasta ese día.
15. **Cesión.** Ninguna parte cede el acuerdo sin permiso de la otra.
16. **Independencia.** Las partes son independientes; este acuerdo no crea relación laboral.
17. **Ley y jurisdicción.** Se aplica la ley española y los juzgados del domicilio del prestador.

## Anexo I · Servicio contratado
| Dato | Valor |
|---|---|
| Servicio | {{servicio.nombre}} · versión {{oferta.version}} |
| Qué incluye | {{oferta.incluye}} |
| Qué no incluye | {{oferta.no_incluye}} |
| Inicio y duración | {{inicio:larga}} · {{duracion}} |
| Precio | {{base:€}} + IVA |
| Plazo de inactividad | 30 días |
| Garantía | 15 días desde la entrega |

| Pago | Cuándo | Base | IVA | Retención | Total |
|---|---|---|---|---|---|
| {{pago.nombre}} ({{pago.pct:%}}) | {{pago.cuando}} | {{pago.base:€}} | {{pago.iva:€}} | −{{pago.retencion:€}} | {{pago.total:€}} |

## Anexo II · Tratamiento de datos
> Guía: opcional. Solo si vas a tratar datos personales de clientes o empleados del cliente.

## Aceptación
| Parte | Nombre | Fecha |
|---|---|---|
| Prestador | {{yo.nombre}} | |
| Cliente | {{contacto.nombre}} | |
