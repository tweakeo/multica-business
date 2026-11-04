# Guion común de las maquetas

> **Qué es esto.** El guion que comparten las 6 maquetas de `DIRECCIONES.md` para que la comparación sea
> justa: los mismos datos, la misma barra lateral, las mismas tres pantallas, los mismos textos y los mismos
> estados. Lo único que cambia entre maquetas es la dirección de diseño.
>
> **Estado:** propuesta · 22/10/2026 · no cambia nada en la app ni en ninguna carpeta.
>
> **Datos:** todo es de **Asesoría Ribera**, una empresa ficticia (la demo de `~/TLS Empresas/DEV -
> Asesoría Ribera`). No hay datos de clientes reales. Donde el guion amplía o ajusta la demo, lo dice en §8 para
> que el trabajo de plantillas lo alinee.
>
> **Rutas:** las de la carpeta v2 de `SISTEMAS.md` §1.2. Las plantillas de documento todavía no existen en
> `docs/propuesta/plantillas/EJEMPLOS/`; los tres documentos de §6 se definen aquí y el trabajo de plantillas
> los toma como referencia.

---

## 0. Reglas de la comparación

1. **Mismo lienzo:** ventana de Mac de 1440 × 900 pt al 100 %, con sus tres botones de ventana. La barra
   lateral mide lo que diga cada dirección (entre 232 y 260 pt).
2. **Claro y oscuro** con un conmutador visible. Cada maqueta abre en el modo natural de su dirección (Saldo en
   oscuro; las demás en claro).
3. **Mismos datos y mismos textos, al pie de la letra.** Los textos entre comillas («…») de este guion se
   copian tal cual. No se inventan cifras, nombres ni fechas.
4. **Mismos estados** (lista de §7). Cada estado se puede ver con un clic, sin trucos.
5. **Interacción viva mínima:** recorrer la gráfica y cambiar de periodo; entrar en el modo edición de la barra
   lateral, arrastrar fuera, ver «Ocultos», indentar y salir con «Listo»; editar el inicio; arrastrar una
   tarjeta del tablero (con el bloqueo de Ganada); cambiar de pestaña en Documento y resaltar las líneas de un
   bloque. Cada gesto de arrastre enseña también su alternativa con un clic (menú contextual).
6. **Accesible:** los colores, tamaños y contrastes son los de la dirección; foco visible con el teclado.
7. **Sin emojis** y sin la estética de Obsidian ni de Multica (nada de árbol de ficheros como navegación ni
   paneles grises de editor).
8. **Insignia «EJEMPLO»** siempre visible: es la empresa de ejemplo.

---

## 1. La empresa, las personas y el día

| Qué | Valor |
|---|---|
| Empresa | Asesoría Ribera Demo SL (ficticia) · Valencia · asesoría fiscal y contable · 2 personas |
| Logo | Monograma «AR» (no hay logo aportado: es el provisional que genera la app) |
| Titular | **Elena Sanchis** (ficticia). Es quien usa la app. Roles: Dirección y Finanzas |
| Empleada | **Lucía Andreu** (ficticia). Roles: Comercial e Implementadora |
| Asistentes | Mika (coordina) · Comercial · Implementador · Contable · Cartero · Ordenador. Marca, en pausa. Equipo, apagado |
| Servicios (la Oferta) | Trimestrales: 150 € por trimestre (165 € desde el 1T de 2027, decisión del 19 oct) · Renta: 90 € por declaración · Consulta fiscal: 60 € por hora |
| Valor de una oportunidad | Lo que se facturaría el primer año: Trimestrales 600 € (4 × 150 €), Renta 90 € |
| Etapa | 2 · Estandarización |
| **Hoy** | **Jueves, 22 de octubre de 2026, 9:05.** El jueves toca el cierre de semana (12:00, 20 min) |
| Tope de horas | 4 h al día |

---

## 2. La barra lateral (idéntica en las seis)

### 2.1 Estado normal

De arriba abajo, con estos textos y contadores:

| Elemento | Texto | Dato a la derecha o debajo |
|---|---|---|
| Empresa | «Asesoría Ribera» con el monograma «AR» | Insignia «EJEMPLO» |
| Favoritos (solo iconos) | Caja · CRM · Facturas y cobros | Nombre al pasar el puntero |
| Hoy | «Hoy» | — (seleccionado en la pantalla 1) |
| Decisiones | «Decisiones» | «3» |
| Tareas | «Tareas» | «3 para hoy» |
| Sección | «Áreas» | — |
| 1 · Dirección | «1 · Dirección» | «activa» |
| 2 · Ventas | «2 · Ventas» | «activa» y el aviso «2 quietas» con triángulo (seleccionada en la pantalla 2) |
| 3 · Entrega | «3 · Entrega» | «activa» |
| 4 · Finanzas | «4 · Finanzas» | «activa» |
| 5 · Marca | «5 · Marca» | «preparada» |
| 6 · Equipo | «6 · Equipo» | «en reposo» (atenuada) |
| Asistentes | «Asistentes» | «1 trabajando» |
| Carpeta | «Carpeta» | — |
| Sección | «Recientes» | — |
| Reciente 1 | «Factura · Arquitectura Nexo» | «borrador» |
| Reciente 2 | «Facturación y cobros» | «sistema» |
| Reciente 3 | «Sergio Nexo» | «contacto» |

El pie de la barra queda vacío. Cada área lleva su icono (Dirección brújula, Ventas gráfica que sube, Entrega
caja, Finanzas tarjeta, Marca destellos y Equipo dos personas) y su color.

### 2.2 Estado de edición (se enseña en la pantalla 1)

Una foto fija del momento, idéntica en las seis:
- Se ha entrado manteniendo pulsado «Tareas». Arriba, el botón «Listo».
- Todos los elementos muestran el «−» y el asa, **menos Hoy**, que lleva un candado («Hoy no se puede ocultar»).
- **«Directorio»** está añadido e **indentado bajo «2 · Ventas»** (segundo nivel).
- **«5 · Marca»** se está arrastrando fuera de la barra, a más de 40 pt, con el rótulo **«Ocultar»**.
- La bandeja **«Ocultos»** contiene **«6 · Equipo»** y **«Carpeta»**, cada uno con «Mostrar».
- Aviso abajo durante 6 s: **«Ocultaste 6 · Equipo · Deshacer»**.

### 2.3 Menú contextual de un elemento (alternativa sin arrastrar)

