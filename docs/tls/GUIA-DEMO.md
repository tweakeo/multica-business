# TLS · Guía de la demo: Asesoría Ribera

Esta guía explica cómo se trabaja con TLS como si la gestoría ya funcionara con él. **Todos los datos son ficticios.**

## 1. Arrancar

**Instalada desde el DMG (lo normal):**
1. Abre `TLS-0.1.0.dmg` y arrastra TLS a Aplicaciones.
2. La primera vez, permite abrirla en *Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente*.
3. TLS arranca sola su base de datos y su servidor y entra en la demo como **Elena Ribera**, la dueña de la gestoría. No pide usuario ni código.

Volver a la demo inicial: cierra TLS y borra `~/Library/Application Support/TLS/runtime` y `~/TLS Empresas/DEMO - Asesoría Ribera`.

**Desarrollo con servidor externo:**
- `scripts/tls/start-demo.sh` arranca el servidor de desarrollo en `:8080` y pone la app en modo externo. En este modo se entra con `demo@tls.local` y el código fijo de desarrollo.
- `node scripts/tls/seed-demo.mjs --reset` recrea la demo en ese servidor (añade `--offline` para no lanzar agentes).

## 2. La empresa en la demo

**Asesoría Ribera** es una gestoría ficticia de Valencia con dos servicios. Cada servicio tiene su **canvas**, es decir, su propio tablero con las etapas del proceso:

| Servicio | Precio vigente | Canvas (columnas) |
|---|---|---|
| **Renta** (IRPF de particulares, anual) | 90 € + IVA por declaración. Hubo una versión anterior a 80 € | Por hacer → Documentación → Preparación → Revisión con cliente → Presentación de la renta → Hecho |
| **Trimestrales** (303/111 de empresas, cada trimestre) | 150 € + IVA por trimestre | Por hacer → Recogida de documentos → Contabilización → Conciliación → Modelos y validación → Presentación de modelos → Hecho |

Qué hay cargado:
- **Ventas:** 15 oportunidades en todas las etapas, con su canal de entrada y la pieza de contenido de la que vienen cuando la hay.
- **Entrega:** 3 Renta cerradas, 1 Renta fuera de plazo en curso y 2 Trimestrales T3 en curso con el plazo del 20/10 encima.
- **Finanzas:**
  - 2 cuentas bancarias y un extracto de julio a octubre.
  - Facturas emitidas y de proveedores, con PDF de justificante (salvo dos que faltan a propósito).
  - El paquete del T3 ya preparado.
- **Marca:** 7 piezas de contenido y 4 conversaciones de escucha, de las que 2 ya han pasado a Ventas.
- **Dirección:** objetivos del T4, 4 decisiones (2 tomadas y 2 abiertas) y los rituales de los últimos días.
- **Equipo:** 6 roles. Elena ocupa 5 («seis sombreros») y el agente de Marca ocupa uno.
- **6 agentes**, uno por área, coordinados por el agente de Dirección en el equipo «Comité de dirección».

La carpeta portable de la empresa está en `~/TLS Empresas/DEMO - Asesoría Ribera`. Ábrela con Finder: cada registro es un fichero Markdown legible.

## 3. Cómo se mira el negocio

En la barra lateral, el grupo **Empresa** tiene la vista general y las seis áreas, cada una con su color.

**Empresa → pestaña Empresa** (perspectiva de empresa):
- Caja y meses de caja (runway), con la fórmula y su cobertura.
- Dependencia del dueño y cuello de botella.
- Las seis áreas, con su salud explicada (nunca un verde inventado), sus indicadores y su etapa de madurez estimada.
- Objetivos del trimestre, decisiones abiertas y excepciones priorizadas.

**Mi foco** (perspectiva de ejecución): tu foco del día y su veredicto, tus tareas abiertas y lo que espera tu decisión.

**Cada área** tiene cuatro pestañas:
- **Resumen:** indicadores con meta y alerta, excepciones y madurez.
- **Gestión:** el trabajo del área (embudo, canvases, facturas y bancos, contenidos, equipo, objetivos y decisiones).
- **Análisis:** distribuciones y tendencias.
- **Sistemas:** las capacidades del área con su estado en esta build y el **modo de ejecución** (manual, asistido, supervisado o autónomo), roles, agente, servicios con su plantilla y definición de indicadores.

