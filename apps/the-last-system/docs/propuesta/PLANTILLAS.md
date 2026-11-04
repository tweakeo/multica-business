# Plantillas de The Last System (propuesta v2)

> **Qué es esto.** El catálogo completo de plantillas de la app: qué fichas y documentos se crean, con qué
> propiedades y secciones, qué variables rellena la app, qué sistema los usa y qué PDF sale. Incluye cómo se
> consigue el logo (aportarlo, traerlo de tu web o generarlo) y qué lleva el kit de marca.
>
> **Estado:** propuesta para aprobar · 22/10/2026 · no cambia nada en tu carpeta.
>
> **Base:** SISTEMAS.md (los 19 sistemas, el diccionario de propiedades y su Anexo B), PLAN.md (§4 y §6), la demo
> de Asesoría Ribera, la estructura y la forma de calcular de las plantillas de `tlb/`, el método Kepano y los
> dos vídeos de referencia, ya con su transcripción (lo que aportan está en SISTEMAS.md §9).
> De Blash solo se usan ideas, reescritas y marcadas «idea de Blash, reformulada».
> No hay datos de clientes reales: los ejemplos son de Asesoría Ribera, una empresa ficticia.
>
> **Los ficheros:** las 90 plantillas están en `docs/propuesta/plantillas/`, con una carpeta por área y otra
> `Comunes/`. Los 4 ejemplos rellenos y una variante de ejemplo están en `plantillas/EJEMPLOS/`.

---

## 0. En una página

1. **90 plantillas para los 19 sistemas.** 16 son comunes y el resto va por áreas: Dirección 13, Ventas 15,
   Entrega 17, Finanzas 10, Marca 13 y Equipo 6. Cubren el Anexo B de SISTEMAS.md y lo que faltaba:
   - factura y factura rectificativa, propuesta, presupuesto, contrato y recibo;
   - los ocho tipos de contenido y el calendario editorial;
   - el kit de logo y el manual de marca.
2. **Cada plantilla es un `.md` que se lee bien en cualquier editor.** Lleva propiedades arriba, un título, una
   línea de resumen y secciones fijas, sin HTML ni emojis. Las instrucciones son citas que empiezan por «Guía:»
   y la app las retira cuando ya no hacen falta.
3. **En la app, la misma nota se ve como una pantalla.** Las propiedades forman la cabecera, con una cifra
   protagonista; cada sección es un bloque, y abajo hay una barra con la acción principal (§1.7).
4. **Las variables van con doble llave**, como en Obsidian: `{{fecha}}`, `{{empresa.nombre}}`, `{{total:€}}`.
   Lo que falta nunca se inventa: se escribe `[falta: empresa.nif]`.
5. **Las relaciones son enlaces legibles** dentro de las propiedades:
   `empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"` (decisión 1 de SISTEMAS.md). Si renombras
   la empresa, la app cambia el enlace en todas partes.
6. **En los documentos con dinero**, la tabla de conceptos es la fuente y el precio sale de la oferta: nunca se
   teclea. El cálculo es exacto al céntimo, y emitir o enviar siempre pide tu OK (§3).
7. **Los PDF salen con tu marca y sin internet:** el logo, los colores y las tipografías salen del manual de
   marca. Mientras quede un `[falta: …]`, el PDF lleva la marca «BORRADOR» (§1.8).
8. **El logo se consigue por tres caminos:** lo aportas, lo traemos de tu web con tu permiso o la app lo genera
   con tu nombre y tu color. La IA de imagen queda fuera de la v1 salvo que digas lo contrario. Siempre termina
   en un kit con 9 variantes que usan todos los documentos (§5 y §6).
9. **Los datos fiscales y la cuenta del banco del emisor no van en ninguna nota.** La app los pone en el PDF y
   en el correo cuando lo envías.
10. **Hay cuatro ejemplos rellenos** de Asesoría Ribera que cuentan una sola historia, una venta que acaba en
    factura, y sirven para las maquetas de las seis direcciones de diseño (§7). Los acompaña una variante de
    ejemplo: la reunión de descubrimiento del servicio Trimestrales.
11. **Te hago 8 preguntas, cada una con propuesta** (§9). Ninguna bloquea F1.
12. **Con lo que aportan los vídeos** (SISTEMAS.md §9):
    - la ficha de sistema se amplía con Entradas, Salida esperada y criterio de «bien hecho», Herramientas y
      conexiones y Referencias y ejemplos, unificadas con las secciones que ya tenía;
    - el servicio lleva tipo, estado (En pruebas, Activo o Retirado), modelo y rango de precio, fases y sus
      clientes y proyectos;
    - hay reunión de descubrimiento con preguntas guía y una variante por servicio, reunión de seguimiento y
      una propuesta que el asistente genera desde la reunión;
    - contacto y empresa son la ficha de cliente: la app enseña sola todo lo relacionado y la plantilla lo dice.

---

## 1. Reglas comunes

### 1.1 Dónde viven

| Dónde | Qué hay | Quién lo cambia |
|---|---|---|
| Dentro de la app (biblioteca) | Las 90 originales, intactas: las de `docs/propuesta/plantillas/` | Solo una versión nueva de la app |
| `N · Área/Sistemas/Plantillas/` de cada empresa | La copia que usa cada sistema. Se copia al instalar el sistema | Tú, como cualquier otra nota |
| `1 · Dirección/Sistemas/Plantillas/` | Las comunes y las del Buzón | Tú |
| `.tls/plantillas.yaml` | Qué crea cada plantilla, dónde, con qué nombre y qué pregunta al crear | La app; tú, desde Ajustes |

- Es la decisión 4 de SISTEMAS.md, opción A.
- La app no enseña las notas de `Plantillas/` en sus vistas ni las cuenta como fichas.
- Para Obsidian, la app apunta su complemento de plantillas a `1 · Dirección/Sistemas/Plantillas/`. Las de las
  áreas se usan desde la app.

Así se describe una plantilla en `.tls/plantillas.yaml`:

```yaml
factura:
  fichero: "4 · Finanzas/Sistemas/Plantillas/Factura.md"
  tipo: invoice
  carpeta: "{finanzas}/Fiscal/Borradores"
  nombre: "{{empresa.slug}}-{{fecha}}"
  preguntas: [oportunidad, hito]
  modulo: facturas-y-cobros
tarea:
  fichero: "1 · Dirección/Sistemas/Plantillas/Tarea.md"
  tipo: task
  carpeta: "{area}/Tareas"            # o la del proyecto, si se crea desde él
  nombre: "t-{{numero}}-{{slug}}"
  preguntas: [titulo, responsable]
  modulo: tareas
contacto:
  fichero: "2 · Ventas/Sistemas/Plantillas/Contacto.md"
  tipo: contact
  carpeta: "{ventas}/Contactos"
  nombre: "{{slug}}"
  preguntas: [titulo, empresa, email]
  modulo: directorio
reunion-descubrimiento:
  fichero: "2 · Ventas/Sistemas/Plantillas/Reunión de descubrimiento.md"
  tipo: meeting
  carpeta: "{ventas}/Oportunidades/{{oportunidad.slug}}/Reuniones"
  nombre: "{{fecha}}-descubrimiento-{{servicio.slug}}"
  titulo: "Descubrimiento · {{servicio.nombre}} · {{empresa.nombre}}"
  variante_por: servicio              # usa la variante que el servicio enlaza en `descubrimiento`, si la tiene
  desde: [organization, contact, opportunity, service]
  preguntas: [servicio, fecha, hora]
  modulo: crm
```

- `nombre` y `titulo` son los **nombres estándar**: el del fichero y el que se ve. Los pone la plantilla y
  nadie los escribe al crear (SISTEMAS.md §1.7).
- `desde` dice en qué fichas aparece su botón «Nueva…». Así, la ficha de cliente tiene «Nueva reunión»,
  «Nueva propuesta», «Nuevo proyecto» y «Nueva factura», que crean la nota ya enlazada (SISTEMAS.md §4.4).
- `variante_por: servicio` hace que se use la variante del servicio si existe y, si no, la general.

### 1.2 Cómo está hecha una plantilla

1. **Propiedades.** Primero `tls_type`, `tls_schema: 1` e `id: "{{id}}"`; después, las obligatorias y las
   opcionales. La última es `plantilla: "<Nombre> vN"`.
   - Las plantillas enseñan todas las claves para que se vea qué existe. **Al crear la nota, la app no escribe
     las que quedan vacías** (SISTEMAS.md §1.5).
   - Los comentarios `# …` explican las opciones y no se copian a la nota.
2. **Título y resumen.** Un `# Título` y, debajo, una línea `> …` con lo esencial separado por « · ».
   - La línea de resumen la escribe la app a partir de las propiedades. Si el dato de un tramo está vacío, el
     tramo desaparece entero, con su separador.
   - Si la cambias tú, la app no la toca, pero te avisa si deja de coincidir con las propiedades. Manda la
     propiedad.
3. **Secciones `##` fijas,** siempre en el mismo orden. La app encuentra cada sección por su nombre.
4. **Guías.** Las líneas `> Guía: …` explican qué va en cada sección.
   - Se copian a la nota al crearla.
   - La app quita la guía de una sección cuando escribes en ella, o todas a la vez con «Quitar guías». Es un
     solo cambio y se puede deshacer.
   - Nunca toca una guía que hayas editado.
   - Se pueden apagar en Ajustes › Plantillas › «Copiar guías al crear».
5. **Tablas de 6 columnas como mucho.** La única excepción es `Incidencias.md`, que conserva las 10 columnas de
   G3 porque el portal ya la lee así.
6. **Casillas `- [ ]`.** Solo son tareas en `Tareas/` y en «Tareas del cliente» del portal. En cualquier otro
   sitio son pasos de esa nota.
7. **Sin HTML y sin emojis.** La única excepción son los comentarios `<!-- tls:… -->` que escribe la app en la
   Actividad de las tareas y en `Decisiones.md` (PLAN §4.2 y §4.4). Nunca están en las plantillas.
8. **Los marcadores `<nombre>` de las guías van entre comillas invertidas,** para que Obsidian no los tome por HTML.

### 1.3 Variables

Se escriben `{{así}}` y la app las sustituye al crear la nota. Si una variable no tiene valor:
- en una propiedad, la clave no se escribe;
- en el texto, se escribe `[falta: nombre.de.la.variable]`. Se ve en cualquier editor; la app lo marca con la
  palabra «Falta» y nunca lo inventa.

| Variable | Qué pone | Ejemplo |
|---|---|---|
| `{{id}}` | Identificador único | `404f898c-…` |
| `{{numero}}` | El siguiente número de su serie | `T-0031` |
| `{{orden}}` | El número de orden entre las fichas de ese tipo del mismo cliente | `2`, en «Seguimiento 2 · Talleres Martín» |
| `{{titulo}}` y `{{slug}}` | Lo que escribes al crear, y su forma para el nombre del fichero | `talleres-martin-e-hijos` |
| `{{fecha}}` y `{{hora}}` | Hoy y ahora | `2026-10-15`, `09:05` |
| `{{fecha+14}}` y `{{fecha+5l}}` | Hoy más 14 días naturales, o más 5 laborables | `2026-10-29` |
| `{{semana}}`, `{{mes}}`, `{{trimestre}}`, `{{año}}` | El periodo actual | `2026-S42`, `T4 2026` |
| `{{area}}` y `{{area.nombre}}` | El área donde se crea | `finanzas`, `4 · Finanzas` |
| `{{yo}}` y `{{yo.nombre}}` | Quién crea la nota | `Elena Castell` |
| `{{responsable}}` y `{{asistente}}` | La persona o el asistente asignado | `agente:contable` |
| `{{mi_empresa.*}}` | Tu empresa, de `Empresa.md` | `{{mi_empresa.nombre}}` |
| `{{empresa.*}}` y `{{contacto.*}}` | La empresa o la persona relacionada | `{{empresa.nif}}` |
| `{{oportunidad.*}}`, `{{proyecto.*}}`, `{{servicio.*}}`, `{{oferta.*}}`, `{{factura.*}}`, `{{reunion.*}}`, `{{sistema.*}}`, `{{rol.*}}` | Cualquier propiedad de la ficha relacionada | `{{oferta.precio}}` |
| `{{marca.logo}}` y `{{marca.color}}` | Del manual de marca | enlace al kit de logo |
| `{{x.enlace}}` | Un enlace a esa ficha. En propiedades, `"[[slug\|Nombre]]"`; en el texto, `[Nombre](ruta relativa)`, el estilo de G3 | |
| `{{cursor}}` | Dónde queda el cursor | |

**Formatos.** Se ponen con dos puntos, como el `{{date:…}}` de Obsidian. No se usa la barra `|` porque rompe
las tablas.