Sobre «Directorio»: «Subir» · «Bajar» · «Meter en grupo» · «Sacar del grupo» · «Fijar en favoritos» ·
«Ocultar», con los atajos ⌥⌘↑, ⌥⌘↓, ⌘] y ⌘[ donde toque. Al final, separado: «Editar barra lateral» y
«Restaurar barra original».

### 2.4 Barra de herramientas

- Buscador «Buscar o hacer…» con ⌘K.
- Botón «Mika» con ⌘J.
- Interruptor «Asistentes encendidos».
- Insignia «Ejemplo: lo que cambies se queda en esta carpeta».

---

## 3. Datos

### 3.1 Las seis áreas

| Área | Estado | La lleva | Número clave | Valor | Meta | Alerta | Ritmo (con icono y palabra) |
|---|---|---|---|---|---|---|---|
| 1 · Dirección | Activa | Elena con Mika | DIR-DEC14 · decisiones sin tomar a los 14 días | 0 | 0 | 1 | «En ritmo» |
| 2 · Ventas | Activa | Lucía con el asistente Comercial | VEN-STALE7 · oportunidades quietas 7 días o más | 2 | 0 | 1 | «En alerta» |
| 3 · Entrega | Activa | Lucía con el asistente Implementador | ENT-ONTIME · trimestres presentados a tiempo | 6 de 6 (100 %) | 100 % | por debajo de 100 % | «En ritmo» |
| 4 · Finanzas | Activa | Elena con el asistente Contable | FIN-RUNWAY · meses de caja | 6,0 | 3 | por debajo de 3 | «En ritmo» |
| 5 · Marca | Preparada | Elena (el asistente Marca está en pausa) | MAR-PUB · publicadas sobre planificadas | 1 de 2 | «Sin meta» | — | «Sin meta» |
| 6 · Equipo | En reposo | — | EQU-ROLES · áreas con un dueño distinto de ti | «Sin dato» | «Sin meta» | — | «En reposo» |

Frases por área para el módulo «Ritmo por área»:
- «1 · Dirección · Ninguna decisión atascada»
- «2 · Ventas · 2 oportunidades quietas»
- «3 · Entrega · 6 de 6 trimestres presentados a tiempo»
- «4 · Finanzas · 6,0 meses de caja»
- «5 · Marca · 1 de 2 publicaciones este mes»
- «6 · Equipo · Se activa en la etapa 5»

Cabecera de Ventas (pantalla 2): «Convierte desconocidos en clientes» · «La lleva Lucía (Comercial) con el
asistente Comercial» · pregunta «¿De dónde sale el próximo cliente?».

### 3.2 Caja

**Hoy: 18.719,45 €.** Cuenta corriente; la cuenta de ahorro no entra en este ejemplo.

**Meses de caja: 6,0.** Caja ÷ gasto medio mensual de julio a septiembre (3.126,85 €), sin contar el traspaso
a la cuenta de ahorro ni la retirada de la titular.

| Periodo | Puntos | Referencia (inicio del periodo) | Variación (texto exacto) |
|---|---|---|---|
| 1S | 7, diarios | 15 oct: 19.483,15 € | «−763,70 € · −3,9 %» |
| 1M (por defecto) | 30, diarios | 22 sep: 19.621,35 € | «−901,90 € · −4,6 %» |
| 3M | 14, cierre de cada domingo y hoy | 22 jul: 20.346,15 € | «−1.626,70 € · −8,0 %» |
| 1A | 53, cierre de cada domingo y hoy | 22 oct 2025: 18.602,60 € (estimado) | «+116,85 € · +0,6 %» |
| Todo | Igual que 1A en este ejemplo | — | — |

**Series (saldo al cierre del día, en euros):**

- **1S:** 16/10 19.483,15 · 17/10 19.664,65 · 18/10 19.664,65 · 19/10 19.664,65 · 20/10 18.719,45 · 21/10
  18.719,45 · 22/10 18.719,45
- **1M:** 23/09 19.621,35 · 24/09 19.621,35 · 25/09 19.621,35 · 26/09 19.621,35 · 27/09 19.621,35 · 28/09
  18.171,35 · 29/09 18.171,35 · 30/09 16.891,35 · 01/10 16.228,35 · 02/10 19.628,35 · 03/10 19.628,35 · 04/10
  19.628,35 · 05/10 19.483,15 · 06/10 19.483,15 · 07/10 19.483,15 · 08/10 19.483,15 · 09/10 19.483,15 · 10/10
  19.483,15 · 11/10 19.483,15 · 12/10 19.483,15 · 13/10 19.483,15 · 14/10 19.483,15 · 15/10 19.483,15 · 16/10
  19.483,15 · 17/10 19.664,65 · 18/10 19.664,65 · 19/10 19.664,65 · 20/10 18.719,45 · 21/10 18.719,45 · 22/10
  18.719,45
- **3M:** 26/07 20.346,15 · 02/08 21.153,15 · 09/08 21.007,95 · 16/08 18.929,30 · 23/08 18.929,30 · 30/08
  16.999,30 · 06/09 19.591,10 · 13/09 19.512,45 · 20/09 19.621,35 · 27/09 19.621,35 · 04/10 19.628,35 · 11/10
  19.483,15 · 18/10 19.664,65 · 22/10 18.719,45
- **1A** (hasta el 28/06 es **Estimado**: no hay extracto antes del 30 de junio de 2026): 26/10/25 18.602,60 ·
  02/11/25 19.409,60 · 09/11/25 19.264,40 · 16/11/25 19.185,75 · 23/11/25 19.185,75 · 30/11/25 17.255,75 ·
  07/12/25 19.847,55 · 14/12/25 19.768,90 · 21/12/25 18.318,90 · 28/12/25 16.868,90 · 04/01 19.125,90 · 11/01
  18.902,05 · 18/01 18.902,05 · 25/01 17.882,05 · 01/02 15.289,05 · 08/02 18.543,85 · 15/02 18.646,70 · 22/02
  18.646,70 · 01/03 16.053,70 · 08/03 19.308,50 · 15/03 19.229,85 · 22/03 19.411,35 · 29/03 17.961,35 · 05/04
  20.073,15 · 12/04 20.103,40 · 19/04 20.212,30 · 26/04 19.415,80 · 03/05 20.331,70 · 10/05 20.325,65 · 17/05
  20.434,55 · 24/05 20.543,45 · 31/05 18.722,35 · 07/06 21.531,95 · 14/06 21.562,20 · 21/06 20.221,10 · 28/06
  18.880,00 · **(desde aquí, extracto)** 05/07 20.991,80 · 12/07 21.094,65 · 19/07 21.094,65 · 26/07
  20.346,15 · 02/08 21.153,15 · 09/08 21.007,95 · 16/08 18.929,30 · 23/08 18.929,30 · 30/08 16.999,30 · 06/09
  19.591,10 · 13/09 19.512,45 · 20/09 19.621,35 · 27/09 19.621,35 · 04/10 19.628,35 · 11/10 19.483,15 · 18/10
  19.664,65 · 22/10 18.719,45

**Movimientos que explican los saltos** (para la etiqueta al recorrer la gráfica):

| Día | Movimiento | Importe |
|---|---|---|
| 28 sep | Nómina de septiembre | −1.450,00 € |
| 30 sep | Seguros sociales · Retirada de la titular | −480,00 € · −800,00 € |
| 1 oct | Alquiler de la oficina | −663,00 € |
| 2 oct | Remesa de cuotas de clientes | +3.400,00 € |
| 5 oct | Programa de contabilidad | −145,20 € |
| 17 oct | Transferencia de Talleres Martín e Hijos (cobro sin confirmar) | +181,50 € |
| 20 oct | Modelos 303 y 111 del 3T | −945,20 € |

**Textos de la gráfica:**
- Frase de cabecera (1M): «La caja baja 902 € este mes: el martes se pagaron los impuestos del trimestre.»
- **Puntero sobre el 20 oct (1M):** cifra «18.719,45 €», fecha «mar 20 oct», motivo «Modelos 303 y 111 del 3T ·
  −945,20 €».
- **Arrastre del 1 al 2 oct (1M):** «+3.400,00 € entre el 1 y el 2 oct · remesa de cuotas».
- **1A:** etiqueta «Estimado hasta el 30 jun» sobre el tramo estimado.
- Fuente al pie del módulo: «Sale del extracto de la cuenta corriente · último movimiento el 20 oct».

### 3.3 El embudo: 8 oportunidades en 5 etapas

| # | Tarjeta (título) | Persona | Servicio | Etapa | Valor | Prob. | Días | Siguiente paso | Responsable | Distintivo |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Estudio Creativo Lúcuma | Irene Lúcuma | Trimestrales | Prospecto | 600 € | 10 % | 3 d | «Ofrecer el diagnóstico · vie 23 oct» | Comercial (asistente) | «Llegó por Marca» |
| 2 | Frutas Ribera | Amparo Ribera | Trimestrales | Diagnóstico | 600 € | 30 % | 4 d | «Diagnóstico · vie 23 oct, 10:00» | Lucía | «Ficha previa lista» |
| 3 | Carlos Gil | Carlos Gil (particular) | Renta 2026 | Diagnóstico | 90 € | 30 % | **quieta 8 d** | «Proponer fecha de diagnóstico · hoy» | Lucía | En alerta |
| 4 | Javier Ortega | Javier Ortega (particular) | Renta 2026 | Propuesta | 90 € | 50 % | **quieta 7 d** | «Toque del día 7 · hoy» | Lucía | «Borrador listo» |
| 5 | Bar La Plaza | Lola Plaza | Trimestrales | Propuesta | 600 € | 50 % | 2 d | «Toque del día 7 · mar 27 oct» | Lucía | — |
| 6 | Arquitectura Nexo | Sergio Nexo | Trimestrales y consulta | Aceptada | 690 € | 90 % | 1 d | «Emitir la factura inicial · hoy» | Elena | «Factura en borrador» |
| 7 | Talleres Martín e Hijos | Jorge Martín | Trimestrales | Aceptada | 600 € | 90 % | 8 d (actividad hace 5) | «Confirmar el cobro · hoy» | Elena | «Cobro recibido el 17 oct, sin confirmar» |
| 8 | Andrés Vidal | Andrés Vidal (particular) | Renta 2026 | Ganada | 90 € | 100 % | 18 sep | — | Lucía | «Cobrado» |

«Quieta» quiere decir sin cambio de etapa ni actividad. Talleres Martín no cuenta como quieta porque el 17 oct
llegó su transferencia.

**Columnas** (título, número y suma):

| Columna | Tarjetas | Suma |
|---|---|---|
| Prospecto | 1 | 600 € |
| Diagnóstico | 2 | 690 € |
| Propuesta | 2 | 690 € |
| Aceptada | 2 | 1.290 € |
| Ganada (últimos 90 días) | 1 | 90 € |
| Plegadas al final | «Perdida · 1» (Nerea Blasco · Renta 2026 · motivo «La hará ella misma») · «Pausada · 0» | — |

**Indicadores encima del tablero:** «Valor abierto 3.270 €» · «Ponderado 1.773 €» · «Ganadas sobre cerradas
(90 días): 1 de 2».

### 3.4 Las tres decisiones (formato 1-3-1)

**Decisión 1 · «¿Confirmas el cobro de Talleres Martín?»**
- Grupo: Para aprobar · la prepara «Contable (asistente)» · 4 · Finanzas · desde el lun 19 oct.
- Problema: «El 17 oct llegó una transferencia de 181,50 € de TALLERES MARTIN E HIJOS SL. Coincide con la
  factura F-2026-0013 en importe, nombre y fecha.»
- Opciones:
  1. **«Confirmar el cobro»**: la factura pasa a Cobrada, la oportunidad a Ganada y nace su proyecto.
     **Recomendada:** «Coinciden importe, nombre y fecha.»
  2. «Confirmar el cobro y arrancar el proyecto el lunes 26».
  3. «No es este cobro: dejarlo sin conciliar y preguntar a Jorge Martín».
- Evidencias: «Movimiento del 17 oct» · «Factura F-2026-0013» · «Propuesta v1».
- Si lo pospones: «El proyecto no arranca: se empieza con el cobro confirmado (decisión del 19 oct).»

**Decisión 2 · «¿Envías el toque del día 7 a Javier Ortega?»**
- Grupo: Para aprobar · lo prepara «Comercial (asistente)» · 2 · Ventas · hoy.
- Problema: «Javier Ortega recibió la propuesta de Renta 2026 el 15 oct y no ha contestado. El mensaje del día
  7 está listo.»
- Borrador (detalle): «Hola, Javier: te escribo por la propuesta de la Renta 2026 que te envié el día 15. Si
  te encaja, te la dejamos lista antes de que empiece la campaña. ¿Te viene bien que te llame el lunes a las
  10:00?»
- Criterios: «Cumple 4 de 4: cita algo concreto · menos de 120 palabras · una sola pregunta al final · ningún
  precio fuera de la Oferta».
- Opciones:
  1. **«Enviar tal cual».** **Recomendada:** «Cumple los 4 criterios del sistema Embudo.»
  2. «Cambiar el texto y enviar».
  3. «No insistir: pasar a Perdida con motivo».
- Si lo pospones: «Sigue quieta; mañana serán 8 días.»

**Decisión 3 · «¿Dejas que el Comercial redacte los toques sin preguntarte?»**
- Grupo: Propuestas de mejora · la propone la app · sistema Embudo (VE2).
- Problema: «Has aprobado sin cambios los 5 últimos toques que redactó el Comercial.»
- Opciones:
  1. **«Subir un escalón: Lo hace y revisas»**: los redacta solo y te enseña el resumen; **enviar sigue siendo
     siempre con tu OK**. **Recomendada:** «5 de 5 aprobados sin cambios.»
  2. «Esperar a 10 seguidos».
  3. «Dejarlo como está».
- Si lo pospones: «No cambia nada.»

### 3.5 El foco del día

- Título: **«Emite la primera factura de Arquitectura Nexo»** · 4 · Finanzas · T-0041.
- Qué pasa: «Sergio Nexo aceptó ayer la propuesta (Trimestrales y una consulta). La factura de 290,40 € está en
  borrador.»
- Por qué importa: «El proyecto arranca cuando se confirma el cobro, y su primera sesión está prevista para el
  jueves 29.»
- Qué pasa si no: «El cobro llega más tarde y la sesión del 29 se mueve.»
- Recomendación: «Revísala y emítela hoy. El correo de envío queda preparado para tu OK.»
- Botón principal: **«Revisar y emitir»** (abre la pantalla 3, pestaña Factura). Secundarios: «Ver detalle» ·
  «Posponer» (avisa: «Si lo pospones a mañana, la sesión del 29 queda en el aire»).

### 3.6 El resto de Hoy

- Saludo: «Buenos días, Elena» · «Jueves, 22 de octubre».
- Frase del día: **«3 cosas piden tu decisión. Hoy tienes 2,5 h de 4.»**
- Alertas (solo existe porque hay algo en rojo): «2 · Ventas · 2 oportunidades quietas 7 días o más (alerta en
  1)» · «Ver».
- Línea de Mika: «Revisé a las 8:45: 1 cosa en rojo (Ventas).»
- Asistente trabajando: «Comercial (asistente) está preparando la ficha previa de Frutas Ribera.»

**Tu semana** (tope de 4 h al día):

| Día | Lun 19 | Mar 20 | Mié 21 | **Jue 22 (hoy)** | Vie 23 | Sáb 24 | Dom 25 |
|---|---|---|---|---|---|---|---|
| Horas | 3,5 | **4,5** | 3,0 | 2,5 | 3,0 | — | — |
| Aviso | — | «Pasa del tope» (icono y texto) | — | — | — | atenuado | atenuado |

**Lo que cabe hoy** (lo de Elena):

| Hora | Qué | Tipo | Área | Tiempo |
|---|---|---|---|---|
| 9:30 | «Revisar y emitir la factura de Arquitectura Nexo» · T-0041 | Tarea (el foco) | 4 · Finanzas | 0,5 h |
| 10:00 | «Revisión de la semana con Lucía» | Calendario | 1 · Dirección | 0,5 h |
| 11:00 | «Revisar el contrato de Arquitectura Nexo» · T-0040 | Tarea | 2 · Ventas | 0,4 h |
| 12:00 | «Cierre de semana» | Rutina | 1 · Dirección | 0,3 h |
| 16:00 | «Responder la duda de IVA de Clínica Dental Sonrisa» · T-0037 · «vence hoy» | Tarea | 3 · Entrega | 0,8 h |

### 3.7 Seguimientos (pantalla 2)

- **Hoy (2):**
  - «Javier Ortega · Renta 2026 · Toque del día 7» · «Borrador listo · cumple 4 de 4» · botón «Revisar y
    enviar» con la marca «Siempre con tu OK».
  - «Carlos Gil · Renta 2026 · Quieta 8 días: sin fecha de diagnóstico» · botón «Proponer dos horarios».
- **Próximos (2):**
  - «Amparo Ribera · Frutas Ribera · Diagnóstico · vie 23 oct, 10:00» · «Ficha previa lista».
  - «Lola Plaza · Bar La Plaza · Toque del día 7 · mar 27 oct».

---

## 4. Pantalla 1 · Hoy

**Orden fijo (no se mueve):** saludo y frase del día → foco → «Pide tu decisión» (las 3 de §3.4, con las
opciones 1·2·3 y la recomendada marcada) → Alertas → módulos (editables) → línea de Mika.

**Módulos por defecto** (rejilla de 4 columnas):

| Módulo | Tamaño | Contenido |
|---|---|---|
| Caja | Grande 2×2 | Cifra «18.719,45 €», variación del periodo, frase, gráfica interactiva (§3.2) con periodos y «Ver como tabla» |
| Ritmo por área | Grande 2×2 | Las 6 filas de §3.1 con icono, frase y ritmo |
| Tu semana | Ancho 4×1 | La tira de §3.6 con la barra de horas frente al tope |
| Lo que cabe hoy | Mediano 2×1 | Las 3 primeras filas de §3.6 y «Ver las 5» |
| Cobros por confirmar | Pequeño 1×1 | «1» · «181,50 € de Talleres Martín · llegó el 17 oct» |
| Oportunidades quietas | Pequeño 1×1 | «2» · «alerta en 1» con el ritmo «En alerta» |

**Galería de «+ Añadir»** (categorías por área): Próximas sesiones · Movimientos sin conciliar · Próximo
trimestre · Publicadas sobre planificadas · Salud de los asistentes · Valor del embudo · Facturas pendientes de
cobro.

**Estado «Editar inicio»:** todos los módulos con «−» y asa; «Lo que cabe hoy» levantado a medio arrastre; la
galería cerrada; arriba, «Listo».

**Estado vacío de ejemplo** (opcional, en un módulo añadido): «Movimientos sin conciliar» con «Sin dato: falta el
extracto de la cuenta de ahorro» · botón «Añadir extracto».

---

## 5. Pantalla 2 · Ventas

- **Barra lateral:** «2 · Ventas» seleccionada.
- **Cabecera del área:** «2 · Ventas» con su icono · «Convierte desconocidos en clientes» · «La lleva Lucía
  (Comercial) con el asistente Comercial» · «¿De dónde sale el próximo cliente?» · **cifra protagonista «2»**
  con «oportunidades quietas 7 días o más» · «Meta 0 · alerta en 1» · ritmo «En alerta» · botones «Pedir al
  Comercial» y «Ver como Comercial».
- **Pestañas:** Resumen · **Operación** (activa) · Control · Sistemas y activos. Dentro de Operación, el
  conmutador «CRM · Directorio · Propuestas · Servicios» con CRM activo y «Tablero | Lista» con Tablero activo.
- **Indicadores** y **tablero** de §3.3. Cada tarjeta enseña: título, persona (si es distinta), servicio,
  valor, días (o «quieta N d» con icono), siguiente paso con fecha, responsable (iniciales o «asistente») y el
  distintivo.
- **Seguimientos** de §3.7, al lado o debajo según la dirección.

**Estado de arrastre bloqueado:** la tarjeta «Arquitectura Nexo» (Aceptada) se arrastra sobre «Ganada». La
columna Ganada no la acepta y enseña:
- «Ganada necesita un cobro confirmado por una persona. La factura de Arquitectura Nexo aún está en borrador.»
- Botones: «Dejar en Aceptada» (principal) · «Abrir la factura».
- Alternativa sin arrastrar, visible en el menú contextual de la tarjeta: «Mover a… ›» con las etapas, y ⌘← ⌘→.
  Ganada aparece desactivada con el mismo motivo.

---

## 6. Pantalla 3 · Documento

**Disposición:** a la izquierda, el fichero en texto plano (lo que verías en cualquier editor, con «Ver como
texto»); a la derecha, el mismo fichero como pantalla de app. Arriba, tres pestañas: **Factura · Ficha de
sistema · Contacto**. Al pasar por un bloque de la derecha se resaltan sus líneas a la izquierda, y al revés.
Encima del texto se ve la ruta del fichero.

### 6.1 Factura

**Ruta:** `4 · Finanzas/Fiscal/Borradores/arquitectura-nexo-4t-2026.md`

```markdown
---
tls_type: invoice
tls_schema: 1
id: 5f3c9a12-8d4e-4b7a-a1c6-0e2d9b7f4a31
estado: Borrador
serie: F
empresa: "[[arquitectura-nexo|Arquitectura Nexo SLP]]"
oportunidad: "[[arquitectura-nexo-trimestrales|Arquitectura Nexo · Trimestrales]]"
creada: 2026-10-21
plazo_dias: 7
iva_pct: 21
base: 240.00
cuota_iva: 50.40
total: 290.40
forma_pago: transferencia
plantilla: Factura v1
---
# Factura a Arquitectura Nexo SLP
> Borrador · 290,40 € · se numera al emitir · vence 7 días después

## Conceptos
| Concepto | Cantidad | Precio | IVA | Importe |
|---|---|---|---|---|
| Trimestrales · 4T 2026 (modelos 303 y 111) | 1 | 150,00 € | 21 % | 150,00 € |
| Consulta fiscal · alta en operaciones intracomunitarias | 1,5 h | 60,00 € | 21 % | 90,00 € |

## Totales
| Base | IVA 21 % | Retención | Total |
|---|---|---|---|
| 240,00 € | 50,40 € | No aplica | **290,40 €** |

## Forma de pago
Transferencia a la cuenta de Asesoría Ribera terminada en 4821, en los 7 días siguientes a la emisión.
Los datos fiscales completos del emisor los pone la app en el PDF.

## Notas
Primera factura del encargo. El proyecto arranca cuando se confirma el cobro.
```

Notas para la maqueta:
- No lleva `numero`, `fecha` ni `vence`: los pone la app al emitir (la siguiente de la serie es F-2026-0014).
- La retención no aplica porque la emisora es una sociedad.
- Datos del cliente que la app toma de su ficha de empresa: «Arquitectura Nexo SLP · NIF B00000017 (ficticio) ·
  Calle Ejemplo 12, 46002 Valencia · administracion@arquitecturanexo.example».

**Lectura en la app:**

| Parte | Contenido |
|---|---|
| Cabecera (3 datos) | Estado «Borrador» (icono y palabra) · «Se numera al emitir» · «Creada el 21 oct» |
| **Protagonista** | **«290,40 €»** |
| Secundarios (4) | Para: «Arquitectura Nexo SLP» · Vence: «7 días tras emitir (si la emites hoy, el 29 oct)» · Oportunidad: «Arquitectura Nexo · Trimestrales» · Forma de pago: «Transferencia · cuenta terminada en 4821» |
| Auxiliares (4) | «Base 240,00 €» · «IVA 50,40 €» · «Retención: no aplica» · «Plantilla Factura v1» |
| Bloques | Conceptos (2 filas) · Totales (fila Total destacada) · Forma de pago · Notas · Propiedades (plegado) |
| Línea de estados | Borrador (actual) → Emitida → Enviada → Cobrada |
| Barra fija | **«Revisar y emitir»** (principal) · «Vista previa PDF» · «Ver como texto» |

**Estados opcionales:**
- **Hoja de confirmación al pulsar «Revisar y emitir»:** «Vas a emitir la factura F-2026-0014 a Arquitectura
  Nexo SLP por 290,40 €. Fecha: 22 oct 2026 · vence el 29 oct. Una factura emitida no se cambia: si hay un
  error, se corrige con una rectificativa.» Botones «Emitir» y «Cancelar».
- **Con un dato que falta:** en el texto, la línea de forma de pago dice `[falta: empresa.cp]` en lugar del
  código postal; en la app, pastilla «Falta: código postal del cliente», el botón principal desactivado con el
  motivo y un botón «Pedir el dato» (prepara un correo que apruebas tú).

### 6.2 Ficha de sistema

**Ruta:** `4 · Finanzas/Sistemas/Facturación y cobros.md`

```markdown
---
tls_type: system
tls_schema: 1
id: 9a4d2e71-3c5b-4f8a-b1e6-7d0c2f9a5b34
codigo: FI1
area: finanzas
estado: montado
etapa: 1
rol: "[[financiero|Financiero]]"
numero_clave: FIN-AR
revisar_cada: mensual
revisado: 2026-10-05
plantilla: Ficha de sistema v2
---
# Facturación y cobros
> 4 · Finanzas · Montado · Lo lleva Elena con el asistente Contable · Número: cobrado en plazo

## Para qué
Que cada encargo tenga su factura a tiempo y que un cobro solo cuente cuando se ve en el banco.

## Cuándo se usa
Empieza cuando una oportunidad pasa a Aceptada, cuando se termina un encargo o cuando vence una factura.
Termina cuando la factura está Cobrada y tiene su recibo.

## Recibe de y entrega a
| Recibe | De | Entrega | A |
|---|---|---|---|
| Propuesta aceptada con su precio | Embudo (Ventas) | Factura en borrador | Elena, para revisarla |
| Datos fiscales del cliente | Ficha de la empresa | Factura emitida, PDF y fila en emitidas.csv | Cliente y gestoría |
| Cobro visto en el banco | Tesorería | Factura Cobrada y recibo | Arranque del cliente (Entrega) |

## Pasos
| # | Paso | Quién | Modo | Deja hecho |
|---|---|---|---|---|
| 1 | Completar los datos fiscales del cliente | Contable (asistente) | Lo hace y revisas | Datos completos o «falta» marcado |
| 2 | Preparar la factura desde la propuesta | Contable (asistente) | Te ayuda | Factura en borrador |
| 3 | Revisar y emitir | Elena | Siempre con tu OK | Número, fecha, PDF y fila en emitidas.csv |
| 4 | Enviarla al cliente | Elena | Siempre con tu OK | Correo enviado |
| 5 | Confirmar el cobro con el extracto | Elena | Lo haces tú | Factura Cobrada y recibo |
| 6 | Si vence, preparar el recordatorio | Contable (asistente) | Te ayuda | Recordatorio en borrador y decisión |

## Quién lo hace
Lo lleva Elena (rol Financiero). El asistente Contable prepara; Elena emite, envía y confirma.

## Qué deja hecho
Cada factura con número, PDF, fila en emitidas.csv y estado al día; cada cobro con su recibo y su movimiento.

## Criterios de calidad
- El precio sale de la Oferta, nunca se teclea
- Ningún dato fiscal inventado: lo que falta se marca
- Los totales cuadran al céntimo
- La factura sale como mucho un día laborable después de Aceptada

## Lo que nunca hace
- Emitir o enviar sin tu OK · dar algo por cobrado sin el banco · cambiar una factura emitida (se rectifica)

## Plantillas y activos
- Plantillas: [Factura](Plantillas/Factura.md) · [Factura rectificativa](Plantillas/Factura%20rectificativa.md) · [Recibo de cobro](Plantillas/Recibo%20de%20cobro.md) · [Recordatorio de cobro](Plantillas/Recordatorio%20de%20cobro.md)
- Activos: [Condiciones de cobro](../Activos/condiciones-de-cobro.md)

## Procedimientos
Ninguno por ahora.

## Ejemplos buenos
- [Factura F-2026-0013 · Talleres Martín e Hijos](../Fiscal/2026/T4/Ingresos/talleres-martin-4t-2026.md)

## Cómo sabemos que va bien
Cobrado en plazo (FIN-AR). Meta y alerta en [Metas](../../1%20·%20Dirección/Metas.md).

## Rutina
Día 5 de cada mes: «¿Qué está sin cobrar y qué margen dejó lo cobrado?»

## Aprendido
- 2026-09-21 · Las consultas por horas se facturan junto a la cuota del trimestre, no aparte · tras 3 correcciones iguales · aprobado por Elena

## Origen
Escrito el 2026-07-03, tras hacerlo 3 veces a mano.
```

**Lectura en la app:**

| Parte | Contenido |
|---|---|
| Cabecera | «Facturación y cobros» · área «4 · Finanzas» · estado «Montado» (icono y palabra) · «Para qué» en una línea |
| **Protagonista** | Número clave FIN-AR: **«100 %»** · «3 de 3 facturas de encargo cobradas a tiempo desde julio» · «Meta: todas · alerta con 1 vencida» · ritmo «En ritmo» |
| Minigráfica (recorrible) | Días hasta el cobro de cada factura, con una línea en el plazo de 7 días: F-2026-0004 (Panadería Horno Sol) 5 días · F-2026-0005 (Clínica Dental Sonrisa) 7 días · F-2026-0006 (Andrés Vidal) 4 días · F-2026-0013 (Talleres Martín) 3 días, marcada «falta confirmarlo». Al pasar: «F-2026-0006 · Andrés Vidal · cobrada en 4 días». Las cuotas mensuales de la cartera se cobran por remesa y no entran aquí |
| Secundarios | «Lo lleva Elena con el asistente Contable» · «Revisado hace 17 días» · «Etapa 1» · «Código FI1» |
| Recibe de y entrega a | Diagrama sencillo: Embudo → **Facturación y cobros** → Arranque del cliente; Tesorería → Facturación y cobros |
| Pasos | 6 filas: número, verbo, quién (iniciales «E» o «Contable (asistente)»), modo en palabras; candado y «Siempre con tu OK» en los pasos 3 y 4 |
| Cómo va (calculado) | Uso «4 veces este mes» · Bien a la primera «3 de 4 sin cambios» · Tiempo «Te ahorra unas 2 h al mes (estimado)» · Frescura «Revisado hace 17 días» · Sin ti «1 de 6 pasos sin ti» |
| Resto de bloques | Criterios de calidad (4, con marca) · Lo que nunca hace · Plantillas y activos (chips) · Ejemplos buenos (miniatura) · Rutina · Aprendido (línea de tiempo) · Origen |
| Barra fija | **«Probar con un caso»** (principal) · «Revisar ahora» · «Pedir mejora al Contable» · «Ver como texto» |

### 6.3 Contacto

**Ruta:** `2 · Ventas/Contactos/sergio-nexo.md`

```markdown
---
tls_type: contact
tls_schema: 1
id: 2c8e6f40-1a9b-4d3e-b7c5-9f0a4e2d1b86
nombre: Sergio Nexo
aliases: [Sergio]
empresa: "[[arquitectura-nexo|Arquitectura Nexo SLP]]"
cargo: Socio director
email: sergio@arquitecturanexo.example
relacion: [cliente]
origen: recomendación
referido_por: "[[jorge-martin|Jorge Martín]]"
verificacion: verificado
creada: 2026-10-12
plantilla: Contacto v1
---
# Sergio Nexo
> Cliente · Arquitectura Nexo SLP · aceptó la propuesta el 21 oct

Empresa: [Arquitectura Nexo SLP](../Empresas/arquitectura-nexo.md)

## Cómo llegó
Le recomendó Jorge Martín (Talleres Martín e Hijos) el lunes 12 de octubre. Quiere olvidarse de los trimestres y empezar a vender a Francia.

## Notas
- 2026-10-14 · Diagnóstico. Frase destino: «Quiero que el día 20 sea un día normal».
- 2026-10-21 · Acepta Trimestrales y una consulta para el alta intracomunitaria.
- Prefiere el correo a las llamadas, mejor por la mañana.

Fuente: diagnóstico del 14 oct y correo del 21 oct · 2026-10-21
```

**Lectura en la app:**

| Parte | Contenido |
|---|---|
| Cabecera (3 datos) | «Cliente» · «Verificado» · «Socio director en Arquitectura Nexo SLP» |
| **Protagonista** | Las iniciales **«SN»** en grande (en el relleno de Ventas) y el nombre «Sergio Nexo» |
| Secundarios (4) | Último contacto: «21 oct · correo: acepta la propuesta» · Siguiente paso: «Primera sesión el jue 29 oct, cuando se confirme el cobro» · Recomendado por: «Jorge Martín» · Correo: «sergio@arquitecturanexo.example» |
| Auxiliares | «Origen: recomendación» · «Alta el 12 oct» · «Otros nombres: Sergio» · fila vacía «Añadir teléfono» (sin dato inventado) |
| Bloques | Cómo llegó · Notas (la frase destino destacada como cita) |
| Lo de esta persona (vistas) | Oportunidades (1): «Arquitectura Nexo · Trimestrales · Aceptada · 690 €» · Reuniones (1): «14 oct · Diagnóstico · 60 min» · Facturas (1): «Borrador · 290,40 €» · Tareas (1): «T-0041 Revisar y emitir la factura» · Enlazan aquí (3) |
| Barra fija | **«Escribir un correo»** (principal; prepara un borrador, nunca envía solo) · «Nueva reunión» · «Ver como texto» |

---

## 7. Lista de comprobación por maqueta

**Hoy**
- [ ] Claro y oscuro.
- [ ] Barra lateral en estado normal (§2.1) y en estado de edición (§2.2), con el aviso «Ocultaste 6 · Equipo ·
  Deshacer».
- [ ] Menú contextual de «Directorio» (§2.3).
- [ ] Foco, 3 decisiones con su recomendada, alerta y línea de Mika.
- [ ] Caja en 1M; puntero sobre el 20 oct; arrastre del 1 al 2 oct; 1A con el tramo «Estimado»; «Ver como
  tabla».
- [ ] «Editar inicio» con «−», asas y un módulo a medio arrastre.

**Ventas**
- [ ] Cabecera del área con la cifra «2» y su ritmo.
- [ ] Tablero con las 5 columnas, sus sumas y las plegadas.
- [ ] Arrastre bloqueado sobre Ganada, con el aviso y sus dos botones.
- [ ] Seguimientos de hoy y próximos.

**Documento**
- [ ] Las tres pestañas, cada una con el texto a la izquierda y la pantalla a la derecha.
- [ ] Resaltado de las líneas de un bloque al pasar por él.
- [ ] Barra fija con su acción principal en cada pestaña.
- [ ] (Opcional) Hoja de confirmación de «Revisar y emitir» y estado con «falta».

**Accesibilidad**
- [ ] Foco de teclado visible en un elemento de cada pantalla.
- [ ] (Opcional) Una captura con el texto al 200 % y otra con «Reducir movimiento».

---

## 8. Lo que el trabajo de plantillas debe alinear con la demo de Ribera

| Qué | En la demo de Ribera | En este guion | Propuesta |
|---|---|---|---|
| Servicio «Consulta fiscal» (60 €/h) | No existe | Segunda línea de la factura | Añadir `2 · Ventas/Productos/consulta-fiscal.md` con su versión, o quitar la línea |
| Personas | Sin nombres | Elena Sanchis (titular) y Lucía Andreu (empleada) | Añadirlas como ocupantes de los roles |
| Oportunidades | 14, con otros estados | 8, con los estados de §3.3 | Ajustar estados y fechas, o crear una variante de la demo |
| Movimientos del 20 oct | El extracto acaba el 17 oct | Modelos 303 y 111 del 3T (−655,20 € y −290,00 €) | Añadirlos al extracto |
| Tramo de caja anterior al 30 jun | No hay extracto | Serie «Estimado» | Generarla a partir de facturas, o dejar 1A solo con el tramo real |
| Facturas | F-2026-0004 a 0006 | F-2026-0004 (emitida el 7 jul), 0005 (13 jul), 0006 (14 sep), 0013 (Talleres, 14 oct) y la siguiente, F-2026-0014 | Ajustar las fechas de emisión y crear F-2026-0013 en `Fiscal/2026/T4/Ingresos/` |
| Claves de la factura | `cliente_id`, `payment_terms_days`, importes en céntimos | `empresa` (enlace), `plazo_dias`, euros con punto | Las del diccionario de `SISTEMAS.md` §1.5; las de la demo se leen como alias |
| Ficha de sistema FI1 | Ribera no tiene sistemas escritos | Ficha completa en §6.2 | Usarla como ejemplo de la plantilla «Ficha de sistema v2» |
| Empresa Arquitectura Nexo | `arquitectura-nexo-slp--dbc2c351.md` | NIF ficticio B00000017 y domicilio genérico | Completar la ficha de empresa con datos de facturación ficticios |

---

### 8.1 Datos para la profundidad (maquetas M2)

Lo que usan `M2-Hoy`, `M2-Bases`, `M2-Contacto` y `M2-Proyecto` para recorrer Hoy › Decisión › Ventas › Contactos ›
Jorge Martín › Proyectos › Trimestrales 2026 › T-0042 (`DISENO-MOSAICO-V2.md` §2.6 y §9). Todo es ficticio.

**Nombres y ficheros únicos de Talleres Martín** (los mismos en las cuatro maquetas):

| Ficha | Fichero | Nombre que se ve |
|---|---|---|
| Empresa | `2 · Ventas/Empresas/talleres-martin-e-hijos.md` | Talleres Martín e Hijos SL (corto: «Talleres Martín») |
| Contacto | `2 · Ventas/Contactos/jorge-martin.md` | Jorge Martín · Gerente |
| Oportunidad | `2 · Ventas/Oportunidades/talleres-martin-trimestrales.md` | Talleres Martín · Trimestrales |
| Reunión | `…/talleres-martin-trimestrales/Reuniones/2026-10-09-descubrimiento-trimestrales.md` | Descubrimiento · Trimestrales · Talleres Martín |
| Factura | `4 · Finanzas/Fiscal/2026/T4/Ingresos/talleres-martin-4t-2026.md` | F-2026-0013 · 181,50 € |
| Proyecto | `3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md` | Trimestrales 2026 |

Las oportunidades se titulan «Empresa · Servicio» (o «Persona · Servicio» si es un particular): «Arquitectura Nexo ·
Trimestrales», «Carlos Gil · Renta 2026». `responsable` se escribe con su identificador estable: `elena`, `lucia`,
`agente:comercial`, `agente:implementador`.

**La recomendación.** Jorge Martín llama a Ribera el 7 de octubre (`PLANTILLAS.md` §7) y recomienda a Sergio Nexo el
**lunes 12 de octubre**; el diagnóstico con Sergio es el 14 y acepta el 21.

**Proyecto «Trimestrales 2026» (Talleres Martín).** Nace al confirmar el cobro de F-2026-0013 con la opción
recomendada: **En curso**, con su plan creado y responsable Lucía (`responsable: lucia`). Con la opción 2 nace **Sin
empezar** y arranca el lunes 26 de octubre. Plan Trimestrales del 4T de 2026, en cuatro fases:

| Fase | Fechas | Qué |
|---|---|---|
| Recogida | 22–26 oct | Documentación de 1T–3T y accesos (T-0042) |
| Contabilidad | 27 oct – 31 dic | Al día cada mes: las facturas de un mes, antes del día 5 del siguiente |
| Modelos 4T | 4–15 ene 2027 | Borradores del 303 y el 111 del cuarto trimestre, revisados |
| Presentación | 18–30 ene 2027 | El 111 hasta el 20 de enero y el 303 hasta el 30 |

| Tarea | Título | Fase | Responsable | Planificada | Vence | Estado el 22 oct |
|---|---|---|---|---|---|---|
| T-0042 | Pedir la documentación de 1T–3T y los accesos | Recogida | Implementador (asistente) | 22 oct | 26 oct | En revisión: el correo a Jorge espera tu OK |
| T-0043 | Contabilizar cada mes y clasificar los gastos | Contabilidad | Implementador (asistente) | 2 nov | 31 dic | Por hacer |
| T-0044 | Conciliar los bancos y listar las diferencias | Contabilidad | Implementador (asistente) | 28 dic | 31 dic | Por hacer |
| T-0045 | Preparar los borradores del 303 y el 111 del 4T | Modelos 4T | Lucía | 4 ene 2027 | 12 ene 2027 | Por hacer · revisión obligatoria |
| T-0046 | Validación del cliente y aviso del cargo | Modelos 4T | Lucía | 13 ene 2027 | 15 ene 2027 | Por hacer |
| T-0047 | Presentar el 111 y el 303 y archivar justificantes | Presentación | Lucía | 18 ene 2027 | 20 ene 2027 | Por hacer · solo con certificado |

- **Tarea suelta de Talleres:** T-0038 «Pedir a Jorge las facturas de proveedores en papel» (Lucía, creada el 14 oct,
  sin proyecto). Es la que «Añadir existente…» ofrece primero.
- **Resultado prometido:** «Que en enero no me tenga que acordar de nada» (frase destino del descubrimiento del 9 oct).
- **Terminado cuando:** 111 presentado antes del 20 de enero y 303 antes del 30, justificantes archivados y resumen
  enviado al cliente.
- **Cobrado:** 150 € de 600 € del primer año (25 %), sin IVA: F-2026-0013 (150,00 € + IVA 31,50 € = 181,50 €),
  transferencia del 17 oct, cobro confirmado el 22 oct por Elena, con su **recibo** en Materiales.

**Proyecto de Clínica Dental Sonrisa.** «Trimestrales 2026», en curso, fase Contabilidad, 2 de 6 tareas hechas,
F-2026-0005 cobrada, responsable Lucía; T-0037 «Responder la duda de IVA» vence hoy.

**Base Contactos (9 fichas, 8 sin archivar):**

| Contacto | Empresa | Estado | Último contacto | Siguiente paso |
|---|---|---|---|---|
| Jorge Martín | Talleres Martín e Hijos SL | Activo | 17 oct · transferencia de 181,50 € | Confirmar el cobro · hoy |
| Javier Ortega | Particular | Interesado | 15 oct · recibe la propuesta | Toque del día 7 · hoy (quieta 7 días) |
| Carlos Gil | Particular | Interesado | 14 oct · pasa a Diagnóstico | Proponer fecha de diagnóstico · hoy (quieta 8 días) |
| Sergio Nexo | Arquitectura Nexo SLP | Activo | 21 oct · acepta la propuesta | Emitir la factura inicial · hoy |
| Amparo Ribera | Frutas Ribera | Interesado | 18 oct · pasa a Diagnóstico | Diagnóstico · vie 23 oct, 10:00 |
| Irene Lúcuma | Estudio Creativo Lúcuma | Interesado | 19 oct · llegó por Marca | Ofrecer el diagnóstico · vie 23 oct |
| Lola Plaza | Bar La Plaza | Interesado | 20 oct · recibe la propuesta | Toque del día 7 · mar 27 oct |
| Andrés Vidal | Particular | Activo | 18 sep · Renta cobrada | — |
| Nerea Blasco | Particular | Archivado | — | — (oportunidad Perdida) |

**Base Facturas (5 fichas).** El plazo de pago es de 7 días tras emitir.

| Número | Empresa | Fecha | Vence | Total | Estado | Cobrado |
|---|---|---|---|---|---|---|
| (se numera al emitir) | Arquitectura Nexo SLP | 21 oct | — | 290,40 € | Borrador | — |
| F-2026-0013 | Talleres Martín e Hijos SL | 14 oct | 21 oct | 181,50 € | Enviada | Llegó el 17 oct, sin confirmar |
| F-2026-0006 | Andrés Vidal (particular) | 14 sep | 21 sep | 108,90 € (Renta 90 € + IVA) | Cobrada | En 4 días |
| F-2026-0005 | Clínica Dental Sonrisa | 13 jul | 20 jul | 181,50 € | Cobrada | En 7 días |
| F-2026-0004 | Panadería Horno Sol | 7 jul | 14 jul | 181,50 € | Cobrada | En 5 días |

**La barra lateral** de las cuatro maquetas añade la sección Bases de `DISENO-MOSAICO-V2.md` §4.1 entre Áreas y
Asistentes, con las fichas abiertas a la derecha: Contactos 8 · Empresas 7 · Oportunidades «7 abiertas» · Proyectos
«1 en curso» · Reuniones «1 prevista» · Facturas «2 abiertas» · Todas las bases ⇧⌘B. Recientes: «Jorge Martín»
(contacto) · «Factura · Arquitectura Nexo» (borrador) · «Facturación y cobros» (sistema).

## Procedencia

- Datos: demo ficticia de Asesoría Ribera (empresa, servicios, precios, oportunidades, extracto de julio a
  octubre de 2026 y decisiones del 19 oct), ampliada como dice §8.
- Estructura, estados, eventos, números clave y regla de Ganada: `SISTEMAS.md` §1–§5.
- Patrones de pantalla (foco, decisiones 1-3-1, Hoy, CRM, documento como pantalla): `PLAN.md` §6 e informe de
  referencias de apps de consumo.
- La cadencia de toques a los 7, 14, 21 y 30 días y el formato 1-3-1 son ideas de Blash, reformuladas (ya
  recogidas en `SISTEMAS.md`). No hay texto de Blash en este guion.
