---
tls_type: import_report
tls_schema: 1
id: 07d8f5fc-1a95-5849-8d81-b615a2680a95
fecha: 2026-10-19
fuente: G2 · DEV - Asesoría Ribera
ficheros: 189
convertidos: 173
archivados: 1
verificados: 9
estado: Aplicado
---
# Importación del 19 oct 2026
> Aplicado · 189 ficheros de origen · no se borró nada

## Resumen
| Qué | Cuántos |
|---|---|
| Ficheros de origen | 189 |
| Registros convertidos | 173 |
| Notas creadas | 113 |
| Tablas CSV creadas | 6 |
| Ficheros copiados tal cual (PDF y CSV) | 15 |
| Justificantes comprobados con su huella | 9 |
| Fichas de tarea creadas | 2 |
| Guardados sin convertir en Archivo | 1 |

## Por bloques
| Bloque de origen | Ficheros | Destino |
|---|---|---|
| Dirección/Decisiones | 2 | 1 · Dirección/Decisiones.md y Decisiones/ |
| Dirección/Decisiones (abiertas) | 2 | Tareas/ de su área, una ficha por tarea |
| Dirección/KPI | 21 | 1 · Dirección/Metas.md |
| Dirección/Objetivos | 6 | 1 · Dirección/Objetivos |
| Dirección/Rutinas | 2 | 1 · Dirección/Rutinas |
| Empresa.md | 1 | Empresa.md, .tls/config.yaml y las seis Área.md |
| Entrega/Servicios | 2 | 2 · Ventas/Productos y 3 · Entrega/Planes de entrega |
| Equipo/Roles | 6 | 6 · Equipo/Roles |
| Finanzas/<año>/<trimestre>/Cobros y pagos | 17 | 4 · Finanzas/Registros/pagos.csv |
| Finanzas/<año>/<trimestre>/Gastos | 11 | 4 · Finanzas/Registros/recibidas.csv |
| Finanzas/<año>/<trimestre>/Ingresos | 7 | 4 · Finanzas/Fiscal/<año>/<trimestre>/Ingresos |
| Finanzas/<año>/<trimestre>/Paquete gestoría | 1 | 4 · Finanzas/Fiscal/<año>/<trimestre>/Modelos/Paquete gestoría |
| Finanzas/Bancos | 2 | 4 · Finanzas/Registros/Bancos/<cuenta> |
| Finanzas/Bancos/<cuenta>/<trimestre> | 30 | 4 · Finanzas/Registros/Bancos/<cuenta>/movimientos.csv |
| Finanzas/Bancos/extractos | 1 | 4 · Finanzas/Registros/Bancos/<cuenta>/Extractos |
| Justificantes y Documentos | 9 | 4 · Finanzas/Fiscal/<año>/<trimestre>/Gastos/<proveedor> |
| Lo que no tiene conversión | 1 | Archivo/Importación 2026-10-19 |
| Marca/Contenidos | 7 | 5 · Marca/Contenidos |
| Marca/Conversaciones | 4 | 5 · Marca/Conversaciones |
| Marca/Identidad.md | 1 | 5 · Marca/Marca.md |
| Ventas/Contactos | 14 | 2 · Ventas/Contactos |
| Ventas/Guiones | 1 | 2 · Ventas/Activos |
| Ventas/Ofertas | 3 | 2 · Ventas/Productos/Versiones |
| Ventas/Oportunidades | 14 | 2 · Ventas/Oportunidades |
| Ventas/Organizaciones | 10 | 2 · Ventas/Empresas |

## Lo que se quedó donde estaba
La carpeta de origen no se ha tocado. Lo que no tiene sitio en la estructura nueva se guarda tal cual en `Archivo/Importación 2026-10-19/`:
- [LEEME.md](../Archivo/Importación%202026-10-19/LEEME.md)

## Duplicados
Ninguno.

## Calidad de los datos
| Aviso | Fichas | Qué hacer |
|---|---|---|
| CSV del paquete de la gestoría con la columna id mal exportada (lista de números) | 4 | Se copian tal cual; vuelve a generar el paquete desde la app. |
| Gastos sin justificante | 2 | Busca el original y guárdalo en su carpeta de Gastos. |
| Los días de los planes de entrega se copian tal cual (G2 no dice si son laborables) | 2 | Confírmalo: en la v2 los días de un plan son laborables. |
| Notas que se guardan sin convertir en Archivo (nota sin tipo) | 1 | Revísalas en Archivo/Importación 2026-10-19/ y decide si las quieres en un área. |
| Oportunidades y facturas que citan un proyecto que no está en la exportación | 12 | Crea el proyecto de entrega si hace falta; la referencia no se ha copiado. |
| Quién hace cada tarea del plan, con los nombres de la v2 (agent:entrega → agente:implementador; lead → responsable) | 2 | Nada, salvo que en tu empresa se llamen de otra forma. |
| Roles con ocupante sin nombre (G2 solo guarda un identificador) | 6 | Escribe quién ocupa el rol en «ocupante». |