| Formato | Resultado |
|---|---|
| `{{total:€}}` | `181,50 €` |
| `{{iva_pct:%}}` | `21 %` |
| `{{vence:corta}}` | `30 oct` |
| `{{vence:larga}}` | `30 de octubre de 2026` |
| `{{importe:letra}}` | `ciento ochenta y un euros con cincuenta céntimos` |
| `{{permiso:sino}}` | `sí` o `no` |

**Filas que se repiten.** Una fila de tabla con variables de una lista (`{{linea.*}}`, `{{pago.*}}`,
`{{fase.*}}`, `{{sesion.*}}`) se repite una vez por elemento. Una factura con tres conceptos tiene tres filas.

**Variables que nunca se escriben en una nota.** Las `{{emisor.*}}` (NIF, domicilio y cuenta del emisor) solo se
sustituyen en el PDF o en el correo que sale, en el momento de generarlo o de enviarlo con tu OK. En la nota se
quedan tal cual.

**Con Obsidian.** `{{title}}`, `{{date}}` y `{{time}}` también funcionan. Si creas una nota desde Obsidian y se
queda con `{{numero}}` o `{{id}}` sin sustituir, la app lo detecta y ofrece rellenarlos.

### 1.4 Propiedades

- **Diccionario único** (SISTEMAS.md §1.5): un nombre tiene un solo tipo en toda la carpeta.
- **Formatos:**
  - fechas `AAAA-MM-DD`;
  - importes en euros con punto (`150.00`), que la app lee tal cual y convierte a decimal exacto;
  - porcentajes como número (`21`, no `0.21`);
  - sí y no como `true` y `false`, que es lo que entiende Obsidian;
  - listas entre corchetes.
- **Relaciones:** `"[[slug|Nombre]]"`. Los responsables se escriben `Elena Castell` o `agente:contable`.
- **Lo que se calcula no se escribe.** El pendiente de cobro, el avance de un proyecto o el último contacto los
  calcula la app al momento. Solo se escribe lo que decide una persona o lo que es una foto fija, como el informe
  de una semana.

**Una precisión al diccionario.** `origen` dice qué creó la ficha: `manual`, `regla:<evento>`, `agente:<nombre>`
o `importacion`. Por dónde llegó una persona o una oportunidad se dice con `canal`: `web`, `recomendación`,
`llamada`… Así cada nombre tiene un solo significado.

**Claves nuevas** que hay que sumar al diccionario:

| Clave | Tipo | Dónde | Para qué |
|---|---|---|---|
| `siguiente_paso`, `siguiente_fecha` | texto, fecha | Oportunidad | Criterio del Embudo: ninguna oportunidad sin siguiente paso con fecha |
| `aceptada` | fecha | Oportunidad | Cuándo pasó a Aceptada; dispara el contrato y la factura |
| `no_contactar` | sí/no | Contacto | Pidió no recibir comunicaciones |
| `estado` | opción | Contacto, Empresa | Ciclo de vida del cliente: Interesado, Activo, Antiguo cliente o Archivado. `relacion` queda solo para el papel (cliente, proveedor…) |
| `tipo` | opción | Empresa | empresa, profesional, particular o administración; decide la retención |
| `tipo`, `modelo_precio`, `precio_min`, `precio_max` | opción, opción, dinero, dinero | Servicio | Qué es (servicio, producto, formación…), cómo se cobra (fijo, por unidad o a medida) y el rango si es a medida |
| `descubrimiento` | enlace | Servicio | Su variante de reunión de descubrimiento, con las preguntas guía del servicio |
| `reunion` | enlace | Propuesta | La reunión de descubrimiento de la que el asistente sacó el borrador |
| `conexiones` | enlaces | Ficha de sistema | Programas conectados que usa; los permisos viven en la configuración |
| `pestanas_por` | opción | Nota índice | Propiedad que da una pestaña por valor (estado o tipo) |
| `logo` | ruta | Empresa, Tu empresa, Manual de marca | La imagen del logo |
| `hito`, `periodo` | opción, texto | Factura | inicial, final, único o recurrente; «T4 2026» |
| `metodo`, `motivo` | opción, texto | Factura rectificativa | Por diferencias o por sustitución, y por qué |
| `ref` | texto | Propuesta, Contrato | Referencia legible: `PR-2026-10-10-talleres-martin` |
| `funciones`, `modulos` | listas | Ficha de sistema | Funciones que cubre y módulos que enciende |
| `registro` | opción | Registros (`log`) | decisiones, metas, incidencias, bitácora, correo o gestoría |
| `forma`, `donde` | opción, texto | Fragmentos | Si es sección, fila o línea, y dónde se mete |
| `ejemplo_bueno` | sí/no | Activo | Su sistema lo enlaza como modelo |
| `pdf`, `pdf_sha256` | ruta, texto | Documentos con PDF | El PDF generado y su huella |

### 1.5 Tipos de ficha que añade este documento

SISTEMAS.md §8 ya lista los `tls_type` nuevos. Este documento suma estos:

| `tls_type` | Qué es |
|---|---|
| `fragment` | Plantilla que no crea una nota: mete una sección, una fila o una línea en otra (§1.6) |
| `log` | Registro que solo crece: Decisiones, Metas, Incidencias, Bitácora, Correo del Buzón, Dudas para la gestoría |
| `routine_log` | Registro de una rutina: inicio y cierre de semana, revisión mensual y trimestral |
| `strategy` | El Rumbo |
| `root_cause` | Los cinco porqués |
| `capture` | Una captura rápida del Buzón |
| `import_report` | El informe de importación |
| `background` | Los antecedentes de un proyecto |
| `portal` | El portal del cliente |
| `session_summary` | El resumen de una sesión, en el portal |
| `editorial_plan` | El plan editorial |
| `connection` | Una conexión con otro programa (ficha que describe, no que da permisos) |
| `company` | Tu empresa (`Empresa.md`) |

### 1.6 Fragmentos

Tres plantillas no crean una nota:
- **Traspaso**, una sección del proyecto de entrega;
- **Condiciones de cobro**, una sección del servicio;
- **Gasto**, una fila de `recibidas.csv`.

Llevan `tls_type: fragment`, `forma` y `donde`. Su frontmatter no se copia: la app mete solo el cuerpo en el
sitio indicado, con el mismo motor de escritura que el resto, con vista previa y deshacer.

### 1.7 Cómo se ve cada plantilla en la app

Estas reglas valen para cualquiera de las seis direcciones de diseño:
- La cabecera sale de las propiedades: hasta 3 datos arriba, **una cifra protagonista** y hasta 4 datos
  secundarios. El resto queda plegado en «Propiedades».
- Cada `##` es un bloque que se pliega, las tablas son filas que se tocan y los estados son pastillas con texto:
  el color nunca va solo.
- Abajo hay una **barra fija** con la acción principal y «Ver como texto» (⌘E).
- Todo lo que sale fuera (enviar, publicar o emitir) abre una confirmación.

| Plantillas | Cifra protagonista | Pastilla | Acción principal |
|---|---|---|---|
| Factura y rectificativa | Total | Estado, y «Vencida» si toca | Revisar y emitir · Preparar envío · Confirmar cobro, según el estado |
| Propuesta y presupuesto | Total | Estado y días de validez | Aprobar y preparar envío |
| Contrato | Total del Anexo I | Estado | Preparar envío |
| Recibo | Importe | Cobrado | Descargar PDF |
| Oportunidad | Valor × probabilidad | Etapa y días quieta | Preparar propuesta · Mover de etapa |
| Contacto y empresa (ficha de cliente) | Iniciales o logo | Estado (Interesado, Activo…) | Nueva reunión · Nueva propuesta · Nuevo proyecto · Nueva factura · Escribir (borrador) |
| Tarea | Estado | Vencimiento | Empezar ahora · Marcar como hecha |
| Pregunta, decisión 1-3-1 y petición de encargo | La opción recomendada | Días esperando | Aprobar · Aprobar con cambios · Responder · Posponer |
| Proyecto de entrega | Sesiones hechas sobre incluidas | Fase y % cobrado | Preparar kit · Nueva incidencia |
| Reunión y acta de sesión | Fecha y hora | Estado y kit (n de 6) | Convertir acciones en tareas |
| Reunión de descubrimiento | Fecha y hora | Estado y servicio | Generar borrador de propuesta (cuando está Hecha) |
| Ficha de sistema | Número clave frente a meta | Estado y «n de m pasos sin ti» | Replicar un ejemplo · Probar con un caso · Revisar ahora |
| Servicio y versión de oferta | Precio o rango | Estado (En pruebas, Activo, Retirado) | Preparar propuesta |
| Contenido (8 tipos) | Fecha de publicar | Estado | Generar borrador · Preparar publicación |
| Caso de éxito y testimonio | La cifra o la cita | Permiso | Pedir permiso · PDF |
| Rol y rol de asistente | Misión | Ocupante | Ver como este rol |
| Objetivo | Cifra frente a meta, en anillo | Ritmo | — |
| Rutina y sus registros | Próxima fecha o veredicto | Activa | Empezar ahora |
| Kit de logo y manual de marca | El logo | Estado | Aprobar · Cambiar logo |
| Cuenta bancaria | Saldo | «Del extracto» o «Estimado» | Importar extracto |
| Índice del paquete trimestral | Lo que falta | Estado | Preparar el envío a la gestoría |

### 1.8 PDF

**Hay una maqueta por tipo de documento** dentro de la app. Toma el logo, los colores y las tipografías del manual
de marca, y lleva las fuentes incluidas, así que no necesita internet. El PDF lo genera el motor web del Mac.

**Maqueta común, en A4 vertical:**
- Cabecera: el logo a la izquierda, en su variante «para documentos»; a la derecha, el tipo de documento, el
  número y la fecha.
- Bloque protagonista: la cifra (total o importe) en la tipografía de cifras, con el color principal en su
  variante legible.
- Las partes en dos columnas, y tablas con las cifras alineadas a la derecha y de ancho fijo.
- Pie: los datos fiscales del emisor (de Ajustes › Facturación), «Página n de m» y los 8 primeros caracteres de
  la huella.
- Metadatos: título, autor (el emisor), idioma español y fecha. El texto se puede seleccionar. Falta comprobar si
  el motor del Mac etiqueta el PDF para lectores de pantalla.

**Reglas:**
- Mientras quede un `[falta: …]` o el estado sea Borrador, el PDF lleva «BORRADOR» en diagonal.
- Se guarda junto a la nota con la convención fiscal que ya usas: `AAAA-MM-DD <Tipo> <número> <cliente> <importe>€.pdf`,
  sin importe si el documento no lo tiene. Su ruta va en `pdf:` y su huella en `pdf_sha256:`.
- **Un documento emitido no se vuelve a generar.** Si cambias el logo, las facturas emitidas conservan su PDF.
- Enviar es siempre un borrador de correo con el PDF adjunto, que apruebas tú.

| Documento | Páginas | Qué lleva |
|---|---|---|
| Propuesta | 3 | 1: portada con la frase destino del cliente en grande. 2: qué proponemos, qué incluye y qué no, calendario. 3: inversión, pagos, condiciones, siguientes pasos y aceptación |
| Presupuesto | 1 | Partes, conceptos, totales y validez |
| Contrato | Las que ocupe | Partes, cláusulas, Anexo I en página propia, Anexo II si lo hay y aceptación |
| Factura y rectificativa | 1; sigue en la 2 si pasa de 15 líneas | Lo que pide el reglamento de facturación: número y serie, fecha, datos de las partes, conceptos, base, tipo y cuota de IVA, retención y total. La rectificativa dice que lo es, cita la original y el motivo. A confirmar con tu gestoría |
| Recibo | Media página | Texto de recibí, importe en cifra y en letra, y detalle |
| Cierre (acta de entrega) | 2 | Lo prometido con su evidencia, el antes y el después, y la conformidad |
| Caso de éxito | 1 | Cifra protagonista, antes, qué hicimos, después y cita |
| Acuerdo de colaboración | Las que ocupe | Como el contrato |
| Manual de marca | 6 a 8 | Portada, esencia, logo, color, tipografía, tono y formatos |
| Hoja del kit de logo | 1 | Variantes sobre claro y oscuro, espacio, tamaño mínimo y usos incorrectos |
| Opcionales | 1 o 2 | Informe de avance (versión cliente), bienvenida, resumen de sesión, diagnóstico e índice del paquete trimestral |

### 1.9 Versiones de plantilla

- Cada nota guarda con qué plantilla y qué versión se creó: `plantilla: "Factura v1"`.
- Si una versión nueva de la app trae una plantilla cambiada, **las notas que ya existen no se tocan**. En
  Sistemas y activos aparece «Hay una versión nueva de la plantilla Factura», con «Ver cambios» e «Instalar».
- «Aplicar plantilla» sobre una nota que ya existe solo añade, al final, las propiedades y las secciones que
  faltan. Nunca pisa nada.
- Si has cambiado tu copia de una plantilla, la app no la pisa al actualizar: te enseña las diferencias.

### 1.10 Datos sensibles