Pulsa cualquier registro para abrir el **inspector**: detalle, instantánea de la propuesta, relaciones, documentos, fichero en la carpeta, historial auditado y eventos, además de las acciones propias de ese registro.

Los indicadores distinguen entre **«Sin datos», «Sin meta», «Datos parciales» y «Desconocido»**. Un ejemplo de la demo: el margen del mes aparece como *datos parciales*, porque las cuotas de la cartera antigua se facturan fuera de TLS.

## 4. El viaje del cliente, paso a paso

### a) Entra un interesado (Ventas)
1. **Empresa → Nuevo interesado**: nombre, email, servicio y canal. Se crean de una vez el contacto, su empresa y la oportunidad (VEN-01). Si el email ya existía, se reutiliza: no hay duplicados.
2. El evento `contacto.creado` crea una tarea para **Ventas · Comercial**. El agente cualifica al interesado y anota el resultado en la oportunidad. Además redacta el primer mensaje, que **no se envía**: queda en **Aprobaciones**.
   - *En la demo ya ha pasado con Rosa Campos.* Abre **Aprobaciones**: verás el email con su destinatario y su asunto.
3. Aprueba o rechaza (rechazar exige motivo). Al aprobar, TLS vuelve a comprobar el contenido, la versión de la oportunidad y los controles globales. Si algo cambió, la aprobación se **invalida**. No hay integración de correo: el mensaje queda registrado como «pendiente de envío manual».

### b) De la propuesta al cobro
1. **Ventas → Gestión → Embudo**. Abre una oportunidad (por ejemplo, Arquitectura Nexo) y usa los botones de etapa. Cada etapa exige sus datos: responsable, servicio y propuesta.
2. **Generar propuesta** toma el precio de la oferta vigente y guarda una **instantánea**. Aunque el precio cambie después, esta propuesta y su factura no cambian.
3. **Registrar aceptación** exige evidencia (correo, firma, llamada). La oportunidad pasa a *Aceptada · pendiente de cobro* y se prepara automáticamente la **factura en borrador**.
4. **Finanzas → Gestión → Facturas emitidas**: abre el borrador y pulsa **Emitir factura**. Se asignan el número (F-2026-NNNN), la fecha y el vencimiento.

### c) El cobro confirma la venta y crea el proyecto
- **Prueba esto en la demo:** ve a **Finanzas → Gestión → Bancos y conciliación → Propuestos**. Hay un movimiento de **Talleres Martín** (181,50 €) que el sistema propone casar con la factura F-2026-0007. Pulsa **Confirmar**.
- Lo que ocurre a continuación:
  1. Se registra el cobro.
  2. La factura queda cobrada.
  3. El evento `cobro.confirmado` marca la oportunidad como **Ganada**.
  4. Se crea **un único proyecto** de Trimestrales para Talleres con las tareas de su plantilla. Tienen fechas de planificación y de vencimiento en días laborables, y las tareas de agente se asignan al agente de Entrega.
- Comprueba el resultado en **Entrega → Gestión** y en el tablero del proyecto (el canvas). Repetir el evento no crea un segundo proyecto.

### d) La entrega
- **Entrega → Gestión** muestra los proyectos de cada canvas con su avance, sus tareas vencidas y el próximo vencimiento. Pulsa uno para abrir el tablero de Multica con las columnas del servicio.
- Las tareas de persona (por ejemplo, presentar con certificado) y las de agente (pedir documentación, contabilizar, conciliar) conviven en el mismo tablero.
- Para cerrar un proyecto hace falta resultado y evidencia, y que no queden tareas abiertas. Al cerrarlo se preparan la petición de referido y el caso de cliente.