## Campos sin convertir
| Campo de G2 | Fichas | Por qué |
|---|---|---|
| account.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| account.version | 2 | Número de revisión interno de G2. |
| company.areas.color | 1 | La app usa su propia paleta por área. |
| company.cuerpo | 1 | Explica el formato de G2; no describe la empresa. |
| company.profile.servicios | 1 | Los servicios son sus fichas en Productos. |
| company.workspace_id | 1 | Identificador del espacio de G2; la carpeta nueva tiene su propio id. |
| contact.updated_at | 14 | Fecha interna de G2: la app guarda su propio historial. |
| contact.version | 14 | Número de revisión interno de G2. |
| content.created_at | 7 | La pieza se fecha por «publicar» y «publicado». |
| content.updated_at | 7 | Fecha interna de G2: la app guarda su propio historial. |
| content.version | 7 | Número de revisión interno de G2. |
| conversation.created_at | 4 | La conversación se fecha por cuándo ocurrió. |
| conversation.updated_at | 4 | Fecha interna de G2: la app guarda su propio historial. |
| conversation.version | 4 | Número de revisión interno de G2. |
| decision.author_id | 4 | G2 no guarda nombres de personas, solo identificadores. |
| decision.author_type | 4 | G2 no guarda nombres de personas, solo identificadores. |
| decision.updated_at | 4 | Fecha interna de G2: la app guarda su propio historial. |
| decision.version | 4 | Número de revisión interno de G2. |
| document.updated_at | 9 | Fecha interna de G2: la app guarda su propio historial. |
| document.version | 9 | Número de revisión interno de G2. |
| invoice.currency | 7 | Todo está en euros (EUR). |
| invoice.nature | 18 | La naturaleza (fijo, variable o inversión) es solo de los gastos. |
| invoice.paid_minor | 18 | La app calcula lo cobrado a partir de pagos.csv. |
| invoice.payment_terms_days | 18 | Queda en la fecha de vencimiento. |
| invoice.project_id | 6 | Los proyectos no están en la exportación. |
| invoice.updated_at | 18 | Fecha interna de G2: la app guarda su propio historial. |
| invoice.version | 18 | Número de revisión interno de G2. |
| kpi.updated_at | 21 | Fecha interna de G2: la app guarda su propio historial. |
| kpi.version | 21 | Número de revisión interno de G2. |
| movement.counterparty | 15 | movimientos.csv no tiene columna de contraparte; va en el concepto. |
| movement.updated_at | 30 | Fecha interna de G2: la app guarda su propio historial. |
| movement.version | 30 | Número de revisión interno de G2. |
| objective.owner_id | 6 | G2 no guarda nombres de personas, solo identificadores. |
| objective.owner_type | 6 | G2 no guarda nombres de personas, solo identificadores. |
| objective.updated_at | 6 | Fecha interna de G2: la app guarda su propio historial. |
| objective.version | 6 | Número de revisión interno de G2. |
| opportunity.last_contact_at | 14 | La app calcula el último contacto. |
| opportunity.owner_id | 12 | G2 no guarda nombres de personas, solo identificadores. |
| opportunity.owner_type | 12 | G2 no guarda nombres de personas, solo identificadores. |
| opportunity.project_id | 6 | Los proyectos no están en la exportación. |
| opportunity.stage (entrada, cualificacion) | 3 | En la v2 las dos etapas son «Prospecto». |
| opportunity.updated_at | 14 | Fecha interna de G2: la app guarda su propio historial. |
| opportunity.version | 14 | Número de revisión interno de G2. |
| organization.updated_at | 10 | Fecha interna de G2: la app guarda su propio historial. |
| organization.version | 10 | Número de revisión interno de G2. |
| payment.confirmed_at | 17 | Momento interno de la confirmación; queda «verificacion: confirmado». |
| payment.confirmed_by_id | 17 | G2 no guarda nombres de personas, solo identificadores. |
| payment.confirmed_by_type | 17 | G2 no guarda nombres de personas, solo identificadores. |
| payment.updated_at | 17 | Fecha interna de G2: la app guarda su propio historial. |
| payment.version | 17 | Número de revisión interno de G2. |
| period.updated_at | 1 | Fecha interna de G2: la app guarda su propio historial. |
| period.version | 1 | Número de revisión interno de G2. |
| role.occupant_id | 6 | G2 no guarda nombres de personas, solo identificadores. |
| role.updated_at | 6 | Fecha interna de G2: la app guarda su propio historial. |
| role.version | 6 | Número de revisión interno de G2. |
| routine.author_id | 2 | G2 no guarda nombres de personas, solo identificadores. |
| routine.author_type | 2 | G2 no guarda nombres de personas, solo identificadores. |
| routine.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| routine.version | 2 | Número de revisión interno de G2. |
| service.template.phases.tasks.status | 2 | Columna del tablero de G2: en la v2 el estado lo lleva cada tarea. |
| service.template_version | 2 | Pasa a «version» del plan de entrega. |
| service.updated_at | 2 | Fecha interna de G2: la app guarda su propio historial. |
| service.version | 2 | Número de revisión interno de G2; la versión del servicio sale de su oferta vigente. |
| service.workflow_id | 2 | Identificador interno de G2. |

## Cómo deshacer
La conversión crea una carpeta nueva y no cambia la de origen. Para deshacerla, retira esta carpeta.
