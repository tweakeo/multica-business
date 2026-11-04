---
active: true
archived_at: null
code: TRIM
created_at: "2026-10-19T23:52:02.242157+02:00"
description: 'Impuestos trimestrales de empresas y autónomos (303 y 111): recogida, contabilización, conciliación, modelos y presentación antes del día 20.'
id: 421c377d-c090-48e7-bdb2-05237cea71b5
name: Trimestrales
recurrence: quarterly
template:
  done_when: Modelos presentados antes del día 20, justificantes archivados y resumen enviado al cliente.
  phases:
    - name: Recogida
      tasks:
        - acceptance: Inventario de documentos recibidos y faltantes.
          assignee: agent:entrega
          duration: 3
          offset: 0
          status: trim_recogida
          title: Solicitar facturas emitidas, recibidas y extractos del trimestre
    - name: Contabilidad
      tasks:
        - acceptance: Libros de ingresos y gastos del trimestre completos.
          assignee: agent:entrega
          duration: 4
          offset: 3
          status: trim_contabilizacion
          title: Contabilizar facturas y clasificar gastos
        - acceptance: Lista de diferencias con su explicación o pregunta al cliente.
          assignee: agent:entrega
          duration: 2
          offset: 6
          status: trim_conciliacion
          title: Conciliar bancos y listar diferencias
    - name: Modelos
      tasks:
        - acceptance: Borradores revisados por la asesora.
          assignee: lead
          description: Revisión profesional obligatoria.
          duration: 2
          offset: 8
          status: trim_modelos
          title: Preparar borradores de los modelos 303 y 111
        - acceptance: Conformidad escrita del cliente.
          assignee: lead
          duration: 1
          offset: 10
          status: trim_modelos
          title: Validación del cliente y aviso del cargo
    - name: Presentación
      tasks:
        - acceptance: Justificantes en la carpeta del cliente.
          assignee: lead
          description: 'Acción con efectos oficiales: solo una persona con certificado.'
          due_slack: 0
          duration: 1
          offset: 11
          status: trim_presentacion
          title: Presentar modelos y archivar justificantes
  project_days: 14
template_version: 1
tls_schema: 1
tls_type: service
updated_at: "2026-10-19T23:52:02.242157+02:00"
version: 1
workflow_id: 758d3cbc-6e9a-47e8-9b88-623f32e1d831
---