- Los datos fiscales y la cuenta del emisor viven en `.tls/config.yaml › facturacion`, que no lee ningún
  asistente ni ningún programa conectado. La app los pone en el PDF y en el correo al enviarlo.
- De una cuenta bancaria se guardan los 4 últimos dígitos, nunca el número entero.
- Ninguna plantilla pide contraseñas: «Tus accesos» son enlaces.
- Los logos de clientes solo se guardan si los aporta el cliente o salen de su web pública (§5.9).

---

## 2. Catálogo

Cada área tiene una tabla resumen y, debajo, el detalle de cada plantilla. En el detalle, las propiedades
obligatorias van en **negrita**. PDF: **sí** se genera con tu marca · **opc.** es opcional · **—** no hay PDF.

### 2.0 Comunes (`Comunes/`, que se instalan en `1 · Dirección/Sistemas/Plantillas/`)

| Plantilla | Tipo | Nace en | Sistema | PDF |
|---|---|---|---|---|
| Tarea | `task` | `Tareas/` del área o del proyecto | Todos | — |
| Pregunta de asistente | `task` (`tipo: pregunta`) | Ídem | DI1 | — |
| Decisión 1-3-1 | `task` (`tipo: decision`) | Ídem | DI1 | — |
| Ficha de decisión | `decision` | `1 · Dirección/Decisiones/` | DI1 | — |
| Reunión | `meeting` | `Reuniones/` de su oportunidad, proyecto o área | Todos | opc. |
| Ficha de sistema | `system` | `N · Área/Sistemas/` | Todos | — |
| Procedimiento | `procedure` | `N · Área/Sistemas/` | Todos | — |
| Activo | `asset` | `N · Área/Activos/` | Todos | — |
| Nota índice | `index` | Carpeta de cada colección | — | — |
| Proyecto interno | `project` (`clase: interno`) | `N · Área/Proyectos/<slug>/` | DI2, DI3 | — |
| Captura rápida | `capture` | `Buzón/` | CO1 | — |
| Borrador de mensaje | `draft` | `N · Área/Borradores/` | Todos | — |
| Cabecera de área | `area` | `N · Área/Área.md` | Gobierno de cada área | — |
| Tu empresa | `company` | `Empresa.md` | Puesta en marcha | — |
| Registro del Buzón | `log` (`registro: correo`) | `Buzón/Correo AAAA-MM.md` | CO1 | — |
| Informe de importación | `import_report` | `Buzón/` | CO1 | — |

- **Tarea.**
  - Propiedades: **numero, titulo, estado**, tipo, prioridad, responsable, planificada, vence, estimacion_h,
    dedicadas_h, area, proyecto, oportunidad, empresa, padre, bloqueada_por, capacidad, despertar, origen,
    creada, creada_por y cerrada.
  - Secciones: Descripción · Actividad.
  - Es la ficha de PLAN §4.2 con dos cambios: las relaciones son enlaces, y lleva título y resumen arriba.
- **Pregunta de asistente.** Una tarea con `tipo: pregunta`, asignada a ti y en «En revisión».
  - Secciones: Pregunta · Por qué la hago · Lo que propongo · Actividad.
  - Variable propia: `{{asistente}}`.
- **Decisión 1-3-1.**
  - Secciones: Problema · Opciones (una tabla con 3 y una recomendada) · Por qué recomiendo la 1 · Datos que
    hay · Qué cambia si se aprueba · Actividad.
  - El formato 1-3-1 es una idea de Blash, reformulada.
- **Ficha de decisión.** Solo para las decisiones grandes; las demás son una línea en `Decisiones.md`.
  - Propiedades: **titulo, fecha, estado** (Tomada, Sustituida), area, decidido_por, sustituye, afecta y revisar_el.
  - Secciones: Qué se decide · Por qué · Para qué · Alcance · Datos que había · Opciones descartadas · Qué hay que
    poner al día · Revisiones.
- **Reunión.** La general, para reuniones internas y las que no tienen plantilla propia.
  - Propiedades: **titulo, fecha, estado** (Prevista, Hecha, Cancelada), tipo (descubrimiento, seguimiento,
    sesion, interna u otra; las tres primeras tienen plantilla propia), hora, duracion_min, personas, empresa,
    oportunidad, proyecto, area, lugar y grabacion.
  - Secciones: Antes de la reunión (la ficha previa) · Objetivo · Qué se habló · Decisiones · Acciones · Para el
    cliente · Nota interna.
  - Las acciones se convierten en tareas al confirmarlas (idea de Blash, reformulada).
- **Ficha de sistema.** Un sistema es una carpeta con el qué, el cómo, ejemplos y una forma de comprobarlo
  (nuestro resumen del vídeo de Nico): la guía de arriba lo dice así y señala qué sección es cada cosa.
  - Propiedades: **codigo, area, estado** (falta, a medias, montado, funciona sin ti), etapa, **rol,
    numero_clave**, funciones, modulos, conexiones, revisar_cada y revisado.
  - Secciones, en el orden de SISTEMAS.md §2.2: Para qué · Cuándo se usa · **Entradas** · Pasos · Quién lo hace ·
    **Salida esperada y criterio de «bien hecho»** · Lo que nunca hace · **Herramientas y conexiones** ·
    Plantillas y activos · Procedimientos · **Referencias y ejemplos** · Cómo sabemos que va bien · Rutina ·
    Aprendido · Notas para el asistente · Origen.
  - Se unifica con la versión anterior, sin duplicar: «Recibe de y entrega a» se reparte entre Entradas y Salida
    esperada; «Qué deja hecho» y «Criterios de calidad» forman la Salida esperada, con sus criterios de sí o no
    escritos antes de la primera ejecución; «Ejemplos buenos» pasa a «Referencias y ejemplos», que el asistente
    replica antes de que se le delegue nada; y «Aprendido» sigue siendo los aprendizajes con fecha, que entran
    como propuesta de mejora que apruebas tú.
  - Las ejecuciones (tareas, proyectos y documentos que salieron del sistema) no se escriben: la app las enseña
    debajo de la ficha.
  - Un paso que ya va solo sin asistente se describe dentro de Pasos, con Disparador · Pasos · Qué deja · Si falla.
- **Procedimiento.**
  - Propiedades: **sistema**, codigo, area, estado, tiempo_min y revisado.
  - Secciones: Para qué · Entrada · Pasos · Comprobaciones · Salida · Si falla · Aprendido · Origen.
  - Que cada procedimiento diga su entrada, su salida y su tiempo es una idea de Blash, reformulada. Los 3
    procedimientos de Finanzas de G3 se leen tal cual.
- **Activo.**
  - Propiedades: **nombre, sistema**, area, estado (En uso, A revisar, Retirado), ubicacion, responsable,
    ultimo_uso y ejemplo_bueno.
  - Secciones: Qué produce · Cómo se usa · Por qué es un buen ejemplo · Origen.
- **Nota índice.** Es la «nota de categoría» de Kepano. Propiedades: **coleccion, vista**, agrupar_por,
  ordenar_por y pestanas_por (una pestaña por estado o por tipo sobre la misma colección, SISTEMAS.md §1.4). El
  cuerpo son dos o tres frases y la app no lo reescribe.
- **Proyecto interno.**
  - Propiedades: **nombre, clase, estado**, area, objetivo, responsable, inicio, fin, fecha_cierre, fase y
    horas_previstas.
  - Secciones: Resultado esperado · Por qué ahora · Alcance · Hitos · Enlaces de interés · Riesgos.
- **Captura rápida.** Propiedades: creada, hora, canal (teclado, voz, archivo, correo), estado (Por ordenar,
  Ordenada) y destino. El cuerpo es libre.
- **Borrador de mensaje.** Es la base de todos los mensajes de las áreas.
  - Propiedades: **tipo, accion, estado** (refleja la aprobación), para, asunto, en_respuesta_a, tarea,
    oportunidad, proyecto, empresa y creado_por.
  - Secciones: Mensaje (lo único que se envía) · Para ti (lo que no se envía).
- **Cabecera de área.** Las propiedades de SISTEMAS.md §2.3 y las secciones de G3: Qué transforma · Sistemas ·
  Rutina · Carpetas · Pendiente.
- **Tu empresa.**
  - Propiedades: **nombre**, aliases, sector, ciudad, personas, titular, etapa, areas_activas, moneda y logo.
    Sin datos fiscales.
  - Secciones: Qué hace · Las seis áreas · Cómo fluye el trabajo · Reglas comunes · Pendiente.
- **Registro del Buzón.** Una sección por día y una línea por entrada: hora · de · asunto · tipo · destino · estado.
- **Informe de importación.**
  - Propiedades: los recuentos y el estado.
  - Secciones: Resumen · Por bloques · Lo que se quedó donde estaba · Duplicados · Calidad de los datos · Cómo deshacer.

### 2.1 Dirección (`1 · Dirección/`)

| Plantilla | Tipo | Nace en | Sistema | PDF |
|---|---|---|---|---|
| Diagnóstico | `diagnosis` | `Diagnóstico.md` | DI3 | opc. |
| Rumbo | `strategy` | `Rumbo.md` | DI3 | — |
| Plan de 4 semanas | `project` (`clase: interno`) | `Proyectos/` | DI3 | — |
| Metas | `log` (`registro: metas`) | `Metas.md` | DI3 | — |
| Registro de decisiones | `log` (`registro: decisiones`) | `Decisiones.md` | DI1 | — |
| Cinco porqués | `root_cause` | Junto a lo que se repite | DI3, EN3 | — |
| Rutina | `routine` | `Rutinas/<rutina>.md` | DI2 | — |
| Inicio de semana | `routine_log` | `Rutinas/<rutina>/AAAA-MM-DD.md` | DI2 | — |
| Cierre de semana | `routine_log` | Ídem | DI1, DI2 | — |
| Revisión mensual | `routine_log` | Ídem | DI2, DI3 | — |
| Revisión trimestral | `routine_log` | Ídem | DI2, DI3 | — |
| Objetivo | `objective` | `Objetivos/` | DI2 | — |
| Petición de encargo | `task` (`tipo: decision`) | `Tareas/` | DI1 (Valorar encargo) | — |

- **Diagnóstico.**
  - Propiedades: **fecha, estado** (Borrador, Confirmado), etapa_global, cuello y version.
  - Secciones: Frase del negocio · Frase destino · Cliente ideal y anticliente · Las seis áreas (tabla con
    funciona y depende de ti, de 1 a 5, la etapa y tu frase literal) · Cuello de botella · Síntoma, causa y pieza
    que falta · Siguiente paso · Revisiones.
  - Reglas de TLB: la etapa es la primera pregunta respondida con «no», y el cuello es la dependencia de 4 o más
    entre las áreas con sus requisitos cumplidos.
- **Rumbo.** Propiedades: version, revisado y revisar_cada. Secciones: Qué es la empresa · A quién servimos ·
  Adónde vamos · Este trimestre · Lo que no hacemos · Reglas de la casa · Decisiones que lo cambiaron.
- **Plan de 4 semanas.**
  - Propiedades: las de un proyecto interno, más diagnostico. Las fechas por defecto son `{{fecha+1l}}` y
    `{{fecha+20l}}`.
  - Secciones: Por qué esta área · Las tres acciones (una tabla por semanas; la cuarta es volver a diagnosticar)
    · Cómo sabremos que funcionó · Lo que no tocamos.
- **Metas.**
  - Es la tabla de G3: `| Código | Indicador | Meta | Alerta | Por qué |`.
  - Trae las filas de los sistemas de serie y base sin meta. Al instalar un sistema se añade su fila.
  - La app solo cambia las columnas Meta y Alerta.
- **Registro de decisiones.** Una línea por decisión: `- AAAA-MM-DD · qué se decide · por qué · alcance · fuente`.
  La app añade al final el comentario `tls:decision` de PLAN §4.4. Lo superado se marca «(sustituida)».
- **Cinco porqués.**
  - Propiedades: **titulo, fecha**, area, sistema, proyecto, repeticiones y **estado** (Abierto, Arreglado,
    Comprobado).
  - Secciones: Qué pasó (las dos veces) · Cinco porqués · Causa en el sistema · Arreglo · Cómo comprobamos que no
    vuelve. La causa apunta al sistema, nunca a la persona (TLB).
- **Rutina.**
  - Propiedades de PLAN §4.3: **nombre, area, cadencia**, dia, hora, duracion_min, **pregunta**, responsable,
    activa y calendario.
  - Secciones: Pregunta · Qué produce · Qué no hace · Cómo se hace · Registro.
- **Inicio de semana.**
  - Propiedades: rutina, tipo, fecha, semana, tope_horas (20 por defecto, 4 al día), horas_planificadas y
    duracion_min.
  - Secciones: Lo que quedó de la semana pasada · Foco de la semana (3 como mucho) · Reparto (una tabla por día)
    · Vence esta semana · Decisiones pendientes · Lo que no haré.
