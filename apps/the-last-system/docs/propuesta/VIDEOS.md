# Análisis de los dos vídeos de referencia

Ambos vídeos se han analizado a partir de su transcripción completa (subtítulos automáticos en español).

## Vídeo 1 · «Obsidian para gestionar clientes, proyectos y servicios | Método Kepano» (ITK, 21:45)

**Caso.** Un pequeño negocio de servicios (mentorías y gestión del conocimiento) organizado en Obsidian con el método de Steph Ango (Kepano).

**Método, paso a paso:**
1. **Identificar las categorías relevantes.** Aquí son 4: Clientes, Servicios, Reuniones y Proyectos. Si aparecen más, se crean.
2. **Una plantilla por categoría.**
   - Lo importante son las **propiedades**, y siempre la propiedad `categories`, que dice a qué categoría pertenece cada nota. Sin ella las vistas no funcionan.
   - **Cliente:** nombre (coincide con el título), tipo (individual o empresa), estado (prospect → activo → archivado), creado, último contacto, servicios contratados, localización, email, teléfono, web, proyectos relacionados, factura y justificante de transferencia (como PDF enlazado) y un enlace a su plantilla.
   - **Servicio:** categoría, tipo (análisis, formación, producto, auditoría…), estado (activo, en pruebas, deshabilitado), creado, modelo de precio, rango de precios, clientes, proyectos y descripción (objetivos, para quién es, qué incluye, fases).
   - **Reunión:** tres plantillas.
     - «Discovery call» (una por servicio, con las preguntas para entender el problema y ver si el servicio encaja);
     - variante por servicio;
     - seguimiento periódico.
3. **Una «base» (vista de base de datos) por categoría.**
   - Filtra por `categories` y excluye las notas cuyo nombre contiene «template».
   - Elige qué columnas (propiedades) se ven.
   - Define vistas por estado: clientes activos o archivados, servicios activos o desactivados, reuniones por tipo…
4. **Una nota de categoría por cada una**, en una carpeta «Categorías». Lleva incrustadas las vistas de su base: es el «panel» de esa categoría.
5. **Identificar las vistas que necesita cada uno**, y crearlas.
6. **Flujo de principio a fin con dos clientes ficticios:**
   1. Los servicios existen antes que los clientes.
   2. Se crea el cliente desde su plantilla y se le asigna el servicio que pide.
   3. Se crea la reunión de descubrimiento, enlazada al cliente, y se toman notas.
   4. **Un agente (Claude Code) genera desde esas notas un borrador de propuesta**, siguiendo cómo hace las propuestas el autor. La persona lo revisa y lo envía.
   5. Si el cliente acepta, su estado pasa de prospect a activo.
   6. Se crean las reuniones de seguimiento y el proyecto.

**Buenas prácticas que se llevan a TLS:**
- **El cliente es el nodo central.** Desde su ficha se ven todas sus reuniones, proyectos, propuestas y facturas.
  - En Obsidian hay que crear cada nota desde la del cliente o instalar DataView.
  - **En TLS:** la ficha de cliente muestra sola todo lo que la enlaza (backlinks tipados por relación) y tiene botones «Nueva reunión / propuesta / proyecto / factura» que crean la nota ya enlazada.
- **Nombres estándar para las notas** (p. ej. «Reunión de seguimiento 1 · Juan · AAAA-MM-DD»). En TLS los pone la plantilla, no la persona.
- **Propiedades de lista con enlaces** para relaciones de muchos a muchos (cliente ↔ servicios ↔ proyectos), con **la misma propiedad reutilizada entre tipos**.
- **Estados como ciclo de vida** (prospect → activo → archivado). Archivar no es borrar: se conserva la base de clientes históricos.
- **Plantillas de reunión con preguntas guía por servicio**, sobre todo la de descubrimiento.
- **Vistas por estado y por tipo**, encima de una misma colección.
- **La IA prepara el borrador y la persona revisa y envía** (coincide con nuestra regla «ninguna salida sin aprobación»).
- **Lo que en Obsidian exige plugins** (DataView, Templater, nombres automáticos), **TLS lo trae de serie y sin configurar.** Este es el valor diferencial para un público no técnico.

