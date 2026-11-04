---
tls_type: task
tls_schema: 1
id: d2730502-312b-49e3-b7ca-bd17e3f523e6
numero: T-0031
titulo: Preparar la factura de Trimestrales para Talleres Martín
estado: Hecha
prioridad: Alta
tipo: tarea
responsable: agente:contable
planificada: 2026-10-14
vence: 2026-10-16
estimacion_h: 0.5
dedicadas_h: 0.25
area: finanzas
oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
capacidad: FIN-10
origen: regla:oportunidad.aceptada
creada: 2026-10-14
creada_por: sistema
cerrada: 2026-10-15
plantilla: "Tarea v1"
---
# Preparar la factura de Trimestrales para Talleres Martín
> Hecha · Contable (asistente) · cerrada el 15 oct

## Descripción
La oportunidad pasó a Aceptada el 14 de octubre. Hay que preparar la factura de Trimestrales T4 desde la propuesta aceptada (Trimestrales v1: 150 € + IVA, vence a 15 días) y dejarla lista para que Elena la emita.

- [x] Comprobar los datos fiscales de la empresa
- [x] Preparar el borrador con la línea de la propuesta
- [x] Dejarlo pendiente de OK en Decisiones

## Actividad
<!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

### 2026-10-14 09:12 · sistema
Creada por la regla «oportunidad aceptada» desde [Jorge Martín · Trimestrales](../../2%20·%20Ventas/Oportunidades/jorge-martin-trimestrales.md). Asignada a Contable (asistente).
<!-- tls:evento {"id":"ev-3f9a1c","tipo":"creacion","regla":"oportunidad.aceptada","clave":"79f8cc54:oportunidad.aceptada"} -->

### 2026-10-14 09:20 · agente:contable
Estado: Por hacer → En revisión. No puedo completar el borrador: a [Talleres Martín e Hijos SL](../../2%20·%20Ventas/Empresas/talleres-martin-e-hijos.md) le faltan el NIF y el domicilio. Lo dejo con «[falta: empresa.nif]» y «[falta: empresa.domicilio]». ¿Me los consigues?
<!-- tls:evento {"id":"ev-7d1e2a","tipo":"ejecucion","de":"Por hacer","a":"En revisión","run":"r-2b81","coste_usd":0.02} -->

### 2026-10-14 12:41 · Lucía Navarro
Me los ha pasado Jorge por correo y ya están en la ficha de la empresa. @Contable

### 2026-10-14 12:44 · agente:contable
Retomo la tarea por tu mención. [Borrador de factura](../Fiscal/2026/T4/Ingresos/f-2026-0007.md) completo: 150,00 € + IVA 31,50 € = 181,50 €, vence a 15 días de la emisión. Sin retención: Asesoría Ribera es una sociedad. Sigue En revisión, pendiente de tu OK en Decisiones.
<!-- tls:evento {"id":"ev-a04c77","tipo":"ejecucion","de":"En revisión","a":"En revisión","run":"r-2b9f","coste_usd":0.03,"aprobacion":"apr-5c2e"} -->

### 2026-10-15 09:05 · Elena Castell
Revisada y emitida como F-2026-0007. Enviada a Jorge. Estado: En revisión → Hecha.
<!-- tls:evento {"id":"ev-c81f03","tipo":"estado","de":"En revisión","a":"Hecha","aprobacion":"apr-5c2e"} -->