- **Cierre de semana.**
  - Propiedades: las mismas, más veredicto (Avanza, No avanza).
  - Secciones: Pregunta («¿Qué decidí y qué se quedó sin decidir?») · Avanzó · Bloqueado · Decidido · Sin decidir
    · Foco de la semana que viene · Qué no haré · Veredicto · Repaso de la carpeta (5 notas al azar y la salud de
    los enlaces).
  - Lo prepara Mika a partir de las tareas (idea de Blash, reformulada); el veredicto lo das tú.
- **Revisión mensual.**
  - Secciones: Panel por área (Estable, En observación o Crítico, con su número y una frase) · Lo aprendido este
    mes · Auditoría del sistema · Decisiones · Foco del mes que viene.
  - El panel se lee en 10 minutos (idea de Blash, reformulada).
- **Revisión trimestral.**
  - Secciones: Objetivos (si los usas) · Lo aplazado y su destino · Poda de sistemas (conservar, cambiar o
    retirar) · Volver a diagnosticar · Foco del trimestre que viene · Decisiones.
  - La poda trimestral es una idea de Blash, reformulada.
- **Objetivo.**
  - Propiedades de PLAN §4.3: **titulo, area, periodo**, desde, hasta, **meta**, unidad, acumulado,
    **medido_por**, prioritario y estado.
  - Secciones: Por qué · Cómo se mide · Proyectos que cuelgan (los pone la app) · Revisiones.
  - En The Last está apagado (decisión A).
- **Petición de encargo.** El procedimiento Valorar encargo hecho tarjeta.
  - Secciones: Lo que pide (literal) · Quién decide en su lado · Encaje con la Oferta · Capacidad · ¿Nos hace más
    vendibles, más fáciles de entregar o más sencillos? · Opciones (aceptar, reconducir a diagnóstico o rechazar)
    · Actividad.
  - Vence a los 7 días.

### 2.2 Ventas (`2 · Ventas/`)

| Plantilla | Tipo | Nace en | Sistema | PDF |
|---|---|---|---|---|
| Contacto | `contact` | `Contactos/` | VE2 | — |
| Empresa | `organization` | `Empresas/` | VE2 | — |
| Oportunidad | `opportunity` | `Oportunidades/` | VE2 | — |
| Servicio | `service` | `Productos/<servicio>.md` | VE1 | — |
| Versión de oferta | `offer` | `Productos/Versiones/` | VE1 | — |
| Guion de diagnóstico | `asset` | `Activos/` | VE2 | — |
| Objeciones | `asset` | `Activos/` | VE1 | — |
| Reunión de descubrimiento | `meeting` (`tipo: descubrimiento`) | `Oportunidades/<slug>/Reuniones/` | VE2, VE1 | — |
| Reunión de diagnóstico (variante de descubrimiento) | `meeting` (`tipo: descubrimiento`) | `Oportunidades/<slug>/Reuniones/` | VE2 | — |
| Propuesta | `proposal` | `Oportunidades/<slug>/` | VE2 | sí, 3 páginas |
| Presupuesto | `quote` | `Oportunidades/<slug>/` | VE2, FI1 | sí, 1 página |
| Mensaje | `draft` | `Borradores/` | VE2 | — |
| Seguimiento | `task` | `Tareas/` | VE2 | — |
| Petición de referido | `draft` | `Borradores/` | VE3 | — |
| Mensaje de continuidad | `draft` | `Borradores/` | VE3 | — |

- **Contacto.**
  - Propiedades: **nombre**, aliases, empresa, cargo, email, telefono, relacion, **estado**, canal,
    referido_por, conversacion, verificacion, no_contactar, origen y creada.
  - Secciones: Cómo llegó · Lo que le importa (frases literales) · Notas · Historial · Todo lo relacionado ·
    `Fuente:`.
  - `relacion` es el papel (cliente, proveedor, colaborador, gestoría u otro) y `estado`, el ciclo de vida:
    Interesado → Activo → Antiguo cliente → Archivado. La app propone pasar a Activo cuando una oportunidad suya
    llega a Aceptada, y a Antiguo cliente cuando se cierra su último proyecto sin servicio recurrente. Archivar
    lo decides tú y no borra nada (SISTEMAS.md §3.5).
  - **Todo lo relacionado** no se escribe: su guía explica que la app enseña ahí sola, por relación,
    oportunidades, reuniones, propuestas, proyectos, facturas y cobros, con los botones «Nueva reunión», «Nueva
    propuesta», «Nuevo proyecto» y «Nueva factura», que crean la nota ya enlazada (SISTEMAS.md §4.4).
- **Empresa.** Es la ficha de cliente, el nodo central (vídeo de ITK).
  - Propiedades: **nombre**, aliases, tipo, razon_social, nif, domicilio, cp, ciudad, provincia, pais,
    email_facturacion, web, sector, personas, relacion, **estado**, logo, verificacion, origen y creada.
  - Secciones: Qué hace · Cómo trabajamos con ella · Notas · Historial · Todo lo relacionado · `Fuente:`.
  - Los datos de facturación son las propiedades: no se repiten en el cuerpo. Los leen la propuesta, el contrato
    y la factura.
  - Todo lo relacionado funciona igual que en el contacto y suma las personas y los servicios contratados, que
    salen de sus oportunidades y no se escriben. «Nueva reunión» propone la de descubrimiento si el cliente está
    Interesado y la de seguimiento si está Activo.
- **Oportunidad.**
  - Propiedades: **nombre, estado** (Prospecto, Diagnóstico, Propuesta, Aceptada, Ganada, Perdida, Pausada),
    **empresa, contacto**, servicio, oferta_version, precio_congelado, valor, probabilidad, responsable, canal,
    conversacion, referido_por, siguiente_paso, siguiente_fecha, despertar, creada, aceptada, cerrada,
    motivo_perdida y origen.
  - Secciones: Cliente · Qué pide y alcance · Condiciones por acordar · Decisión · Seguimiento · Documentos · `Fuente:`.
- **Servicio** (o producto). Es la única fuente de precios y la ficha central del servicio (Kepano: clientes,
  proyectos y servicios).
  - Propiedades: **nombre, codigo, tipo, estado** (En pruebas, Activo o Retirado), version, valido_desde,
    **modelo_precio** (fijo, por unidad o a medida), **precio** o el rango **precio_min y precio_max**, **unidad,
    iva_pct**, retencion_pct, recurrencia, plan, descubrimiento y responsable.
  - Secciones: Para quién · Qué resuelve · Incluye · No incluye · Fases · Condiciones de cobro · Cliente ideal y
    anticliente · Objeciones · Reunión de descubrimiento · Clientes y proyectos · Versiones.
  - Fases, Reunión de descubrimiento y Clientes y proyectos no se escriben aquí: las fases salen del plan de
    entrega, las preguntas guía viven en su variante de reunión, y los clientes, oportunidades, proyectos e
    ingresos los enseña la app. Así cada cosa tiene una sola fuente.
  - Si es a medida, la propuesta pide el precio dentro del rango y lo fijas tú. Retirado no se ofrece en
    propuestas nuevas, pero conserva sus clientes, proyectos y versiones.
- **Versión de oferta.** Copia congelada al aprobar un cambio. Las propuestas y las facturas la citan y nunca cambia.
  - Propiedades: **servicio, codigo, version, estado**, precio, unidad, iva_pct, retencion_pct, valido_desde,
    valido_hasta y decision.
  - Secciones: las del servicio, más «Qué cambia respecto a la versión anterior».
- **Guion de diagnóstico.**
  - Bloques con sus minutos: encuadre 5, Dirección y negocio 10, Ventas y oferta 10, Entrega 10, Finanzas, Equipo
    y Marca 10, sistema y herramientas 5, propuesta y cierre 10.
  - Lleva preguntas de partida por bloque, la tabla «Lo que tiene que salir» (frase del negocio, cliente ideal y
    anticliente, problema por área, cuello confirmado, frase destino literal y siguiente paso) y tres reglas.
  - Las preguntas están escritas de nuevo, no copiadas de ningún material.
- **Objeciones.** Una tabla: Objeción · Respuesta · Prueba · Siguiente paso, más la sección Aprendido. El formato
  de cuatro columnas es una idea de Blash, reformulada.
- **Reunión de descubrimiento** (vídeo de ITK). La reunión de la etapa Diagnóstico: entender el problema y ver
  si el servicio encaja.
  - Propiedades: **titulo, fecha, estado**, tipo (`descubrimiento`), hora, duracion_min, personas, empresa,
    **oportunidad, servicio**, area, lugar y grabacion. El nombre lo pone la plantilla:
    `2026-10-09-descubrimiento-trimestrales.md`, «Descubrimiento · Trimestrales · Talleres Martín».
  - Secciones: Antes de la reunión (ficha previa) · **Preguntas guía** (su situación, lo que quiere conseguir,
    encaje con el servicio y decisión) · Qué se habló (frases literales) · Lo que salió · Decisiones · Acciones ·
    Nota interna.
  - **Una variante por servicio:** copia la general y cambia el bloque de encaje y la tabla «Lo que salió». Vive
    en `Sistemas/Plantillas/` como «Reunión de descubrimiento · <servicio>» y el servicio la enlaza en
    `descubrimiento`. «Nueva reunión» elige sola la del servicio que pide el cliente. Ejemplo:
    `EJEMPLOS/Reunión de descubrimiento · Trimestrales.md` (§7).
  - Al marcarla Hecha, la app propone la acción «Generar el borrador de propuesta» y lanza `diagnostico.realizado`.
  - Las preguntas están escritas de nuevo, no copiadas de ningún material.
- **Reunión de diagnóstico.** Es la variante de descubrimiento de un servicio que diagnostica la empresa entera,
  como el de The Last.
  - Ficha previa de Ventas: quién es, cómo llegó, qué ha pedido, qué sospechamos y qué queremos saber.
  - En lugar de preguntas de un servicio, sigue el guion de seis bloques, y su tabla «Lo que salió» es la
    salida del guion.
  - Variable propia: `{{guion.enlace}}`.
- **Propuesta.** El borrador lo **genera el asistente Comercial desde las notas de la reunión de
  descubrimiento**; tú lo revisas y lo envías (vídeo de ITK).
  - Propiedades: **oportunidad, version, estado** (Borrador, Aprobada, Enviada, Aceptada, Rechazada, Caducada),
    reunion, ref, fecha, valida_hasta (`{{fecha+14}}`), empresa, contacto, servicio, oferta_version, iva_pct,
    retencion_pct, base, cuota_iva, retencion, total, pdf, pdf_sha256 y origen (`agente:comercial` si la generó
    el asistente).
  - Secciones: Lo que nos contaste · Lo que proponemos · Incluye · No incluye · Calendario · Inversión (líneas y
    totales) · Pagos · Condiciones · Siguientes pasos (3, numerados) · Aceptación · Para ti (no se envía).
  - De dónde sale cada parte: «Lo que nos contaste», de «Qué se habló» y «Lo que salió» de la reunión;
    Incluye, No incluye, precio y pagos, de la versión de la oferta; el calendario, del plan de entrega; la forma,
    de las Referencias y ejemplos del sistema Embudo. Lo que no está en ninguna de esas fuentes queda
    `[falta: …]`.
  - «Para ti» lo rellena el asistente con esas fuentes y lo que falta. No sale en el PDF ni en el correo.
  - Variables propias: `{{linea.*}}`, `{{pago.*}}`, `{{fase.*}}` y `{{reunion.*}}`.
- **Presupuesto.** La versión corta para encargos sencillos.
  - Propiedades: las de la propuesta más numero (`P-AAAA-NNNN`).
  - Secciones: Para · Conceptos (con descuento) · Totales · Validez y forma de pago · Aceptación.
- **Mensaje.** El borrador para ofrecer el diagnóstico.
  - Propiedad extra: motivo (ofrecer_diagnostico, enviar_propuesta, confirmar_cita u otro).
  - Una sola llamada a la acción: dos huecos de agenda (`{{hueco.1}}` y `{{hueco.2}}`).
- **Seguimiento.**
  - Una tarea con `despertar`, asignada al asistente Comercial y creada por la regla `propuesta.enviada`.
  - La tabla de días es 7, 14, 21 y 30; el día 30 se propone Perdida (idea de Blash, reformulada).
  - Apagado en The Last.
- **Petición de referido** y **Mensaje de continuidad.** Borradores para el cierre. Solo se piden con un resultado
  que enseñar, y el siguiente paso sale de la Oferta.

### 2.3 Entrega (`3 · Entrega/`)