### e) El trimestre se prepara solo (tu propia gestoría)
- **Finanzas → Gestión → Trimestres → 2026 T3**: el paquete ya está preparado en `Finanzas/2026/T3/Paquete gestoría/` (índice, libros de ingresos y gastos, movimientos y diferencias).
- El agente Financiero lo ha revisado. Ha detectado el justificante de Movil Levante que falta y ha advertido de que las cuotas de cartera (facturadas fuera de TLS) dejan corto el IVA repercutido. Lee su comentario en la tarea «Revisar el paquete T3».
- Estados del periodo: preparado → aprobado → enviado → presentado → justificantes archivados → liquidación verificada. Desde el paso a *enviado* **se exige evidencia**. Reabrir exige motivo y queda en el historial.
- **Importar un extracto:** Bancos → Importar extracto CSV (formato en `FORMATOS.md`). Puedes reimportar `Finanzas/Bancos/extractos/cuenta-corriente-2026-07-a-10.csv` de la carpeta: verás 0 nuevos y N duplicados.

### f) Marca y atribución
- **Marca → Gestión**: el kanban de contenidos (idea → borrador → revisión → aprobado → programado → publicado). Para pasar a *publicado* hace falta el enlace de evidencia, y si lo pide un agente, aprobación.
- **Conversaciones**: cualifica una conversación de escucha para pasarla a Ventas como interesado, con su canal y la pieza de origen (atribución).

## 5. Trabajar con agentes

- Cada área tiene un agente con instrucciones propias (**Agentes** en la barra lateral). Leen y actúan **solo con `multica biz`**, la API de la empresa.
- **Pedir al agente** (botón en cada área, o el icono 🤖 en una excepción): escribe en lenguaje natural lo que quieres. Se crea una tarea asignada al agente del área y la sigues como cualquier tarea.
- Lo que hace un agente:
  - **Lecturas, cálculos y borradores internos:** directamente, si el modo de la capacidad lo permite.
  - **Acciones sensibles** (enviar, emitir, confirmar dinero, publicar, compromisos): crean una **aprobación**.
  - **Nunca** cambia políticas ni permisos, ni decide aprobaciones o decisiones.
- **Rituales automáticos:**
  - Cada día laborable a partir de las 8:00, el agente de Dirección propone el foco del día.
  - Los lunes prepara la semana.
  - El día 1 de cada mes, la rutina de equipo.
  - Al empezar un trimestre, el paquete y la revisión trimestral.
- **Bitácora** (Empresa → Bitácora): qué hizo cada agente, persona o automatismo, con su resultado. También los eventos de negocio con sus reintentos.
- **Confinamiento:** cada ejecución de agente corre en un sandbox de macOS. No puede leer ni escribir la carpeta de la empresa ni las credenciales, ni conectarse directamente a la base de datos: solo la API.

## 6. Controles

**Empresa → Controles y carpeta**:
- **Interruptor global:** detiene a todos los agentes y automatismos, cancela lo que está en cola y bloquea sus escrituras. Las personas siguen trabajando.
- **Modo lectura:** nadie modifica datos de negocio.
- **Pausa por área:** detiene solo a los agentes de esa área.
- **Carpeta portable:**
  - **Exportar todo**.
  - **Comparar carpeta y base de datos** (vista previa campo a campo).
  - **Reconstruir desde la carpeta**.
  - Detección de ficheros editados fuera de TLS y de IDs duplicados.
- Los **modos por capacidad** están en **cada área → Sistemas**.

## 7. Qué es real y qué no

| | Estado |
|---|---|
| CRM, embudo, propuestas con instantánea, facturas, cobros, conciliación, paquete trimestral | Real: reglas en el servidor y datos persistentes |
| Proyectos y tareas de entrega con canvas por servicio | Real (tareas y proyectos de Multica) |
| Agentes por área, aprobaciones, interruptor, auditoría, sandbox | Real; probado con ejecuciones de Claude |
| Envío de correos, agenda, publicación en redes | **Simulado**: queda registrado como «pendiente de envío/publicación manual» |
| Presentación de impuestos | **Fuera de alcance**: TLS prepara la documentación y la asesora presenta |
| Banca por API, Notion, formularios web, portal del cliente | Pendiente (ver `ESTADO.md`) |

Para usarlo con una empresa real conviene crear un workspace nuevo con su propia carpeta. No mezcles la demo con datos reales.
