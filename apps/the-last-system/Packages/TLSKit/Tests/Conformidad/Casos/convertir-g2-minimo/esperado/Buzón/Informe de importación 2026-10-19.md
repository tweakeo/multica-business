---
tls_type: import_report
tls_schema: 1
id: 7de4dfee-f62f-5ac8-94f8-46d54da94a00
fecha: 2026-10-19
fuente: G2 · entrada
ficheros: 33
convertidos: 28
archivados: 1
verificados: 1
estado: Aplicado
---
# Importación del 19 oct 2026
> Aplicado · 33 ficheros de origen · no se borró nada

## Resumen
| Qué | Cuántos |
|---|---|
| Ficheros de origen | 33 |
| Registros convertidos | 28 |
| Notas creadas | 40 |
| Tablas CSV creadas | 5 |
| Ficheros copiados tal cual (PDF y CSV) | 4 |
| Justificantes comprobados con su huella | 1 |
| Fichas de tarea creadas | 1 |
| Guardados sin convertir en Archivo | 1 |

## Por bloques
| Bloque de origen | Ficheros | Destino |
|---|---|---|
| Dirección/Decisiones | 1 | 1 · Dirección/Decisiones.md y Decisiones/ |
| Dirección/Decisiones (abiertas) | 1 | Tareas/ de su área, una ficha por tarea |
| Dirección/KPI | 2 | 1 · Dirección/Metas.md |
| Dirección/Objetivos | 1 | 1 · Dirección/Objetivos |
| Dirección/Rutinas | 1 | 1 · Dirección/Rutinas |
| Empresa.md | 1 | Empresa.md, .tls/config.yaml y las seis Área.md |
| Entrega/Servicios | 1 | 2 · Ventas/Productos y 3 · Entrega/Planes de entrega |
| Equipo/Roles | 1 | 6 · Equipo/Roles |
| Finanzas/<año>/<trimestre>/Cobros y pagos | 1 | 4 · Finanzas/Registros/pagos.csv |
| Finanzas/<año>/<trimestre>/Gastos | 1 | 4 · Finanzas/Registros/recibidas.csv |
| Finanzas/<año>/<trimestre>/Ingresos | 1 | 4 · Finanzas/Fiscal/<año>/<trimestre>/Ingresos |
| Finanzas/<año>/<trimestre>/Paquete gestoría | 1 | 4 · Finanzas/Fiscal/<año>/<trimestre>/Modelos/Paquete gestoría |
| Finanzas/Bancos | 1 | 4 · Finanzas/Registros/Bancos/<cuenta> |
| Finanzas/Bancos/<cuenta>/<trimestre> | 2 | 4 · Finanzas/Registros/Bancos/<cuenta>/movimientos.csv |
| Finanzas/Bancos/extractos | 1 | 4 · Finanzas/Registros/Bancos/<cuenta>/Extractos |
| Justificantes y Documentos | 1 | 4 · Finanzas/Fiscal/<año>/<trimestre>/Gastos/<proveedor> |
| Lo que no tiene conversión | 1 | Archivo/Importación 2026-10-19 |
| Marca/Contenidos | 1 | 5 · Marca/Contenidos |
| Marca/Conversaciones | 1 | 5 · Marca/Conversaciones |
| Marca/Identidad.md | 1 | 5 · Marca/Marca.md |
| Ventas/Contactos | 2 | 2 · Ventas/Contactos |
| Ventas/Guiones | 1 | 2 · Ventas/Activos |
| Ventas/Ofertas | 1 | 2 · Ventas/Productos/Versiones |
| Ventas/Oportunidades | 2 | 2 · Ventas/Oportunidades |
| Ventas/Organizaciones | 2 | 2 · Ventas/Empresas |

## Lo que se quedó donde estaba
La carpeta de origen no se ha tocado. Lo que no tiene sitio en la estructura nueva se guarda tal cual en `Archivo/Importación 2026-10-19/`:
- [LEEME.md](../Archivo/Importación%202026-10-19/LEEME.md)

## Duplicados
Ninguno.