| Plantilla | Tipo | Nace en | Sistema | PDF |
|---|---|---|---|---|
| Plan de entrega | `delivery_template` | `Planes de entrega/<servicio>.md` | EN2 | — |
| Proyecto de entrega | `project` (`clase: entrega`) | `Proyectos/<slug>/Proyecto.md` | EN1 | — |
| Antecedentes | `background` | `Proyectos/<slug>/Antecedentes.md` | EN1 | — |
| Traspaso | `fragment` (sección) | `Proyecto.md › Traspaso` | EN1 | — |
| Bienvenida | `welcome` | `Portal Cliente/<slug>/Bienvenida.md` | EN1 | opc. |
| Petición de contexto | `draft` | `Borradores/` | EN1 | — |
| Portal | `portal` | `Proyectos/<slug>/Portal.md` | EN1 (Portal Cliente) | — |
| Acta de sesión | `meeting` (`tipo: sesion`) | `Proyectos/<slug>/Reuniones/` | EN2 | opc. |
| Reunión de seguimiento | `meeting` (`tipo: seguimiento`) | `Proyectos/<slug>/Reuniones/` | EN2 | opc. (resumen para el cliente) |
| Mensaje previo a la sesión | `draft` | `Borradores/` | EN2 | — |
| Mensaje posterior a la sesión | `draft` | `Borradores/` | EN2 | — |
| Resumen de la sesión | `session_summary` | `Portal Cliente/<slug>/S<n> · …/` | EN2 | opc. |
| Informe de avance | `report` | `Proyectos/<slug>/Informes/AAAA-Snn.md` | EN2 | opc. (versión cliente) |
| Registro de incidencias | `log` (`registro: incidencias`) | `Proyectos/<slug>/Incidencias.md` | EN3 | — |
| Ficha de incidencia | `incident` | `Proyectos/<slug>/Incidencias/INC-NNN.md` | EN3 | — |
| Acuse de recibo | `draft` | `Borradores/` | EN3 | — |
| Cierre | `closure` | `Proyectos/<slug>/Cierre.md` | EN3 | sí, 2 páginas |

- **Plan de entrega.**
  - Propiedades: **nombre, clase, servicio**, version, estado, dias_proyecto, sesiones_incluidas y terminado_cuando.
  - Cuerpo: «Terminado cuando», una tabla por fase (Tarea · Día · Dura · Margen · Quién · Se acepta cuando),
    Pagos por fase y Kit por sesión.
  - **Las fases viven en las tablas del cuerpo, no en las propiedades** (§8): así se leen en cualquier editor y
    hay una sola fuente.
  - Quién es `responsable`, `cliente` o `agente:<nombre>`. Los días son laborables.
- **Proyecto de entrega.**
  - Propiedades: **nombre, clase, estado**, fase, empresa, contacto, **oportunidad** (obligatoria y única),
    servicio, plan, responsable, inicio, fin, fecha_cierre, sesiones_incluidas, horas_previstas, franja y portal.
  - Secciones: Resultado prometido (la frase destino literal) · Traspaso · Alcance · Quién trabaja en él (con el
    acuerdo de cada colaborador) · Enlaces de interés · Riesgos.
  - El avance y el porcentaje cobrado los calcula la app.
- **Antecedentes.** Lo que pasó antes, como evidencia y no como lista de tareas. Secciones: De dónde viene ·
  Evidencias · Lo que ya se intentó · Fechas que no se mueven.
- **Traspaso.** Una tabla de 6 piezas, cada una con «Sí» o «Falta»: pago inicial, acuerdo, datos, dolores y
  cuello, frase destino y objetivos por área. Si falta algo, el proyecto vuelve a Ventas.
- **Bienvenida.**
  - Propiedades: **proyecto, contacto, estado**, franja, primera_sesion, portal y pdf.
  - Secciones: Lo que vamos a conseguir · Cómo vamos a trabajar · Lo que necesitamos de ti (3 como mucho) · Tus
    accesos (enlaces, nunca contraseñas) · Cómo hablar con nosotros.
- **Petición de contexto.**
  - Pide tres cosas sin repetir lo ya respondido: qué vendes, un vídeo de cómo trabajas hoy, y **tu logo y tu
    manual de marca**. Así el logo del cliente llega por el camino «lo aportas» (§5.9).
  - Con lo que llegue, el asistente sigue una cadena: ¿basta el contexto? → resumen → diagnóstico de arranque →
    plan de 30 días (idea de Blash, reformulada).
- **Portal.**
  - Es el formato de G3: `## Viaje` (Sesión · Estado · Fecha · Resumen para el cliente · Nota interna) y
    `## Tareas del cliente`, con casillas.
  - Añade Documentos y Dudas y problemas. El cliente nunca ve la nota interna.
- **Acta de sesión.**
  - Es una reunión con `sesion: S<n>` y una tabla de kit con las 6 piezas: mensaje previo, vídeo, plantilla de
    recogida, sesión, transformación con IA y mensaje posterior.
  - Añade «Qué queda aplicado». Va en menos de 24 h.
- **Reunión de seguimiento** (vídeo de ITK: el seguimiento periódico con el cliente activo).
  - Propiedades: **titulo, fecha, estado**, tipo (`seguimiento`), hora, duracion_min, personas, empresa,
    **proyecto**, servicio, area, lugar y grabacion.
  - El nombre lo pone la plantilla con su número de orden: «Seguimiento 2 · Talleres Martín» (`{{orden}}`).
  - Secciones: Antes de la reunión (la prepara el asistente Implementador con las acciones del seguimiento
    anterior, el avance, lo pendiente en el portal y las facturas sin cobrar) · Preguntas guía · Qué se habló ·
    Decisiones · Acciones · Para el cliente · Nota interna.
  - Si sale un trabajo nuevo, la acción es una oportunidad de continuidad (VE3), no una tarea del proyecto.
- **Mensaje previo** y **Mensaje posterior a la sesión.** Variables: `{{sesion.*}}`, `{{video.enlace}}`,
  `{{recogida.enlace}}`, `{{portal.enlace}}` y `{{acta.*}}`. Con el cliente no se usa vocabulario interno: se
  dice «tu sesión de flujos», no «S3» ni «kit».
- **Resumen de la sesión.** Lo que ve el cliente: Qué hicimos · Qué queda aplicado · Lo que necesitamos de ti ·
  Próxima sesión.
- **Informe de avance.**
  - Propiedades: **proyecto, semana, estado** (En plazo, En riesgo, Retrasado), sesiones_hechas,
    sesiones_incluidas, horas_reales, horas_previstas, cobrado_pct y avance_pct. Es una foto de esa semana.
  - Secciones: Hecho · Siguiente · Lo que necesitamos de ti · Riesgos · Las preguntas del viernes · Solo interno.
  - Lo rellena el asistente Implementador (idea de Blash, reformulada).
- **Registro de incidencias.** La tabla de 10 columnas de G3, con los plazos de 24, 48 y 72 h hábiles.
- **Ficha de incidencia.** Para las graves o repetidas.
  - Propiedades: **numero, titulo, proyecto**, tarea, reporta, tipo, **gravedad, estado**, recibida, plazo,
    cerrada y repeticion.
  - Secciones: Qué pasó · Cinco porqués · Causa en el sistema · Arreglo · Cómo comprobamos que no vuelve · Actividad.
- **Acuse de recibo.** Con el cliente no se dice «incidencia»: se dice duda, bloqueo o problema.
- **Cierre.**
  - Propiedades: **proyecto, fecha, estado** (Borrador, Conforme), **cobro_final**, nota (de 1 a 12),
    testimonio, revisiones (30, 60 y 90 días), pdf y pdf_sha256.
  - Secciones: Punto de partida · Lo prometido (Cumplida, Parcial o No, con evidencia) · Antes y después por área
    · Lo que ya haces sin nosotros · Continuidad · Revisiones · Conformidad.
  - Sin cobro final no se entrega. Al cerrar se lanza `proyecto.cerrado`.

### 2.4 Finanzas (`4 · Finanzas/`)

| Plantilla | Tipo | Nace en | Sistema | PDF |
|---|---|---|---|---|
| Contrato | `agreement` | `2 · Ventas/Oportunidades/<slug>/Contrato.md` | FI1 | sí |
| Factura | `invoice` | `Fiscal/Borradores/` → `Fiscal/AAAA/Tn/Ingresos/` | FI1 | sí |
| Factura rectificativa | `invoice` (serie R) | Ídem | FI1 | sí |
| Recibo de cobro | `receipt` | `Fiscal/AAAA/Tn/Ingresos/Cobros/` | FI1 | sí, media página |
| Recordatorio de cobro | `draft` | `Borradores/` | FI1 | — |
| Condiciones de cobro | `fragment` (sección) | `Productos/<servicio>.md` | FI1, VE1 | — |
| Cuenta bancaria | `account` | `Registros/Bancos/<cuenta>/Cuenta.md` | FI2 | — |
| Gasto | `fragment` (fila) | `Registros/recibidas.csv` | FI3 | — |
| Índice del paquete trimestral | `period` | `Fiscal/AAAA/Tn/Modelos/Paquete gestoría/indice.md` | FI3 | opc. |
| Dudas para la gestoría | `log` (`registro: gestoria`) | `Gestoría/Dudas.md` | FI3 | — |

- **Contrato.**
  - Propiedades: **oportunidad, estado** (Borrador, Enviado, Aceptado, Terminado), ref, empresa, contacto,
    servicio, oferta_version, **aceptacion** (pago o firma), aceptado_el, inicio, duracion, fin, base, iva_pct,
    retencion_pct, total, pdf y pdf_sha256.
  - Secciones: Partes · Cómo se acepta · Cláusulas · Anexo I (servicio contratado, que prevalece sobre las
    cláusulas, con la tabla de pagos) · Anexo II (tratamiento de datos, opcional) · Aceptación.
  - Las 17 cláusulas cubren los mismos temas que las de `tlb/contrato.html`: objeto, alcance, forma de trabajo,
    obligaciones de cada parte, plazo e inactividad, precio y pago, propiedad intelectual, confidencialidad, datos, garantía,
    responsabilidad, fuerza mayor, terminación, cesión, independencia y ley aplicable.
  - Los textos son de partida, cortos y en lenguaje llano, escritos de nuevo. **Hay que revisarlos con un
    asesor** antes de usarlos (pregunta 5).
- **Factura.** El detalle está en §3.
  - Propiedades: **numero** (vacío hasta emitir), **serie, estado**, fecha, fecha_operacion, vence, **empresa**,
    contacto, oportunidad, proyecto, servicio, oferta_version, hito, periodo, iva_pct, retencion_pct, base,
    cuota_iva, retencion, total, forma_pago, pdf y pdf_sha256.
  - Secciones: Partes · Conceptos (la fuente de las líneas) · Totales · Forma de pago · Notas · Historial.
- **Factura rectificativa.**
  - Propiedades: las de la factura, con serie R, más **rectifica, rectifica_numero, rectifica_fecha, metodo y motivo**.
  - Secciones: Qué rectifica · Motivo · Partes · Conceptos · Totales · Forma de pago o devolución · Historial.
- **Recibo de cobro.**
  - Propiedades: **numero** (`CB-AAAA-NNNN`), **factura**, empresa, **importe, fecha**, metodo, **evidencia**
    (`movimientos.csv#MOV-…`), pago_id, confirmado_por, pdf y pdf_sha256.
  - Cuerpo: el texto de recibí, con el importe en cifra y en letra, y la tabla Detalle.
  - Solo existe después de que una persona confirma el cobro.
- **Recordatorio de cobro.** Tono amable: «si ya la habéis pagado, ignora este mensaje». La cuenta va como
  `{{emisor.cuenta}}` y la app la pone al enviar. Al mismo tiempo aparece en Decisiones «¿Seguimos entregando?».
- **Condiciones de cobro.** Tabla Pago · % · Cuándo · Vence a. Vive en cada servicio y la copian la propuesta, el
  contrato y la factura. Por defecto, la regla de la rejilla: 50 % al aceptar y 50 % al entregar, a 7 días.
- **Cuenta bancaria.**
  - Propiedades de PLAN §4.3: **nombre**, banco, alias, iban_ultimos4, moneda, saldo_inicial,
    fecha_saldo_inicial, estado y formato_extracto (separador, decimal, formato de fecha y columnas).
  - El formato del extracto lo adivina la app la primera vez y te lo enseña para confirmar.
- **Gasto.**
  - Es un formulario que deja una fila en `recibidas.csv`, con el original en `Gastos/<proveedor>/`. No hay nota
    por gasto, para no tener dos fuentes.
  - Lleva las cinco columnas nuevas al final de la cabecera: base, iva, retencion, categoria y naturaleza
    (decisión 12 de SISTEMAS.md). La naturaleza (fijo, variable o inversión) es una idea de Blash, reformulada.
- **Índice del paquete trimestral.**
  - Propiedades: **periodo, estado** (Preparando, Preparado, Enviado, Presentado), desde, hasta, listo y enviado_el.
  - Secciones: el aviso «no es una declaración» · Qué contiene · Totales · Lo que falta · Modelos del trimestre ·
    Dudas para la gestoría.
  - Los cuatro CSV van con «;» y coma decimal.
- **Dudas para la gestoría.** Una línea por duda: fecha · pregunta · de dónde sale · Abierta o Respondida ·
  respuesta. El asistente Contable no decide tratamientos fiscales: los pregunta aquí.