**Choques con TLS:**
- **Carpetas.** Kepano usa pocas carpetas y clasifica por categorías; TLS usa carpetas por área, que es una decisión de Manu. Encaje: el tipo (`tls_type`) cumple el papel de la categoría, y en cada colección (Contactos, Oportunidades, Proyectos…) su nota índice cumple el de la «nota de categoría» con sus vistas.
- **Factura y justificante.** Kepano los enlaza como PDF sueltos en la ficha. En TLS la factura es un documento con su plantilla y su fila en `emitidas.csv`, y el justificante sale de la conciliación con el banco.

## Vídeo 2 · «Mi método para crear SISTEMAS con IA que hacen el trabajo por ti» (Nico CMW, 12:31)

**Definición.** Un sistema de IA es **una carpeta** con cinco cosas:
1. la tarea;
2. referencias de cómo debe quedar;
3. instrucciones (los pasos);
4. las herramientas que necesita la IA;
5. una forma de comprobar el resultado.

La IA es el «brazo ejecutor»: la persona decide qué y cómo, e itera.

**Método:**
1. **Descomponer la tarea:** qué entra (insumos), qué debe salir (entregable), restricciones y qué herramientas faltan (en su ejemplo, transcripción con Whisper). Vale igual para cualquier tarea, por ejemplo «descargar las facturas de las suscripciones del mes y pasarlas a contabilidad, sin repetir».
2. **Organizar la carpeta del sistema:**
   - un fichero de instrucciones generales que la IA lee siempre (`AGENTS.md` o `CLAUDE.md`);
   - `referencias/`;
   - `proyectos/` (una subcarpeta por ejecución);
   - `plantillas/`;
   - las herramientas (scripts).
3. **Los ejemplos son lo más importante.** Se le da una referencia y primero se le pide que **la replique**, hasta clavarla.
4. **Primera ejecución real**, y **se itera hasta que el resultado sea el correcto**.
5. **«Convierte lo aprendido en esta conversación en skills»:** los errores y aciertos se guardan en el sistema para no repetirlos.
6. **El sistema mejora con cada proyecto**, como una bola de nieve. Cuando aparece un modelo mejor, se rehace.

**Buenas prácticas que se llevan a TLS:**
- **La ficha de sistema de TLS ya coincide en la estructura** (Para qué · Cuándo se usa · Pasos · Quién lo hace · Rutina · Qué deja hecho). Se amplía con:
  - **Entradas** (qué necesita);
  - **Salida esperada y criterio de «bien hecho»** (cómo se comprueba);
  - **Referencias y ejemplos** (enlaces a 1–3 ejemplos buenos);
  - **Herramientas** (qué conexiones o MCP usa);
  - **Aprendizajes** (lo que el asistente ha ido aprendiendo, con fecha).
- **Cada sistema tiene su carpeta de ejemplos y de ejecuciones.** En TLS, las ejecuciones son los proyectos y las tareas que enlazan al sistema, y los ejemplos son los activos marcados como «referencia».
- **Primero replicar un buen ejemplo y después delegar.** Encaja con la escalera de TLB (persona → asistida → supervisada → autónoma) y con la regla «un proceso hecho 3 veces se escribe antes de la cuarta».
- **Cerrar cada ejecución con «¿qué aprendimos?»** y que se guarde en el sistema. En TLS es una propuesta del asistente para mejorar la ficha del sistema, que tú apruebas, no un cambio silencioso.
- **El entregable se comprueba** con criterios escritos antes de ejecutar (como la meta y la alerta de un KPI, escritas antes de ver el dato).
- **Mensaje para el empresario no técnico:** «un sistema es una carpeta con el qué, el cómo, ejemplos y una forma de comprobarlo», sin jerga.