## Calidad de los datos
| Aviso | Fichas | Qué hacer |
|---|---|---|
| CSV del paquete de la gestoría con la columna id mal exportada (lista de números) | 1 | Se copian tal cual; vuelve a generar el paquete desde la app. |
| Los días de los planes de entrega se copian tal cual (G2 no dice si son laborables) | 1 | Confírmalo: en la v2 los días de un plan son laborables. |
| Notas que se guardan sin convertir en Archivo (nota sin tipo) | 1 | Revísalas en Archivo/Importación 2026-10-19/ y decide si las quieres en un área. |
| Quién hace cada tarea del plan, con los nombres de la v2 (agent:entrega → agente:implementador; lead → responsable) | 1 | Nada, salvo que en tu empresa se llamen de otra forma. |
| Referencias a fichas que no están en la exportación (contact_id) | 1 | Revisa si falta algo en el origen; la referencia no se ha copiado. |
| Referencias a fichas que no están en la exportación (organization_id) | 2 | Revisa si falta algo en el origen; la referencia no se ha copiado. |
| Referencias a fichas que no están en la exportación (refs) | 1 | Revisa si falta algo en el origen; la referencia no se ha copiado. |
| Roles con ocupante sin nombre (G2 solo guarda un identificador) | 1 | Escribe quién ocupa el rol en «ocupante». |

## Campos sin convertir
| Campo de G2 | Fichas | Por qué |
|---|---|---|
| account.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| account.version | 1 | Número de revisión interno de G2. |
| company.areas.color | 1 | La app usa su propia paleta por área. |
| company.cuerpo | 1 | Explica el formato de G2; no describe la empresa. |
| company.profile.servicios | 1 | Los servicios son sus fichas en Productos. |
| company.workspace_id | 1 | Identificador del espacio de G2; la carpeta nueva tiene su propio id. |
| contact.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| contact.version | 2 | Número de revisión interno de G2. |
| content.created_at | 1 | La pieza se fecha por «publicar» y «publicado». |
| content.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| content.version | 1 | Número de revisión interno de G2. |
| conversation.created_at | 1 | La conversación se fecha por cuándo ocurrió. |
| conversation.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| conversation.version | 1 | Número de revisión interno de G2. |
| decision.author_id | 2 | G2 no guarda nombres de personas, solo identificadores. |
| decision.author_type | 2 | G2 no guarda nombres de personas, solo identificadores. |
| decision.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| decision.version | 2 | Número de revisión interno de G2. |
| document.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| document.version | 1 | Número de revisión interno de G2. |
| invoice.currency | 1 | Todo está en euros (EUR). |
| invoice.nature | 2 | La naturaleza (fijo, variable o inversión) es solo de los gastos. |
| invoice.paid_minor | 2 | La app calcula lo cobrado a partir de pagos.csv. |
| invoice.payment_terms_days | 2 | Queda en la fecha de vencimiento. |
| invoice.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| invoice.version | 2 | Número de revisión interno de G2. |
| kpi.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| kpi.version | 2 | Número de revisión interno de G2. |
| movement.counterparty | 1 | movimientos.csv no tiene columna de contraparte; va en el concepto. |
| movement.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| movement.version | 2 | Número de revisión interno de G2. |
| objective.owner_id | 1 | G2 no guarda nombres de personas, solo identificadores. |
| objective.owner_type | 1 | G2 no guarda nombres de personas, solo identificadores. |
| objective.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| objective.version | 1 | Número de revisión interno de G2. |
| opportunity.last_contact_at | 2 | La app calcula el último contacto. |
| opportunity.owner_id | 2 | G2 no guarda nombres de personas, solo identificadores. |
| opportunity.owner_type | 2 | G2 no guarda nombres de personas, solo identificadores. |
| opportunity.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| opportunity.version | 2 | Número de revisión interno de G2. |
| organization.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| organization.version | 2 | Número de revisión interno de G2. |
| payment.confirmed_at | 1 | Momento interno de la confirmación; queda «verificacion: confirmado». |
| payment.confirmed_by_id | 1 | G2 no guarda nombres de personas, solo identificadores. |
| payment.confirmed_by_type | 1 | G2 no guarda nombres de personas, solo identificadores. |
| payment.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| payment.version | 1 | Número de revisión interno de G2. |
| period.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| period.version | 1 | Número de revisión interno de G2. |
| role.occupant_id | 1 | G2 no guarda nombres de personas, solo identificadores. |
| role.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| role.version | 1 | Número de revisión interno de G2. |
| routine.author_id | 1 | G2 no guarda nombres de personas, solo identificadores. |
| routine.author_type | 1 | G2 no guarda nombres de personas, solo identificadores. |
| routine.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| routine.version | 1 | Número de revisión interno de G2. |
| service.template.phases.tasks.status | 1 | Columna del tablero de G2: en la v2 el estado lo lleva cada tarea. |
| service.template_version | 1 | Pasa a «version» del plan de entrega. |
| service.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| service.version | 1 | Número de revisión interno de G2; la versión del servicio sale de su oferta vigente. |
| service.workflow_id | 1 | Identificador interno de G2. |

## Cómo deshacer
La conversión crea una carpeta nueva y no cambia la de origen. Para deshacerla, retira esta carpeta.