### 2.5 Marca (`5 · Marca/`)

| Plantilla | Tipo | Nace en | Sistema | PDF |
|---|---|---|---|---|
| Manual de marca | `brand` | `Marca.md` | MA1 | sí, 6 a 8 páginas |
| Kit de logo | `asset` | `Activos/Logo/Logo.md` | MA1 | sí, hoja del kit |
| Plan editorial | `editorial_plan` | `Plan editorial.md` | MA2 | — |
| Calendario editorial | `index` (`vista: calendario`) | `Calendario editorial.md` | MA2 | — |
| Post · Carrusel · Vídeo corto · Newsletter · Artículo · Anuncio | `content` | `Contenidos/<slug>.md` | MA2 | — |
| Caso de éxito | `content` (`tipo: caso`) | `Contenidos/` | MA3 | sí, 1 página |
| Testimonio | `content` (`tipo: testimonio`) | `Contenidos/` | MA3, VE3 | — |
| Conversación | `conversation` | `Conversaciones/` | MA3 | — |

- **Manual de marca.**
  - Propiedades, que leen todas las maquetas: **nombre**, eslogan, estado, version, logo, color_principal,
    color_secundario, fondo_claro, fondo_oscuro, tipografia_titulos, tipografia_texto, tipografia_cifras y tono.
  - Secciones: Esencia · A quién hablamos (y a quién no) · Cómo hablamos (Decimos · No decimos) · Bios (larga,
    corta y mínima) · Logo · Color · Tipografía · Formatos · Plantillas visuales · Revisión de materiales (Apta,
    Ajustar o Replantear).
  - Las bios no son una plantilla aparte: son una sección del manual.
- **Kit de logo.** El detalle está en §5 y §6.
  - Propiedades: **nombre, sistema, estado** (Provisional, Borrador, Aprobado, Retirado), origen (aportado, web,
    tipografico o ia), fuente, obtenido_el, derechos, vectorial, fondo_transparente, resolucion_px, colores,
    contraste_claro, contraste_oscuro, aprobado_el, version y pdf.
  - Secciones: Variantes · Comprobaciones · Espacio y tamaño mínimo · Usos incorrectos · Origen · Versiones anteriores.
- **Plan editorial.** El detalle está en §4.
  - Propiedades: canal_principal, canales, cadencia, mezcla, dias_fijos y revisado.
  - Secciones: Para qué publicamos · Canales · Pilares · Mezcla · Días fijos · Reglas · Banco de ideas.
- **Calendario editorial.** Una nota índice con vista de calendario sobre la fecha de publicar, más un «Plan del
  mes» en borrador que crea las piezas (§4).
- **Contenidos.** Una base común y ocho variantes (§4).
- **Conversación.**
  - Propiedades: **contacto, canal**, contenido (la pieza que la trajo), **fecha, estado** (Nueva, Propuesta a
    Ventas, Cualificada, No cualifica), decidido_por, oportunidad y motivo.
  - Secciones: Lo que dijo · Contexto · Decisión de Ventas. Marca no cualifica: lo decide Ventas.

### 2.6 Equipo (`6 · Equipo/`)

| Plantilla | Tipo | Nace en | Sistema | PDF |
|---|---|---|---|---|
| Rol | `role` (`clase: humano`) | `Roles/` | EQ1 | — |
| Rol de asistente | `role` (`clase: agente`) | `Roles/` | EQ1, EQ2 | — |
| Acuerdo de colaboración | `collaboration` | `Colaboraciones/` | EQ3 | sí |
| Plan de incorporación | `delivery_template` (`clase: incorporacion`) | `Sistemas/Plantillas/` | EQ3 | — |
| Bitácora mensual | `log` (`registro: bitacora`) | `Bitácora/AAAA-MM.md` | EQ2 | — |
| Conexión | `connection` | `Conexiones/<slug>.md` (carpeta nueva) | EQ2 | — |

- **Rol.**
  - Propiedades: **nombre, clase**, areas, ocupante, nivel, pregunta, sistemas y numeros.
  - Secciones: Misión · Decide sin preguntar · Puede solo · Puede con tu OK · Nunca · Qué recibe y qué entrega ·
    Números · Sistemas · Escalado · Rutinas.
  - Describe; los permisos de verdad están en `config.yaml`. Los asistentes no escriben aquí. «Qué recibe y qué
    entrega» es una idea de Blash, reformulada.
- **Rol de asistente.**
  - Lo mismo, más lee_areas y tope_mes_eur.
  - Secciones extra: Formato de lo que entrega · Cuándo te pregunta · Escalera de autonomía (los cuatro modos con
    sus umbrales de SISTEMAS.md §6.3) · Coste.
  - La escalera equivale al traspaso en cuatro fases (idea de Blash, reformulada).
  - Sus instrucciones de trabajo son las fichas de los sistemas que lleva: no hay instrucciones aparte.
- **Acuerdo de colaboración.**
  - Propiedades: **contacto, estado**, empresa, proyecto, inicio, fin, compensacion, forma_pago, accesos,
    exclusividad, aceptado_el, pdf y pdf_sha256.
  - Secciones: Partes · Qué se encarga · Plazo y entregables · Compensación · Accesos · Propiedad intelectual (lo
    hecho en común solo se vende con permiso de ambas partes) · Confidencialidad y datos · Fin del acuerdo ·
    Aceptación.
- **Plan de incorporación.**
  - Usa el mismo motor que el plan de entrega, con cuatro fases: Día 1 (mira), Semana 1 (lo hacéis juntos), Mes
    1 (lo hace y tú miras) y Día 90 (lo hace solo y te informa).
  - Las tareas nacen al aceptar el acuerdo. La incorporación a 7, 30 y 90 días es una idea de Blash, reformulada.
- **Bitácora mensual.** Una línea por trabajo de un asistente: fecha y hora · asistente · función · qué hizo ·
  resultado · uso. Nadie la edita.
- **Conexión.**
  - Propiedades: **nombre, tipo, estado**, conectada_el, asistentes y responsable.
  - Secciones: Para qué · Qué lee · Qué puede hacer · Qué nunca hace · Permisos por asistente · Si falla.
  - Igual que el Rol, describe y no da permisos.

---

## 3. Documentos con importes

Son seis: propuesta, presupuesto, contrato, factura, factura rectificativa y recibo.

### 3.1 De dónde sale cada dato

| Dato | Fuente | Regla |
|---|---|---|
| Precio y unidad | La versión de la oferta congelada en la oportunidad | Nunca se teclea. Para cambiarlo, se crea una versión nueva del servicio, con una decisión |
| Condiciones de cobro | La sección del servicio | La copian la propuesta, el contrato y la factura |
| IVA | El servicio (21 % por defecto) | Una línea exenta necesita el motivo en Notas. La app no decide exenciones |
| Retención | `config.yaml › facturacion` y el `tipo` de la empresa cliente | Solo si el emisor es un profesional (persona física) y el cliente es empresa o profesional: 15 %, o 7 % mientras dure el tipo reducido de inicio de actividad. Si el emisor es una sociedad, 0 %. Confírmalo con tu gestoría |
| Datos del cliente | Las propiedades de su Empresa | Lo que falta se escribe `[falta: …]` y bloquea la emisión |
| Datos del emisor | `config.yaml › facturacion` | Solo en el PDF y en el correo |

### 3.2 Cálculo exacto

1. Importe de cada línea = cantidad × precio × (1 − descuento ÷ 100), redondeado a céntimos.
2. Base de cada tipo de IVA = suma de los importes de sus líneas.
3. Cuota de IVA = base × tipo, redondeada a céntimos, una vez por tipo.
4. Retención = base sujeta × porcentaje, redondeada a céntimos.
5. Total = bases + cuotas − retención.
6. El redondeo va al céntimo más cercano; el medio céntimo, hacia arriba en valor absoluto, también en negativo.
7. **Pagos fraccionados:** cada pago = base × su porcentaje, redondeado. El último pago se queda la diferencia,
   para que la suma cuadre al céntimo. El IVA y la retención se calculan sobre la base de cada pago.
8. Todo en decimal exacto, nunca con decimales aproximados.

Ejemplo de Ribera: 1 × 150,00 € = 150,00 €; IVA 21 % = 31,50 €; retención 0 % (el emisor es una sociedad);
total, 181,50 €.

**Lo que corrige de las plantillas de `tlb/`:**
- calculaban con decimales aproximados y redondeaban al mostrar, lo que podía descuadrar un céntimo;
- el catálogo de precios estaba escrito dentro del HTML, y la Oferta debe ser la única fuente;
- la rectificativa no cambiaba el signo de los importes ni enlazaba la factura original;
- lo que se editaba se guardaba en el navegador, no en la carpeta.

### 3.3 Series, números y estados

| Documento | Serie | Ejemplo | Se numera |
|---|---|---|---|
| Factura | F | F-2026-0007 | Al emitir |
| Factura rectificativa | R | R-2026-0001 | Al emitir |
| Presupuesto | P | P-2026-0003 | Al aprobarlo |
| Recibo de cobro | CB | CB-2026-0005 | Al confirmar el cobro |
| Tarea | T | T-0031 | Al crearla |
| Incidencia | INC | INC-007 | Al registrarla, dentro de su proyecto |

- El contador va por serie y por año en `.tls/secuencias.json`, y se reinicia el 1 de enero (pregunta 3).
- Un número asignado no se reutiliza nunca, y un borrador no tiene número.
- Si eliges que el número oficial lo ponga otro programa (decisión 13 de SISTEMAS.md, opción A), la app deja el
  número vacío hasta que ese programa lo devuelve.
- **Estados de la factura:** Borrador → (tu OK) Emitida → (tu OK) Enviada → (cobro confirmado) Cobrada. Pasa a
  Rectificada si se emite una rectificativa.
- «Vencida» no es un estado: es una pastilla que la app calcula cuando pasa la fecha y la factura sigue sin cobrar.
- **Una factura emitida queda fija.** Si alguien la cambia fuera de la app, sale un aviso con «Restaurar la
  versión emitida».

### 3.4 Factura rectificativa

- Serie R, con el enlace `rectifica` a la original, el `metodo` y el `motivo`.
- **Por diferencias:** solo la diferencia, en negativo si resta. **Anulación total:** todas las líneas de la
  original, en negativo. **Por sustitución:** todas las líneas con los importes correctos.
- Al emitirla, la original pasa a Rectificada y enlaza la rectificativa en su Historial.
- Si el total es negativo y la original ya estaba cobrada, se prepara una devolución: una fila de pago con
  dirección «pago» que confirma una persona. La app nunca mueve dinero.

### 3.5 Del sí al cobro, documento a documento

| Momento | Documento | Lo prepara | Lo apruebas tú |
|---|---|---|---|
| Diagnóstico hecho | Propuesta v1 o presupuesto | Asistente Comercial | El envío |
| Oportunidad Aceptada | Contrato y factura inicial | Asistente Contable | La emisión y el envío |
| Cobro confirmado | Recibo, oportunidad Ganada y proyecto | La app | La confirmación del cobro |
| Último hito | Factura final | Asistente Contable | La emisión y el envío |
| Vence una factura | Recordatorio y «¿Seguimos entregando?» | Asistente Contable y Mika | El envío y la decisión |
| Error en una factura | Factura rectificativa | Asistente Contable | La emisión |

---

## 4. Marca: tipos de contenido, plan y calendario

### 4.1 Una base común y ocho variantes

Todas las variantes, salvo el testimonio, comparten:
- **Propiedades:** **titulo, tipo, estado**, pilar, canales, objetivo (atraer, nutrir o convertir), cta,
  servicio, publicar, publicado, derivado_de (la pieza raíz), responsable, evidencia_url, alcance, impresiones e
  interacciones. Las conversaciones que trae cada pieza las cuenta la app.
- **Brief:** para quién, qué tiene que pensar o sentir, qué tiene que hacer después y de qué pieza raíz sale.
  Sacar varias piezas de una raíz es una idea de Blash, reformulada.
- **Resultados y Notas**, al final.
- **Estados:** Idea → Borrador → En revisión → Aprobado → Programado → Publicado, o Descartado. Publicar siempre
  pide tu OK.

