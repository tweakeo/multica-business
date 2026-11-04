# Requisitos añadidos por Manu durante el rediseño

Manda sobre lo anterior si hay conflicto. Cada fase debe leer esta lista.

## R1 · Ver PDF dentro de la app, como en Obsidian (22/10/2026)

> «Importante poder visualizar como en Obsidian los PDF dentro de la interfaz del programa.»

**Visor integrado.** Al abrir un PDF desde la carpeta, una ficha o una relación, se ve dentro de la app, en el mismo panel donde se ven las notas, sin abrir Vista Previa. Se construye con PDFKit (`PDFView`) y tiene:
- miniaturas de las páginas;
- zoom, con ajuste a ancho y a página;
- búsqueda en el texto del PDF;
- navegación por páginas y por el índice, si el PDF lo trae;
- selección y copia de texto;
- «Abrir en Vista Previa» y «Mostrar en Finder».

Funciona en claro y en oscuro.

**PDF incrustado en una nota.** `![[factura-2026-014.pdf]]` y `![](Materiales/acta.pdf)` se pintan dentro de la nota, como hace Obsidian:
- el visor va en un bloque de altura fija y se puede ampliar;
- `#page=N` abre en esa página;
- el texto plano no cambia: la incrustación es un enlace normal.

**PDF en las fichas.** Las facturas, los justificantes, los contratos y los materiales de un proyecto muestran su PDF:
- en la pestaña correspondiente, como vista previa;
- en la vista Galería de las Bases, como miniatura de la primera página.

**PDF que solo está en iCloud.** Abrirlo es una acción explícita de la persona, así que pide la descarga (`startDownloadingUbiquitousItem`). Mientras baja se ve el progreso, con «Volver a intentarlo». **Nunca** se descarga nada al recorrer la carpeta ni al indexar: se mantiene la garantía de F0.

**Lo que no hace:**
- no edita el PDF;
- no guarda anotaciones dentro del fichero, porque modificar originales queda fuera, sobre todo los fiscales.

Si más adelante se quieren anotaciones, irían en una nota aparte enlazada.

**Búsqueda.** El texto de los PDF entra en la búsqueda global (⌘K y las Bases):
- se extrae con PDFKit solo de los ficheros ya descargados, en segundo plano;
- se guarda únicamente en el índice desechable, nunca en la carpeta;
- los PDF de rutas privadas no se indexan para los asistentes.

**El mismo criterio para otros ficheros:**
- **imágenes** (png, jpg, heic, svg): visor integrado e incrustación con `![[…]]`;
- **audio y vídeo:** reproductor nativo con AVKit;
- **resto de ficheros:** vista previa de Quick Look en un panel, con «Abrir con…».

**Cuándo:** F1, en la interfaz: visor, incrustaciones y vista previa en las fichas. F2: miniaturas en Galería y texto de los PDF en la búsqueda.