| Tipo | Secciones propias | Medida o límite | Propiedades extra |
|---|---|---|---|
| Post | Gancho · Texto · Llamada a la acción · Imagen | — | — |
| Carrusel | Portada · Diapositivas (Nº, Titular, Texto, Imagen) · Llamada a la acción · Texto de la publicación | 1080 × 1350, de 5 a 10 diapositivas | — |
| Vídeo corto | Gancho (0 a 3 s) · Guion (Tiempo, Plano, Voz, Texto en pantalla) · Llamada a la acción · Música y derechos | 1080 × 1920, de 30 a 90 s, con subtítulos | duracion_s |
| Newsletter | Asunto · Preencabezado · Apertura · Bloques · Llamada a la acción · Despedida | Asunto de menos de 50 caracteres | asunto, preencabezado |
| Artículo | Titular · Entradilla · Estructura · Texto · Descripción para buscadores · Llamada a la acción | Descripción de menos de 155 caracteres | palabra_clave, url |
| Caso de éxito | Cliente · Antes · Qué hicimos · Después · Cita · Permiso | PDF de 1 página para las propuestas | proyecto, empresa, anonimo, permiso, permiso_el, cifra, pdf |
| Testimonio | Cita literal · Quién · Contexto · Permiso | Sin permiso no se publica | autor, empresa, proyecto, autorizado, autorizado_el, medio, usos |
| Anuncio | Objetivo · Público · Mensaje A · Mensaje B · Pieza · Resultados · Qué aprendimos | El objetivo es un número, no «visibilidad» | presupuesto, inicio, fin, publico, coste |

Reglas que repiten todas las plantillas: una sola llamada a la acción y ninguna cifra sin evidencia. Un caso o un
testimonio sin permiso no sale ni en redes ni en propuestas.

### 4.2 Plan editorial

- Es un solo fichero, `5 · Marca/Plan editorial.md`.
- Lleva canales, cuatro pilares (educativo, inspirador, conversación y venta), la mezcla, los días fijos, las
  reglas y un banco de ideas.
- Mezcla de partida: 60 % educativo, 20 % inspirador, 10 % conversación y 10 % venta (idea de Blash,
  reformulada). Se cambia a tu medida.
- Para qué se publica: para que empiecen conversaciones con quien puede comprar. Los seguidores no son la meta.

### 4.3 Calendario editorial

Pediste el calendario como un tipo de contenido más, y SISTEMAS.md lo dejaba solo como vista. Esta propuesta
junta las dos cosas sin crear dos fuentes:
- `5 · Marca/Calendario editorial.md` es una **nota índice** con vista de calendario sobre la fecha `publicar` de
  las piezas. En la app, arrastrar una pieza a otro día cambia su fecha.
- Debajo lleva **el plan de un mes en borrador** («Plan de noviembre de 2026», por ejemplo): una tabla Semana ·
  Día · Pilar · Formato · Idea · Canal, que se rellena bien en texto plano.
- **«Crear piezas»** convierte cada fila en una ficha de contenido en estado Idea, con su fecha, y la idea pasa a
  ser un enlace. Es un solo cambio, que se deshace de una vez.
- Desde ese momento **la fecha vive en la ficha**. Si la cambias allí, el calendario se mueve solo y la tabla no
  se reescribe. Si la tabla y la ficha dejan de coincidir, la app lo señala en la vista.
- En Obsidian, con el módulo «Vistas para Obsidian», la nota incrusta además un `.base` agrupado por mes.

---

## 5. El logo: aportarlo, traerlo o generarlo

### 5.1 Dónde se pide

- **En la puesta en marcha**, en la pantalla «Tu marca», que es una de las cinco preguntas de una empresa nueva.
  En tu copia sale premarcada con lo que ya hay en `5 · Marca/Recursos/Manual de marca/logo/`.
- **En Marca › Kit de marca › «Cambiar logo»**, y en la acción rápida «Subir logo» del área.
- La pantalla tiene tres opciones grandes:
  - **«Ya lo tengo»** (camino a);
  - **«Está en mi web»** (camino b);
  - **«Créalo con mi nombre»** (camino c1).

  Debajo, «Ahora no». La empresa sigue sin logo y los documentos salen con el nombre escrito (§5.8).
- Lo haces tú. El asistente Marca prepara candidatos y comprobaciones en modo «Te ayuda». **Ningún asistente
  aprueba un logo.**

### 5.2 Siempre termina igual

```
5 · Marca/Activos/Logo/
├── Logo.md                         ficha del kit (plantilla «Kit de logo»)
├── original/                       lo recibido, sin tocar
├── logo.svg · logo-blanco.svg · logo-negro.svg
├── isotipo.svg · isotipo-blanco.svg
├── avatar-1024.png · favicon-512.png · portada-social-1500x500.png
├── logo-documento.png              300 ppp, para los PDF
├── qr-web.svg                      enlace a tu web, si la tienes
└── 2026-10-22 Kit de logo.pdf      hoja del kit
```

`Logo.md` nace como Provisional o Borrador y solo pasa a Aprobado con tu OK.

### 5.3 Camino a: lo aportas

1. **Arrastras un SVG, PDF, PNG o JPG** de 10 MB como mucho. El fichero se guarda tal cual en `original/`.
2. **Limpieza.** Si es un SVG, la app le quita el código, los enlaces externos y las fuentes que cargue de
   internet antes de usarlo. Se ve igual y no ejecuta nada. Si es un PDF, se usa su primera página.
3. **Comprobaciones:**

   | Comprobación | Cómo | Si no la pasa |
   |---|---|---|
   | Tamaño | 1.000 px en el lado corto, o vectorial | Avisa de que se verá borroso en documentos grandes y ofrece buscarlo en tu web o crear uno con tu nombre |
   | Fondo | ¿Es transparente? | Si el fondo es de un solo color, propone quitarlo y enseña el antes y el después. Si no, no hay variantes de un color |
   | Contraste | Al menos 3:1 sobre blanco y sobre negro | Propone qué variante usar en cada fondo |
   | Colores | Los 3 dominantes | Te los propone para el manual de marca |

4. **Variantes:**
   - de un SVG o un PDF vectorial salen todas;
   - de un PNG con fondo transparente, las de un solo color se hacen rellenando la silueta;
   - de una imagen con fondo de un color, solo después de que aceptes quitar el fondo;
   - el isotipo solo existe si lo aportas o si lo marcas recortando el logo. **La app no inventa isotipos:**
     en su lugar ofrece un monograma con tus iniciales (camino c1).
   - Las variantes que no se pueden hacer salen en la tabla como «No disponible», con el motivo.
5. Confirmas que es tuyo, y `derechos` pasa a «propio».

### 5.4 Camino b: lo traemos de tu web o de tus redes

1. **Solo desde la dirección que escribes tú y con tu permiso.** La pregunta es concreta: «Voy a descargar la
   página [la dirección que escribiste] y sus imágenes. No envío nada más.» Lo hace la app, o el asistente Marca a petición tuya.
2. **Lee una sola página**, sin recorrer la web:
   - el logo de la cabecera, en SVG o en imagen;
   - el icono de la web y el de móviles;
   - la imagen que se ve al compartir la web en redes;
   - el logo que la página declara para los buscadores.
3. **Redes:** solo la foto de perfil, si pegas la dirección del perfil. Muchas redes no la dejan ver sin iniciar
   sesión; entonces la app te pide que la arrastres.
4. **Candidatos lado a lado**, con su tamaño y su fondo. Eliges uno y confirmas que es tuyo. En `Logo.md` quedan
   anotados `fuente` y `obtenido_el`.
5. Si solo hay una imagen pequeña, la marca como «baja resolución» y propone el camino c1.
6. Lo descargado se trata como no fiable: se limpia como en el camino a y se guarda en `original/`.

### 5.5 Camino c1: logotipo con tu nombre, generado en la app

- **Funciona sin internet, es gratis y da siempre el mismo resultado** con los mismos datos.
- **Pide cuatro cosas:**
  - el nombre tal como quieres que se lea;
  - el color principal, con una paleta propuesta y un aviso si no se lee bien sobre blanco o sobre negro;
  - una de las 4 tipografías libres que trae la app: Space Grotesk, DM Sans, Fraunces o Manrope (pregunta 7);
  - si quieres monograma con tus iniciales, en círculo o en cuadrado redondeado.
- **Propone 6 versiones:** solo el nombre; monograma y nombre en línea; o monograma encima del nombre. Cada una,
  en peso medio y en negrita.
- Salen en SVG con el texto convertido en trazos, para no depender de la fuente instalada.
- El monograma hace de isotipo y de avatar.
- Las tipografías tienen licencia libre (OFL), que permite usarlas en un logo, y `derechos` queda en «propio».
- Queda como Provisional hasta que lo apruebas, y puede ser tu logo definitivo.

### 5.6 Camino c2: con IA de imagen (solo si lo activas)

- Solo con un programa de imagen conectado («otros programas») y si eliges la opción B de la decisión 14 de
  SISTEMAS.md. En la v1 se propone dejarlo fuera.
- **Permiso cada vez:** «Enviaré a [el programa] el nombre de tu empresa, tu sector, tu tono y tus colores».
- La petición se monta con `Marca.md`, y en `Logo.md › Origen` quedan la herramienta y la petición.
- Devuelve imágenes PNG. La app avisa de que no son vectoriales y de que conviene redibujarlas para documentos
  grandes.
- `derechos` queda en «pendiente» hasta que revises las condiciones de uso del generador.
- Nunca se lanza solo.

### 5.7 Aprobar, cambiar y retirar

- **Estados:**
  - Provisional: el logotipo generado sin revisar, o el nombre escrito si no hay logo;
  - Borrador: elegido, sin aprobar;
  - Aprobado;
  - Retirado.
- **Al aprobar:**
  - `Logo.md` pasa a Aprobado, con fecha;
  - los colores pasan al manual de marca con tu OK, enseñándote la diferencia;
  - el logo aparece en propuestas, presupuestos, contratos, facturas, recibos, cierres, casos de éxito, el portal
    del cliente, la firma de correo y el selector de empresa de la barra lateral.
- **Al cambiarlo:**
  - se crea una versión nueva y la anterior va a `Archivo/5 · Marca/Activos/Logo/<fecha>/`;
  - los PDF ya emitidos no cambian;
  - queda una línea en «Versiones anteriores» y otra en `Decisiones.md`, porque es un cambio de identidad.

### 5.8 Si no hay logo

- **Documentos:** la cabecera lleva el nombre de la empresa en la tipografía de títulos y en el color principal.
  No lleva la marca «Borrador»: que falte el logo no es un dato que falte.
- **Barra lateral:** las iniciales sobre el color principal, como en los contactos.
- **Hoy:** una tarjeta discreta, una sola vez y dentro del tope de tarjetas: «Tus documentos salen sin logo ·
  Añadir logo».

### 5.9 Logos de clientes y proveedores

- Sirven para el Directorio, el portal del cliente y los casos de éxito.
- **Solo llegan por el camino a**, porque los aporta el cliente (por ejemplo, con la Petición de contexto), **o
  por el b**, desde su web pública y con tu permiso. **Nunca se genera un logo para otra empresa.**
- Se guardan en `2 · Ventas/Empresas/Logos/<slug>.<extensión>` y la Empresa lo enlaza en `logo`.
- En un caso de éxito, el logo del cliente solo sale si hay permiso (`permiso: true`).

### 5.10 Accesibilidad

- Los elementos gráficos necesitan un contraste de 3:1 como mínimo (WCAG 1.4.11): es la comprobación de §5.3.
- Si el color principal no llega a 4,5:1 como texto, la app usa una variante más oscura o más clara para el
  texto. Con el magenta de The Last: #E6007E vale como relleno con texto blanco (4,50:1); como texto se usa
  #C4006B sobre claro y #FF3D9A sobre oscuro.
- El logo lleva texto alternativo en el PDF y en el portal: «Logo de» y el nombre de la empresa.

### 5.11 Mensajes

| Situación | Lo que dice la app | Lo que ofrece |
|---|---|---|
| Imagen pequeña | «Este logo mide 320 px: se verá borroso en los documentos» | Buscarlo en tu web · Crear uno con tu nombre · Usarlo igualmente |
| Fondo blanco | «Tiene fondo blanco: sobre fondos oscuros se verá un recuadro» | Quitar el fondo (con antes y después) · Dejarlo así |
| Poco contraste | «Sobre fondo oscuro casi no se lee» | Usar la versión en blanco en los fondos oscuros |
| Web sin logo | «No he encontrado un logo en esa página» | Probar otra dirección · Arrastrarlo · Crear uno |
| Formato no admitido | «Solo puedo usar SVG, PDF, PNG o JPG» | Elegir otro fichero |
| SVG con código | «Este SVG traía código; lo he quitado y se ve igual» | Ver el resultado |

---

## 6. El kit de marca

| Pieza | Dónde | De dónde sale | Quién la usa |
|---|---|---|---|
| Manual de marca | `5 · Marca/Marca.md` | Tú, con el asistente Marca | Todas las maquetas PDF, el portal y el asistente Marca, que toma de aquí el tono |
| Kit de logo | `5 · Marca/Activos/Logo/` | §5 | Los PDF, el portal, la barra lateral y las redes |
| Bios larga, corta y mínima | Sección del manual | Tú | Perfiles, propuestas y firma |
| Colores | Propiedades del manual | El logo, o tú | La app y los PDF. Las variantes legibles las calcula la app |
| Tipografías | Propiedades del manual | Las 4 libres de la app, o las tuyas | Los PDF y las plantillas visuales |
| Plantillas visuales | `5 · Marca/Activos/Plantillas visuales/` | La app las genera en SVG con el manual y el logo | Marca, y Entrega para las portadas de sesión |
| Código QR a tu web | `Activos/Logo/qr-web.svg` | La app, sin internet | Documentos y eventos |
| Hoja del kit | PDF en `Activos/Logo/` | La app | Para la imprenta o para quien te diseñe algo |

**Plantillas visuales que genera la app:**
- portada de documento A4;
- carrusel de 1080 × 1350 (portada, diapositiva interior y cierre);
- vídeo vertical de 1080 × 1920 (portada y rótulos);
- miniatura de 1280 × 720;
- portada de redes de 1500 × 500;
- firma de correo de 600 px de ancho.

**Reglas:**
- **Tus tipografías.** Si subes una fuente, la app comprueba si su licencia deja incluirla en un PDF. Si no lo
  permite, usa para los PDF la libre más parecida y te lo dice.
- **Revisión de materiales.** Cada material lleva un veredicto en el manual: Apta, Ajustar o Replantear.
- **En tu copia de G3.** Ya hay 15 ficheros en `5 · Marca/Recursos/Manual de marca/logo/`. «Adoptar» propone a
  qué variante del kit corresponde cada uno, sin mover los originales. Lo que queda de la identidad anterior es
  una tarea en Marca que aparece cuando actives el área (SISTEMAS.md §1.8).

---

## 7. Los cuatro ejemplos rellenos

**La historia (ficticia).**
1. Jorge Martín, gerente de Talleres Martín e Hijos SL, en Paterna, llama a Asesoría Ribera el 7 de octubre de
   2026.
2. El 9 de octubre hacen el diagnóstico y el 10 recibe la propuesta de Trimestrales.
3. El 14 la acepta. La regla `oportunidad.aceptada` crea la tarea T-0031 para el asistente Contable.
4. A la empresa le faltan el NIF y el domicilio. Lucía los consigue y Elena emite y envía la factura F-2026-0007
   el día 15.

El reloj de la demo marca el 19 de octubre: la factura aún no se ha cobrado y vence el 30.

| Fichero | Dónde viviría | Qué enseña para las maquetas |
|---|---|---|
| `Factura F-2026-0007.md` | `4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md` | Cifra protagonista de 181,50 €, pastilla «Enviada», vencimiento el 30 oct, una línea, totales con retención 0 e historial. Barra: «Confirmar cobro» · PDF |
| `Facturación y cobros.md` | `4 · Finanzas/Sistemas/Facturación y cobros.md` | La ficha de sistema completa, con las secciones nuevas: Entradas (con «si falta»), pasos con quién y modo («Siempre con tu OK»), Salida esperada y criterio de «bien hecho», Herramientas y conexiones, Referencias y ejemplos y Aprendido, con una línea que nació como propuesta del asistente al cerrar T-0031. Cifra: FIN-AR frente a la meta, con «1 de 6 pasos sin ti» |
| `Contacto Jorge Martín.md` | `2 · Ventas/Contactos/jorge-martin.md` | Iniciales JM, estado «Activo», frases literales e historial con enlaces a la reunión de descubrimiento, la propuesta y la factura. «Todo lo relacionado» explica lo que la app enseña sola y los botones «Nueva…» |
| `Tarea T-0031.md` | `4 · Finanzas/Tareas/t-0031-preparar-factura-trimestrales-talleres-martin.md` | Actividad con el sistema, el asistente y dos personas, una mención y los cambios de estado. El enlace al borrador ya apunta a la factura emitida: al mover el borrador a Ingresos, la app reescribió el enlace sola, como Obsidian |

**Una variante de ejemplo, además:** `Reunión de descubrimiento · Trimestrales.md` es la variante de la reunión
de descubrimiento para el servicio Trimestrales de Ribera. Viviría en `2 · Ventas/Sistemas/Plantillas/` y el
servicio la enlaza en `descubrimiento`. Es la que se usó con Jorge el 9 de octubre: sus preguntas de encaje
(modelos, volumen de facturas, cómo llegan los papeles, desde qué trimestre) y su tabla «Lo que salió» son lo que
necesita el borrador de la propuesta de Trimestrales.

**Sobre los datos:**
- todos son ficticios: el NIF B00000017, la «Calle Ejemplo 12» y un correo en el dominio reservado `.example`;
- Elena Castell (titular, Finanzas y Entrega) y Lucía Navarro (Ventas y Marca) se inventan para el ejemplo;
- los identificadores de la factura, el contacto y la oportunidad son los de la demo de Ribera.

---

## 8. Qué cambia respecto a SISTEMAS.md y al PLAN

1. **Tareas con `# Título` y línea de resumen.** El ejemplo de PLAN §4.2 no los tenía.
2. **Relaciones de la tarea como enlaces** (`proyecto`, `oportunidad`, `empresa`, `padre`), en lugar de `*_id`,
   en coherencia con la decisión 1.
3. **Tipos nuevos** (§1.5) y **claves nuevas** (§1.4), más la precisión entre `origen` y `canal`.
4. **Carpetas nuevas:**
   - `6 · Equipo/Conexiones/`, porque EQ2 cita la plantilla Conexión y el árbol no tenía sitio para ella;
   - `2 · Ventas/Empresas/Logos/`;
   - `5 · Marca/Activos/Plantillas visuales/`;
   - `4 · Finanzas/Gestoría/Dudas.md`.
5. **`Calendario editorial.md`** como nota índice con un plan del mes (§4.3), en lugar de ser solo una vista.
6. **Las fases del plan de entrega y del de incorporación van en tablas del cuerpo,** no en `fases[]` dentro de
   las propiedades como dice PLAN §4.3 (pregunta 2).
7. **Formatos de variable con dos puntos** (`{{total:€}}`), porque la barra rompe las tablas.
8. **«Vencida» no es un estado de la factura,** sino una pastilla calculada.
9. **La factura lleva `## Historial`,** y el servicio lleva `version` y su tabla de condiciones de cobro.
10. **Petición de encargo** (Valorar encargo) es una tarea de decisión, igual que la 1-3-1.
11. **Lo que aportan los vídeos** (SISTEMAS.md §9), en las plantillas:
    - Ficha de sistema: Entradas, Salida esperada y criterio de «bien hecho», Herramientas y conexiones y
      Referencias y ejemplos, unificadas con las secciones anteriores; la propiedad `conexiones`;
    - Servicio: `tipo`, estado En pruebas · Activo · Retirado (antes Activo · En pausa · Retirado),
      `modelo_precio` y rango, `descubrimiento`, y los bloques Fases y Clientes y proyectos;
    - Contacto y Empresa: `estado` de ciclo de vida separado de `relacion`, que ya no lleva «interesado» ni
      «antiguo cliente», y la sección «Todo lo relacionado»;
    - plantillas nuevas: Reunión de descubrimiento (con su variante por servicio) y Reunión de seguimiento. La
      Reunión de diagnóstico pasa a ser una variante de descubrimiento (`tipo: descubrimiento`);
    - Propuesta: `reunion`, `origen` y la sección «Para ti», porque el borrador sale de la reunión;
    - Nota índice: `pestanas_por`; variable `{{orden}}`; claves `nombre`, `titulo`, `desde` y `variante_por` en
      `plantillas.yaml`.

---

## 9. Preguntas para ti, con propuesta

1. **Guías dentro de las plantillas.**
   - **A) Se copian a la nota y la app las retira cuando escribes.** *Recomendada.*
   - B) No se copian; solo se ven en la app como ayuda.
2. **Fases de los planes de entrega.**
   - **A) En tablas del cuerpo: una sola fuente que se lee en cualquier editor.** *Recomendada.*
   - B) En las propiedades, como dice PLAN §4.3.
3. **Numeración de facturas.**
   - **A) Contador por serie y año, que se reinicia el 1 de enero (F-2026-0001, F-2027-0001).** *Recomendada.*
   - B) Un contador que nunca se reinicia.
4. **Condiciones de cobro de partida para empresas nuevas.**
   - **A) 50 % al aceptar y 50 % al entregar, a 7 días, como dice la rejilla. En The Last, lo que diga su
     Oferta.** *Recomendada.*
   - B) 100 % al aceptar.
5. **Cláusulas del contrato.**
   - **A) En la biblioteca, las cortas y en lenguaje llano de esta plantilla. En tu copia, las 17 de
     `tlb/contrato.html`, que ya revisaste.** *Recomendada.*
   - B) Solo las cortas, también en The Last.
6. **Calendario editorial.**
   - **A) Nota índice con un plan del mes que crea las piezas.** *Recomendada.*
   - B) Solo la vista de calendario, sin nota.
7. **Tipografías del logotipo generado:** Space Grotesk, DM Sans, Fraunces y Manrope, todas libres. *¿Te valen
   o prefieres otras?*
8. **Logos de clientes.**
   - **A) Guardarlos en `2 · Ventas/Empresas/Logos/`, solo si los aporta el cliente o salen de su web.**
     *Recomendada.*
   - B) No guardar logos de otras empresas.

La IA de imagen para el logo ya es la decisión 14 de SISTEMAS.md: aquí no se repite.

---

## Anexo. Procedencia

- **TLB:** los nombres de las áreas, lo que convierte cada una, las preguntas fijas, el diagnóstico con dos
  notas de 1 a 5 y la cita literal, el cuello por dependencia, el plan de 4 semanas, los cinco porqués que
  apuntan al sistema, el cierre de semana (avanzó, bloqueado, decidido, foco y qué no haré) y el veredicto «sin
  maquillar».
- **G3:** los formatos de `Portal.md`, `Incidencias.md`, `Decisiones.md` y `Metas.md`, las secciones de la ficha
  de sistema y de la oportunidad, y las reglas «ninguna salida sin tu OK» y «retirar es mover».
- **SISTEMAS.md y PLAN.md:** el diccionario de propiedades, los 19 sistemas, el Anexo B de plantillas, la ficha
  de tarea y el protocolo de escritura.
- **`tlb/plantillas`:** el orden de los bloques de la propuesta (3 páginas, con dos pagos y su IVA y retención),
  los temas de las 17 cláusulas del contrato, la aceptación con el pago y el Anexo I que prevalece. No se ha
  copiado ningún texto, y sus fallos de cálculo se corrigen (§3.2).
- **Asesoría Ribera:** el plan de entrega con fases y tareas, la factura con líneas, el paquete para la gestoría,
  los nombres de clientes ficticios y los identificadores de los ejemplos.
- **Método Kepano:** las propiedades arriba y poco cuerpo, las reuniones como fichas con la fecha en el nombre,
  las relaciones en propiedades, las notas índice y las plantillas que se crean desde una ficha con su contexto.
- **Vídeo de ITK (método Kepano aplicado a clientes, proyectos y servicios):** la ficha de cliente como nodo
  central con sus botones «Nueva…», los nombres que pone la plantilla, el estado como ciclo de vida con
  archivar, el servicio con tipo, estado, modelo y rango de precio, la reunión de descubrimiento con preguntas
  por servicio, la de seguimiento, las vistas por estado y tipo, y la propuesta que el asistente saca de la
  reunión.
- **Vídeo de Nico CMW:** el sistema como una carpeta con el qué, el cómo, ejemplos y una forma de comprobarlo
  (resumido por nosotros); las secciones Entradas, Salida esperada y criterio de «bien hecho», Herramientas y conexiones, Referencias y
  ejemplos y Aprendido; replicar una referencia antes de delegar y cerrar cada ejecución con «¿qué aprendimos?».
- **Referencias de diseño:** la cabecera con una cifra protagonista y la barra de acción fija; el contraste del
  magenta.
- **Ideas de Blash, reformuladas** (ningún texto copiado):
  - formato 1-3-1: Decisión 1-3-1 y Petición de encargo;
  - acciones del acta que pasan a tareas: Reunión y Acta de sesión;
  - entrada, salida y tiempo de cada procedimiento: Procedimiento;
  - criterios de sí o no: Ficha de sistema;
  - qué recibe y qué entrega: Ficha de sistema y Rol;
  - traspaso en cuatro fases: Rol de asistente y Plan de incorporación;
  - incorporación a 7, 30 y 90 días: Plan de incorporación;
  - seguimiento a 7, 14, 21 y 30 días: Seguimiento;
  - objeción, respuesta, prueba y siguiente paso: Objeciones;
  - mezcla 60/20/10/10 y pieza raíz: Plan editorial y contenidos;
  - naturaleza del gasto (fijo, variable o inversión): Gasto;
  - comprobar que el contexto basta y seguir una cadena: Petición de contexto;
  - panel mensual por área que se lee en 10 minutos: Revisión mensual;
  - poda trimestral: Revisión trimestral;
  - resúmenes que rellena el asistente: Cierre de semana e Informe de avance;
  - comportamiento del asistente separado del conocimiento: «Notas para el asistente» y «Formato de lo que entrega».
