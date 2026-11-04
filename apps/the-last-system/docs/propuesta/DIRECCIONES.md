# Seis direcciones de diseño para The Last System

> **Qué es esto.** Seis maneras muy distintas de pintar la misma app. Todas sirven para la app entera, todas
> son de consumo masivo, limpias y accesibles (WCAG 2.2 AA) y ninguna se parece a Obsidian ni a Multica.
> Por dentro la app es la misma en las seis: lee tu carpeta, reescribe los enlaces al renombrar, tiene módulos
> que se encienden y una barra lateral que se personaliza. Lo que cambia es cómo se ve y cómo se siente.
>
> **Cómo se eligen.** Cada dirección se maqueta con el mismo guion (`GUION-MAQUETAS.md`): los mismos datos de
> Asesoría Ribera, la misma barra lateral y las mismas tres pantallas (Hoy, Ventas y Documento). Eliges una y
> se aplica a las plantillas, a los sistemas y a todas las pantallas.
>
> **Estado:** propuesta para elegir · 22/10/2026 · no cambia nada en la app ni en tu carpeta.
>
> **Base:** `SISTEMAS.md` (estructura, sistemas, vistas, módulos y barra lateral), `PLAN.md` §6, el informe de
> referencias de apps de consumo, el método Kepano y el vídeo de Nico CMW. Los contrastes están calculados con
> la fórmula de WCAG 2.x, no estimados. No hay datos de clientes reales: todo sale de Asesoría Ribera, que es
> ficticia.

---

## 0. En una página

| # | Dirección | En una frase | Cubre | Lo que la hace distinta |
|---|---|---|---|---|
| 1 | **Mosaico** | La marca The Last tal cual, en módulos que se mueven y se ocultan como los widgets del iPhone | Fiel a la marca | Mosaico de piezas redondeadas; el módulo que más importa, en magenta |
| 2 | **Saldo** | Tu empresa como una app de banco: una cifra enorme que se recorre con el dedo, una línea y filas | Trade Republic y Revolut | Negro puro, la cifra rueda al recorrer la gráfica, un fondo de color por área |
| 3 | **Cristal** | Una app más de tu Mac: navegación de cristal, contenido limpio y resúmenes como los de Salud | Apple nativa | Liquid Glass, SF Pro, radios concéntricos, listas agrupadas |
| 4 | **Gaceta** | Cada mañana, la portada del periódico de tu empresa | Editorial y tipográfica | Serifa grande, reglas finas, columnas y gráficas de prensa económica |
| 5 | **Sobremesa** | Una mesa tranquila con alguien que te ayuda: cálida, redondeada y con objetos ilustrados | Cálida y humana | Crema y frambuesa, un objeto por área, frases que te hablan |
| 6 | **Póster** | La marca a todo volumen: cifras gigantes, rejilla dura y un solo bloque magenta por pantalla | Atrevida | Ángulos rectos, letra ancha, sin sombras, tramas por área |

**Qué mirar cuando veas las maquetas:**
1. ¿Entiendes en 5 segundos qué tienes que hacer hoy?
2. ¿La factura se lee igual de bien a la izquierda (texto) que a la derecha (pantalla)?
3. ¿Te apetece abrirla cada mañana? ¿Te cansaría a las tres semanas?
4. ¿Personalizar la barra lateral se entiende sin explicación?
5. ¿Se nota que es The Last sin ver el logo?

---

## 1. Lo que es igual en las seis

Estas reglas no dependen de la dirección que elijas. Las maquetas las cumplen todas, así que la comparación es
solo de aspecto y sensación.

### 1.1 El mapa no cambia

El rediseño de Trade Republic de 2023 se criticó porque sus clientes perdieron las vistas de siempre. Aquí
cambia la estética, no el mapa:
- **El orden de la barra:** Hoy · Decisiones · Tareas · las 6 áreas · Asistentes · Carpeta · Recientes.
- **Los atajos:** ⌘1–3 para Hoy, Decisiones y Tareas; ⌘4–9 para las áreas; ⌘K para buscar y hacer; ⌘J para
  Mika; ⌘E para ver como texto.
- **Los nombres:** los del glosario (`PLAN.md` §6.9). Ninguna dirección inventa palabras nuevas.
- **La pantalla por defecto es excelente sin tocar nada.** La personalización vive detrás del modo edición
  (lección de Arc y Dia).

### 1.2 La barra lateral funciona igual

El comportamiento es el de `SISTEMAS.md` §5.10. Cada dirección solo decide cómo se ve.

| Qué | Cómo funciona en las seis |
|---|---|
| Entrar en modo edición | Mantener pulsado un elemento 0,4 s · clic derecho › «Editar barra lateral» · Visualización › Personalizar barra lateral · botón «Editar» al pasar por la cabecera |
| Reordenar | Arrastrar arriba o abajo; los demás se apartan |
| **Ocultar** | Arrastrar fuera de la barra más de 40 pt: aparece el rótulo «Ocultar»; al soltar, desaparece con su animación y sale «Ocultaste X · Deshacer» durante 6 s. También con el «−» |
| Bandeja «Ocultos» | Al pie del modo edición. Cada elemento se puede devolver arrastrándolo o con «Mostrar» |
| **Indentar** | Arrastrar a la derecha más de 24 pt mientras se mueve: queda bajo el de arriba. Dos niveles como máximo |
| Agrupar | Soltar un elemento sobre otro crea un grupo con nombre editable |
| Fijar | Arrastrar a la fila de favoritos (solo iconos, 6 como máximo) |
| Sin arrastrar (obligatorio) | Menú contextual: Subir · Bajar · Meter en grupo · Sacar del grupo · Fijar · Ocultar. Atajos ⌥⌘↑ ⌥⌘↓ (mover) y ⌘] ⌘[ (indentar). Las mismas acciones con nombre en VoiceOver |
| Fijo | **Hoy no se puede ocultar** |
| Ocultar no es apagar | Lo oculto sigue funcionando y se encuentra con ⌘K. Apagar una función se hace en Módulos |
| Salir | «Listo», Escape o clic fuera de la barra |
| Pie de la barra | Sin nada importante: el interruptor de asistentes y «Ejemplo / Solo lectura» van en la barra de herramientas y en la barra de menús (guía de Apple) |

### 1.3 Módulos de inicio

- Hoy y el Resumen de cada área tienen **módulos**: rejilla de 4 columnas, tamaños Pequeño 1×1, Mediano 2×1,
  Grande 2×2 y Ancho 4×1, **8 como máximo**.
- «Editar inicio» funciona como el Centro de control del iPhone: «+ Añadir» abre una galería con buscador y
  categorías por área, «−» quita y el asa de la esquina cambia el tamaño. Sin arrastrar: clic derecho ›
  Tamaño y Mover antes o después.
- Cada módulo dice de dónde sale («Sale de 14 fichas») y tiene su estado vacío con botón («Sin dato: falta el
  extracto de octubre · Añadir extracto»). **Nunca un 0 falso.**
- Dentro de las listas siguen siendo filas, no tarjetas.

### 1.4 Gráficas

- **Periodos:** 1S · 1M · 3M · 1A · Todo, junto a una frase que resume la gráfica («La caja baja 902 € este
  mes: el martes se pagaron los impuestos del trimestre»).
- **Recorrer:** al pasar el puntero (o con ← y →), la cifra protagonista cambia al valor de ese punto y dice su
  fecha; al salir, vuelve a hoy. Arrastrando se ve la diferencia entre dos puntos.
- **Honestidad:** el tramo que no sale de un extracto lleva la etiqueta «Estimado». Una serie sin datos no se
  dibuja: se escribe qué falta.
- **Siempre** «Ver como tabla» y descripción para VoiceOver (`accessibilityChartDescriptor`).
- **Diferenciar sin color:** cada área tiene su forma de marcador en las gráficas: Dirección rombo, Ventas
  círculo, Entrega cuadrado, Finanzas triángulo, Marca estrella, Equipo cruz.
- Nada de 3D ni de tartas con más de 3 partes.

### 1.5 Documentos: un fichero, dos lecturas a la vez

Un documento (factura, ficha de sistema, contacto) es un `.md` que se lee bien en cualquier editor. En la app
se pinta como una pantalla con el mismo molde en las seis direcciones:

| En el fichero | En la app |
|---|---|
| Propiedades | Cabecera: como mucho 3 datos arriba, **1 dato protagonista**, hasta 4 secundarios y 4 auxiliares. El resto, en «Propiedades», plegado |
| `# Título` y la línea `> …` | Título y subtítulo |
| Cada `## Sección` | Un bloque que se pliega |
| Tablas | Filas que se tocan; la fila de totales destacada |
| `[falta: …]` | Una pastilla «Falta» con icono y texto; el documento no se emite mientras quede alguna |
| (según el tipo) | **Barra fija abajo** con la acción principal, «Vista previa PDF» y «Ver como texto» (⌘E) |

Dato protagonista: factura → total; ficha de sistema → su número clave frente a la meta; contacto → sus
iniciales o su logo.

En la pantalla Documento de las maquetas se ven **las dos lecturas lado a lado**: el texto a la izquierda y la
pantalla a la derecha. Al pasar por un bloque de la derecha se resaltan sus líneas a la izquierda.

### 1.6 Accesibilidad (WCAG 2.2 AA)

| Qué | Regla |
|---|---|
| Contraste | Texto 4,5:1 como mínimo; iconos, bordes de control y foco 3:1. Todas las parejas de esta propuesta están calculadas |
| Color | **Nunca va solo:** siempre con icono y palabra |
| Tamaño de texto | Del 85 al **200 %** (cambio respecto al 85–130 % de `PLAN.md` §6.9, porque macOS no tiene Dynamic Type). Las filas pasan a dos líneas y los módulos se recolocan |
| Objetivos | 28 pt como mínimo, también el «−» y las asas |
| Foco | Anillo de 2 pt en el acento de la dirección, nunca tapado por las barras fijas |
| Arrastre | Siempre hay alternativa con un clic (menú, botones, atajos y VoiceOver) |
| Ajustes del sistema | «Reducir movimiento» (fundidos, sin temblor), «Reducir transparencia» (cristal sólido), «Aumentar contraste» (cada dirección dice qué cambia) |
| Ayuda | Mika (⌘J) y «¿Por qué?» siempre en el mismo sitio |

### 1.7 Color: áreas, estados y magenta

**Las áreas conservan su color en las seis:** Dirección violeta, Ventas verde, Entrega azul, Finanzas ámbar,
Marca magenta y Equipo rojo. Cada dirección cambia el tono, no el reparto.

**Dos versiones de cada color de área:**
- **Tinta** (≥4,5:1): para el nombre del área, iconos y texto.
- **Relleno** (≥3:1): para puntos, barras de 3 pt, series de gráfica e iconos con glifo blanco encima.

**Luminosidad.** Para que las áreas se distingan también en gris (o con daltonismo), se ordenan siempre igual
de más oscura a más clara: **Dirección → Equipo → Entrega → Marca → Ventas → Finanzas**. Las tablas de cada
dirección dan la luminosidad percibida (L*, de 0 negro a 100 blanco) y la separación mínima entre áreas. Con
seis colores y el contraste exigido no caben saltos grandes, así que la forma del marcador (§1.4) y el nombre
siempre acompañan.

**Estados.** Son comunes a las seis direcciones. Llevan tonos propios (verde azulado, naranja tostado, carmín)
para no confundirse con Ventas, Finanzas y Equipo, y siempre con su icono y su palabra:

| Estado | Icono | Claro | Oscuro | Peor contraste en las 6 direcciones |
|---|---|---|---|---|
| Bien (En ritmo, Hecho) | círculo con marca | `#00786E` | `#59C1B5` | 4,71 en claro · 7,88 en oscuro |
| Atención (En observación, vence pronto) | triángulo con exclamación | `#C33900` | `#FF946C` | 4,72 en claro · 7,86 en oscuro |
| Mal (En alerta, vencido, bloqueado) | octógono con aspa | `#D01C36` | `#FF928D` | 4,72 en claro · 7,90 en oscuro |
| Sin dato / Sin meta | círculo con guion | `#6A6A70` | `#B0B0B6` | 4,71 en claro · 7,88 en oscuro |

**Magenta.** El de marca, `#E6007E`, funciona como relleno (blanco encima: 4,50:1, justo) pero no como texto
sobre gris claro (4,03) ni sobre gris oscuro (3,78). Por eso cada dirección da dos tonos: relleno y texto.
Cuando el área Marca y el acento coinciden en color, el área solo aparece como punto, barra o icono, y el
acento solo en la acción principal y la selección.

### 1.8 Lo que ninguna dirección hace

- Un árbol de ficheros como navegación principal (la Carpeta existe, pero es una pantalla más).
- Letra monoespaciada en la interfaz (solo en códigos y en «Ver como texto»).
- Paneles grises densos, pestañas de editor o barras de estado técnicas.
- Emojis, rachas que culpan o celebraciones fuera de hitos reales.
- Números inventados: «Sin dato» y «Sin meta» en vez de 0.

---

## 2. Mosaico — la marca, en módulos

**Idea.** Cada inicio es un mosaico de módulos de tamaños distintos que se mueven, se ocultan y cambian de
tamaño como los widgets del iPhone; el módulo que más importa va en magenta.

**Para quién y por qué encaja.** Es la marca The Last sin traducir (magenta `#E6007E`, Space Grotesk, DM Sans
y JetBrains Mono) y la respuesta más directa a «módulos estables arrastrando o pudiendo ocultar». Para quien
quiere ver su empresa como un cuadro de mando ordenado y tocar cada pieza.

**Referentes.** Widgets y Centro de control de iOS 18 (edición, tamaños, galería) · app Casa (mosaicos por
estancia) · tarjetas de página de Craft · las portadas por área del manual de marca de The Last.

**En qué no se parece a Obsidian ni a Multica.** No hay árbol ni paneles grises: la pantalla es un mosaico de
piezas grandes, una cifra por pieza y mucho aire.

### 2.1 Color

| Uso | Claro | Contraste en claro | Oscuro | Contraste en oscuro |
|---|---|---|---|---|
| Fondo | `#F1F1F4` | — | `#000000` | — |
| Superficie | `#FFFFFF` | — | `#141416` | — |
| Texto | `#111114` | 16,72 / 18,85 | `#F4F4F6` | 19,12 / 16,75 |
| Texto secundario | `#5B5B66` | 5,95 / 6,70 | `#A1A1AB` | 8,20 / 7,19 |
| Separador | `#E2E2E8` | 1,29 sobre superficie (línea; nunca es la única pista) | `#2A2A30` | 1,29 sobre superficie (línea; nunca es la única pista) |
| Acento (relleno) | `#E6007E` | texto `#FFFFFF` encima: 4,50 · como gráfico y foco: 3,99 / 4,50 | `#E6007E` | texto `#FFFFFF` encima: 4,50 · como gráfico y foco: 4,67 / 4,09 |
| Acento (texto y enlaces) | `#C4006B` | 5,23 / 5,90 | `#FF3D9A` | 6,39 / 5,60 |

Contraste «a / b»: sobre el fondo / sobre la superficie. Mínimos: 4,5:1 texto; 3:1 gráficos, bordes de control y anillo de foco.

- El blanco sobre `#E6007E` pasa justo (4,50:1): el texto de los botones va en 13 pt seminegrita o más.
- **Aumentar contraste:** el relleno pasa a `#C4006B` (5,90:1 con blanco) y los mosaicos ganan un borde de
  1 pt en `texto` al 20 %.

| Área | Tinta en claro (texto, iconos) | Relleno en claro (puntos, barras, series) | Tinta en oscuro | Relleno en oscuro |
|---|---|---|---|---|
| Dirección | `#5202B3` · 9,23:1 · L* 27 | `#5B11BC` · 8,28:1 · L* 30 | `#BB7EFF` · 6,61:1 · L* 64 | `#9D52FB` · 4,41:1 · L* 52 |
| Ventas | `#007650` · 5,02:1 · L* 44 | `#019465` · 3,43:1 · L* 54 | `#4DDEA4` · 10,78:1 · L* 80 | `#3BD096` · 9,33:1 · L* 75 |
| Entrega | `#005797` · 6,63:1 · L* 36 | `#0067B2` · 5,20:1 · L* 43 | `#7FB2FF` · 8,51:1 · L* 72 | `#479EFD` · 6,64:1 · L* 64 |
| Finanzas | `#9A6100` · 4,56:1 · L* 46 | `#C37C00` · 3,00:1 · L* 58 | `#FFC788` · 12,07:1 · L* 84 | `#FFB961` · 10,83:1 · L* 80 |
| Marca | `#B90064` · 5,74:1 · L* 40 | `#DF017A` · 4,21:1 · L* 48 | `#FF9FBF` · 9,61:1 · L* 76 | `#FF83B0` · 8,00:1 · L* 70 |
| Equipo | `#9B001A` · 7,73:1 · L* 32 | `#AF001E` · 6,56:1 · L* 36 | `#FF8075` · 7,53:1 · L* 68 | `#F94D4B` · 5,42:1 · L* 58 |

Contraste: el peor de fondo y superficie. Separación mínima de luminosidad entre dos áreas (ΔL*): rellenos 4 en claro y 5 en oscuro; tintas 3 y 4.

Cada área se dibuja como un icono de app: glifo blanco sobre un cuadrado redondeado de su relleno (en oscuro,
glifo negro sobre el relleno oscuro).

### 2.2 Tipografía

| Uso | Familia (Google Fonts) | Peso | Tamaño |
|---|---|---|---|
| Cifra protagonista | Space Grotesk, cifras tabulares | 600 | 56 pt en Hoy · 40 pt en módulo grande · 28 pt en pequeño |
| Título de pantalla | Space Grotesk | 700 | 28 pt |
| Título de módulo y de sección | Space Grotesk | 500 | 15 pt |
| Interfaz y texto | DM Sans (óptico 14) | 400 · 500 · 600 | 13 pt en filas · 15 pt para leer |
| Rótulos pequeños | DM Sans, mayúsculas, +4 % de espaciado | 600 | 11 pt |
| Códigos (T-0041, FIN-AR, F-2026-0014) | JetBrains Mono | 400 · 500 | 12 pt |

### 2.3 Forma, materiales y densidad

- **Radios:** ventana 26 · mosaico 22 · bloque interior 14 · fila 10 · botones y chips en cápsula.
- **Espacio:** 12 pt entre mosaicos, 20 pt de margen.
- **Sombras:** en claro, muy suaves (`0 1px 2px` al 4 % y `0 6px 16px` al 6 % de `#111114`); en oscuro, sin
  sombra y con borde de 1 pt blanco al 8 %.
- **Materiales:** todo sólido; sin cristal.
- **Densidad:** media. Filas de 44 pt; un módulo lleva una cifra y como mucho 5 filas.

### 2.4 Iconografía

SF Symbols en peso medio y de contorno, 17 pt en la barra y 15 pt en filas. Las áreas, en relleno (fill)
dentro de su cuadrado de 24 pt con radio 7. En la maqueta web: Phosphor «regular» (trazo de 1,5 a 24 px) y
«fill» para las áreas.

### 2.5 Gráficas

- Línea de 2,5 pt con extremos redondos en el acento, con relleno degradado del acento del 24 % al 0 %.
- Tres líneas guía punteadas en `separador`, eje x con 4 etiquetas y un halo en el último punto.
- **Al pasar:** regla vertical de 1 pt, punto con anillo blanco de 2 pt y una pastilla flotante con fecha e
  importe; la cifra del módulo cambia y su rótulo dice la fecha («mar 20 oct»).
- **Al arrastrar:** el tramo se cubre de acento al 12 % y la pastilla dice la diferencia.
- **Periodos:** control segmentado en cápsula bajo el título del módulo.
- **Barras** (embudo, horas): radio 6 arriba. **Estimado:** línea discontinua 4–4 con el rótulo «Estimado».

### 2.6 Barra lateral

- Columna sólida de 248 pt sobre la superficie. Arriba, la empresa: monograma «AR» en un cuadrado magenta de
  28 pt, «Asesoría Ribera» y el chip «EJEMPLO».
- Favoritos: cuadrados de 36 pt con su icono.
- Filas-pastilla de 36 pt: icono de app del área, nombre y estado en `secundario`. **Seleccionada:** pastilla
  rellena de magenta con texto blanco.
- **Modo edición:** los elementos tiemblan (±1,5°); cada uno lleva a la izquierda un «−» en un círculo de 20 pt
  (zona de toque de 28 pt) y a la derecha el asa «≡». Arriba, «Listo» en cápsula magenta. Hoy lleva un
  candado pequeño en lugar del «−».
- **Arrastrar fuera:** la fila se despega como un mosaico pequeño con sombra; a 40 pt de la barra se queda al
  60 % y aparece la pastilla «Ocultar» (fondo `texto`, letra `superficie`). Al soltar, se encoge y se deshace
  en seis puntos magenta (0,3 s).
- **Ocultos:** bandeja con borde discontinuo y radio 14 al pie, con lo oculto como chips con icono y «Mostrar».
- **Indentar:** aparece una guía vertical de 2 pt en el color del padre y el hijo se mete 20 pt. Un grupo es
  una pastilla que se despliega, con el nombre editable.

### 2.7 Módulos

- Mosaicos en la rejilla de 4 columnas. Cada uno: arriba el icono del área (16 pt) y el nombre en rótulo
  pequeño; en medio la cifra; debajo una línea de contexto; al pie «Sale de…» en 11 pt.
- **Un solo bloque magenta por inicio.** En Hoy ese papel lo tiene el foco; en las áreas, el módulo de su
  número clave.
- **Editar inicio:** tiemblan, «−» arriba a la izquierda, asa de tamaño abajo a la derecha (28 pt), «+ Añadir»
  abre la galería en una hoja. Un módulo vacío conserva su tamaño y dice qué falta.

### 2.8 Documentos

- **Factura:** arriba, un mosaico ancho en magenta con «290,40 €» en blanco a 56 pt y «Borrador · se numera al
  emitir»; a su lado, dos mosaicos pequeños (Para y Vence). Debajo, un mosaico blanco con Conceptos y otro con
  Totales, donde la fila Total va en Space Grotesk 20 pt. Línea de estados como 4 puntos unidos: Borrador →
  Emitida → Enviada → Cobrada. Barra fija: cápsula magenta «Revisar y emitir», «Vista previa PDF» y «Ver como
  texto».
- **Ficha de sistema:** el número clave en un mosaico 2×1 con su minigráfica; «Cómo va» como 5 mosaicos
  pequeños (uso, bien a la primera, tiempo, frescura, sin ti); los pasos como un carril vertical de
  minimosaicos con el icono de quién lo hace y el modo en una pastilla; candado en los pasos «Siempre con tu OK».
- **Texto plano (⌘E):** JetBrains Mono 13 pt sobre la superficie; propiedades en `secundario`, títulos en
  negrita, enlaces en acento y `[falta: …]` subrayado en magenta.

### 2.9 Las tres pantallas

- **Hoy:** «Buenos días, Elena» a 28 pt y la frase del día; el foco como mosaico ancho magenta con el botón
  blanco; «Pide tu decisión» como tres mosaicos en fila, cada uno con las opciones 1·2·3 en chips; debajo, la
  rejilla de módulos.
- **Ventas:** la cabecera del área como mosaico ancho (icono, pregunta y la cifra «2» a 56 pt en magenta);
  tablero con columnas en bandejas de `fondo` y tarjetas blancas de radio 14; al arrastrar, la tarjeta se
  levanta e inclina 2°; si la sueltas sobre Ganada, la columna se cubre de trama y sale el aviso. Seguimientos
  en una columna derecha de 320 pt.
- **Documento:** mitad y mitad; el texto en un mosaico a la izquierda y la pantalla a la derecha; pestañas en
  control segmentado en cápsula.

### 2.10 Movimiento, riesgos y coste

- **Movimiento:** muelles (respuesta 0,35 s); al abrir un módulo se amplía hasta ocupar la pantalla. Con
  «Reducir movimiento», fundidos.
- **Riesgos:** acabar con «todo a la vez» (por eso el tope de 8); tantas piezas redondeadas pueden parecer
  genéricas si se pierde la tipografía de marca.
- **Coste de construirla:** medio. La rejilla con cambio de tamaño y la galería son propias; el resto es
  estándar.

---

## 3. Saldo — tu empresa como una app de banco

**Idea.** Cada pantalla es una cifra enorme que se recorre con el dedo, una línea a sangre sin ejes y una
lista de filas; cada área tiene su propio fondo de color, como las cuentas de Revolut.

**Para quién y por qué encaja.** Es la estética que ya te gustó (Trade Republic), llevada al extremo con lo
mejor de Revolut 10: negro puro, cifras que ruedan y un fondo por área para saber dónde estás sin leer. Para
quien piensa su empresa en dinero y quiere responder «¿hay caja?» en un segundo.

**Referentes.** Trade Republic (cifra, gráfica y lista; línea de referencia punteada; recorrer la gráfica
cambia la cifra) · Revolut 10 (fondos por cuenta, widgets en el inicio, botones en pastilla) · Stripe (la
etiqueta «Estimado»).

**En qué no se parece a Obsidian ni a Multica.** No hay paneles ni bordes: negro, una cifra, una línea y filas
a todo el ancho.

### 3.1 Color

Saldo vive en oscuro por defecto.

| Uso | Claro | Contraste en claro | Oscuro | Contraste en oscuro |
|---|---|---|---|---|
| Fondo | `#FFFFFF` | — | `#000000` | — |
| Superficie | `#F4F4F6` | — | `#121214` | — |
| Texto | `#000000` | 21,00 / 19,12 | `#FFFFFF` | 21,00 / 18,71 |
| Texto secundario | `#6A6A70` | 5,37 / 4,89 | `#8F8F98` | 6,55 / 5,84 |
| Separador | `#E6E6EA` | 1,13 sobre superficie (línea; nunca es la única pista) | `#232328` | 1,20 sobre superficie (línea; nunca es la única pista) |
| Botón principal (relleno) | `#000000` | texto `#FFFFFF` encima: 21,00 | `#FFFFFF` | texto `#000000` encima: 21,00 |
| Acento (relleno) | `#E6007E` | texto `#FFFFFF` encima: 4,50 · como gráfico y foco: 4,50 / 4,10 | `#FF3D9A` | texto `#000000` encima: 6,39 · como gráfico y foco: 6,39 / 5,69 |
| Acento (texto y enlaces) | `#C4006B` | 5,90 / 5,37 | `#FF3D9A` | 6,39 / 5,69 |

Contraste «a / b»: sobre el fondo / sobre la superficie. Mínimos: 4,5:1 texto; 3:1 gráficos, bordes de control y anillo de foco.

- **El botón principal es tinta invertida** (blanco con letra negra en oscuro; negro con letra blanca en
  claro), como en Trade Republic. El magenta queda para lo que eliges y recorres: el periodo activo, el punto
  de la gráfica, el foco del teclado y los interruptores.
- **Aumentar contraste:** el texto secundario pasa a `#B5B5BD` en oscuro y a `#55555B` en claro, y las filas
  ganan separador visible.

**Cabecera de cada área (el «fondo de cuenta»).** Un degradado que arranca en el color del área y se funde en
el fondo:

| Área | Cabecera en oscuro (degradado: de este color a `#000000`) | Texto blanco encima | Cabecera en claro (de este color a `#FFFFFF`) | Texto negro encima |
|---|---|---|---|---|
| Dirección | `#470095` | 12,34 | `#F4E6FF` | 17,61 |
| Ventas | `#003D29` | 12,36 | `#CBF4E0` | 17,56 |
| Entrega | `#003662` | 12,32 | `#E3EBFF` | 17,59 |
| Finanzas | `#4A3000` | 12,25 | `#FFE7CC` | 17,55 |
| Marca | `#6D0035` | 12,34 | `#FFE4EB` | 17,55 |
| Equipo | `#700012` | 12,37 | `#FFE5E2` | 17,56 |

El texto va siempre sobre la parte más saturada del degradado; el contraste de la tabla es el peor caso (el color de arranque).

| Área | Tinta en claro (texto, iconos) | Relleno en claro (puntos, barras, series) | Tinta en oscuro | Relleno en oscuro |
|---|---|---|---|---|
| Dirección | `#5500B0` · 9,50:1 · L* 27 | `#5E00C1` · 8,51:1 · L* 30 | `#BE7DFF` · 6,74:1 · L* 64 | `#A14EFF` · 4,50:1 · L* 52 |
| Ventas | `#007653` · 5,14:1 · L* 44 | `#019368` · 3,56:1 · L* 54 | `#3EDFA5` · 10,96:1 · L* 80 | `#27D198` · 9,50:1 · L* 75 |
| Entrega | `#005797` · 6,80:1 · L* 36 | `#0067B2` · 5,34:1 · L* 43 | `#7FB2FF` · 8,66:1 · L* 72 | `#479EFD` · 6,75:1 · L* 64 |
| Finanzas | `#986500` · 4,56:1 · L* 47 | `#BF8100` · 3,01:1 · L* 59 | `#FFC87E` · 12,31:1 · L* 84 | `#FFB94E` · 10,96:1 · L* 80 |
| Marca | `#BA005F` · 5,88:1 · L* 40 | `#E00074` · 4,32:1 · L* 48 | `#FFA0BC` · 9,81:1 · L* 76 | `#FF84AC` · 8,15:1 · L* 70 |
| Equipo | `#9B001C` · 7,93:1 · L* 32 | `#AF0021` · 6,72:1 · L* 36 | `#FF8077` · 7,67:1 · L* 68 | `#FB4A4C` · 5,51:1 · L* 58 |

Contraste: el peor de fondo y superficie. Separación mínima de luminosidad entre dos áreas (ΔL*): rellenos 5 en claro y 5 en oscuro; tintas 3 y 4.

### 3.2 Tipografía

| Uso | Familia (Google Fonts) | Peso | Tamaño |
|---|---|---|---|
| Cifra protagonista | Manrope, cifras tabulares, −2 % de espaciado | 800 | 72 pt en Hoy y áreas · 44 pt en documentos. Los céntimos al 55 % y alineados arriba: «18.719,45 €» |
| Títulos | Manrope | 700 | 22 pt |
| Interfaz | Manrope | 500 · 600 | 15 pt el título de fila · 13 pt el detalle |
| Rótulos | Manrope | 600 | 12 pt |
| Códigos | JetBrains Mono | 500 | 12 pt |

### 3.3 Forma, materiales y densidad

- **Radios:** hojas 28 · widgets 20 · botones en cápsula de 50 pt de alto · filas sin caja, a todo el ancho,
  con separador sangrado 64 pt.
- **Sin sombras.** La profundidad sale del brillo (la superficie es un poco más clara que el fondo) y del
  degradado de área.
- **Cristal** solo en la cabecera fija al desplazar: desenfoque con negro al 70 %; con «Reducir
  transparencia», negro sólido.
- **Densidad:** baja-media. Filas de 64 pt con dos líneas (título y detalle) y la cifra a la derecha.

### 3.4 Iconografía

SF Symbols seminegrita y rellenos, dentro de círculos de 36 pt de `superficie`, como los comercios de un
extracto. El área: glifo en su tinta dentro de un círculo del color de su cabecera. Maqueta web: Phosphor
«fill».

### 3.5 Gráficas

- Una línea de 2 pt en `texto`, sin ejes ni rejilla, de borde a borde. Una línea horizontal punteada marca el
  valor al empezar el periodo (como el precio de apertura de Trade Republic).
- La variación se escribe siempre con signo y flecha: «−901,90 € · −4,6 %». El tramo bajo la referencia no
  cambia de color: el color nunca va solo.
- **Al pasar o deslizar:** la cifra grande rueda dígito a dígito hasta el valor del punto; encima aparece la
  fecha («mar 20 oct») y el motivo en una línea («Modelos 303 y 111 del 3T · −945,20 €»). Punto magenta de
  8 pt con halo, vibración leve al encajar en cada día y, al soltar, vuelta a hoy.
- **Al arrastrar:** tramo con velo magenta al 16 % y la diferencia arriba.
- **Periodos:** pastillas bajo la gráfica; la elegida, rellena de acento.
- **Estimado:** la línea pasa a puntos y se lee «Estimado hasta el 30 jun».

### 3.6 Barra lateral

- Negra, sin bordes, de 232 pt. Arriba, la empresa como una «cuenta»: círculo con el monograma, nombre y
  flecha para cambiar. Favoritos: círculos de 40 pt, como los accesos rápidos de Revolut.
- Filas de 40 pt: icono en círculo, nombre y, a la derecha, un dato vivo en `secundario` (Decisiones «3»,
  Ventas «2 quietas» con triángulo, Finanzas «6,0 meses»). **Seleccionada:** texto blanco en 600 y una barra de
  3 pt del color del área a la izquierda.
- **Modo edición, sin temblor** (más sobrio, como una app de banco): los elementos se separan 4 pt y aparecen
  el «−» a la izquierda y el asa a la derecha; «Listo» en pastilla blanca arriba.
- **Arrastrar fuera:** la fila se convierte en una pastilla blanca flotante; pasados 40 pt aparece debajo la
  zona «Ocultar» con un ojo tachado; al soltar, la pastilla se hunde y se funde (0,25 s).
- **Ocultos:** sección plegable al final, «Ocultos · 2», con «Mostrar» en cada fila.
- **Indentar:** el hijo se mete 24 pt, su icono baja a 24 pt y una línea de 1 pt lo une al padre.

### 3.7 Módulos

Widgets de radio 20 en `superficie`, con una cifra y una minigráfica o 3 filas. «Editar inicio» al final de la
lista, como en Revolut: las tarjetas muestran «−» y asa; la galería se abre como hoja.

### 3.8 Documentos

- **Factura, como el detalle de un movimiento:** cabecera con el degradado de Finanzas; en el centro, el
  círculo con las iniciales del cliente («AN»), «Arquitectura Nexo SLP», el total a 44 pt y la pastilla
  «Borrador» con icono. Debajo, filas: Para · Oportunidad · Vence · Forma de pago; luego Conceptos y Totales
  con el importe a la derecha; al final, la línea de tiempo vertical Borrador → Emitida → Enviada → Cobrada.
  Barra fija con el botón blanco a todo el ancho «Revisar y emitir» y, encima, «Vista previa PDF» y «Ver como
  texto».
- **Ficha de sistema:** cabecera con el degradado de su área, el número clave en grande con su minigráfica
  recorrible y «Lo lleva Elena con el asistente Contable». Los pasos como filas: número, verbo, quién y, a la
  derecha, el modo en palabras con un chevron; candado en los de «Siempre con tu OK».
- **Texto plano:** JetBrains Mono 13 pt sobre negro; propiedades en `secundario`, títulos en blanco 700,
  enlaces en magenta.

### 3.9 Las tres pantallas

- **Hoy:** la frase del día en Manrope 700 a 28 pt; el foco como fila ancha con el botón blanco; las tres
  decisiones como filas con las opciones 1·2·3 en pastillas; el módulo de Caja con la cifra a 72 pt y la línea a
  sangre.
- **Ventas:** cabecera con el degradado verde, la cifra «2» enorme y «oportunidades quietas»; el tablero con
  columnas sin caja y tarjetas en `superficie` de radio 16 con el valor grande; al arrastrar, la tarjeta crece
  un 4 % y se ilumina; Ganada bloqueada se atenúa con un candado y el texto. Seguimientos debajo, como lista.
- **Documento:** texto a la izquierda en negro; pantalla a la derecha; pestañas como pastillas.

### 3.10 Movimiento, riesgos y coste

- **Movimiento:** cifras que ruedan (0,35 s), muelles cortos, vibración al encajar. Con «Reducir movimiento»,
  la cifra cambia sin rodar.
- **Riesgos:** es la más cercana a lo que ya había; el cambio radical lo marcan los fondos por área y la cifra
  que rueda. El negro puro cansa en lecturas largas (los documentos van sobre `#121214`). La gráfica sin ejes
  necesita «Ver como tabla» siempre a la vista.
- **Coste:** bajo-medio.

---

## 4. Cristal — una app más de tu Mac

**Idea.** La navegación flota en cristal sobre un contenido limpio; cada área es un resumen como el de Salud
(fijados, destacados en frase y tendencias), con formas que encajan unas dentro de otras.

**Para quién y por qué encaja.** Para quien quiere que la app parezca parte del Mac, como Notas, Salud o
Ajustes, y que se aprenda sola porque todo funciona como en el resto del sistema. Es la versión más literal de
«consumo masivo»: millones de personas ya saben usarla.

**Referentes.** macOS Tahoe 26 y su sistema de diseño (Liquid Glass, concentricidad) · Salud (Resumen:
Fijados, Destacados y Tendencias) · Fitness (Editar resumen) · Ajustes y Recordatorios (listas agrupadas) ·
Wallet (cabecera de pase).

**En qué no se parece a Obsidian ni a Multica.** Sin pestañas de editor ni paneles de complementos: títulos
grandes, listas agrupadas y cristal.

### 4.1 Color

| Uso | Claro | Contraste en claro | Oscuro | Contraste en oscuro |
|---|---|---|---|---|
| Fondo | `#F2F2F7` | — | `#000000` | — |
| Superficie | `#FFFFFF` | — | `#1C1C1E` | — |
| Texto | `#1D1D1F` | 15,08 / 16,83 | `#F5F5F7` | 19,29 / 15,63 |
| Texto secundario | `#636369` | 5,35 / 5,97 | `#A1A1A8` | 8,18 / 6,63 |
| Separador | `#D8D8DD` | 1,42 sobre superficie (línea; nunca es la única pista) | `#38383A` | 1,45 sobre superficie (línea; nunca es la única pista) |
| Acento (relleno) | `#D6006F` | texto `#FFFFFF` encima: 5,14 · como gráfico y foco: 4,60 / 5,14 | `#D6006F` | texto `#FFFFFF` encima: 5,14 · como gráfico y foco: 4,09 / 3,31 |
| Acento (texto y enlaces) | `#C4006B` | 5,29 / 5,90 | `#FF5AAA` | 7,29 / 5,91 |

Contraste «a / b»: sobre el fondo / sobre la superficie. Mínimos: 4,5:1 texto; 3:1 gráficos, bordes de control y anillo de foco.

- El acento es el color de acento de la app en un magenta algo más profundo que el de marca (`#D6006F`), para
  que el blanco encima pase con margen (5,14:1).
- **Cristal:** la barra lateral y la barra de herramientas usan el cristal normal de Tahoe; detrás, un velo del
  color del área al 8 % para que el cristal tenga algo que refractar. Con «Reducir transparencia», sólido:
  `#ECECF0` en claro y `#1C1C1E` en oscuro. En macOS 15 (el mínimo de la app) se ve con el material translúcido
  anterior.
- **Aumentar contraste:** borde de 1 pt en `texto` al 20 % en todo el cristal.

| Área | Tinta en claro (texto, iconos) | Relleno en claro (puntos, barras, series) | Tinta en oscuro | Relleno en oscuro |
|---|---|---|---|---|
| Dirección | `#670096` · 9,33:1 · L* 27 | `#700DA0` · 8,35:1 · L* 30 | `#D172FF` · 6,13:1 · L* 64 | `#AE51DD` · 4,07:1 · L* 52 |
| Ventas | `#00782C` · 5,05:1 · L* 44 | `#009639` · 3,47:1 · L* 54 | `#54E170` · 10,03:1 · L* 80 | `#43D263` · 8,62:1 · L* 75 |
| Entrega | `#00569B` · 6,71:1 · L* 36 | `#0166B6` · 5,26:1 · L* 43 | `#85B1FF` · 7,88:1 · L* 72 | `#4F9CFF` · 6,10:1 · L* 64 |
| Finanzas | `#A45E00` · 4,50:1 · L* 47 | `#CD7700` · 3,02:1 · L* 58 | `#FFC794` · 11,22:1 · L* 84 | `#FFB874` · 10,01:1 · L* 80 |
| Marca | `#B90064` · 5,80:1 · L* 40 | `#DF017A` · 4,25:1 · L* 48 | `#FF9FBF` · 8,88:1 · L* 76 | `#FF83B0` · 7,39:1 · L* 70 |
| Equipo | `#9C000C` · 7,78:1 · L* 32 | `#B00010` · 6,60:1 · L* 37 | `#FF816B` · 6,97:1 · L* 68 | `#FF4637` · 5,01:1 · L* 58 |

Contraste: el peor de fondo y superficie. Separación mínima de luminosidad entre dos áreas (ΔL*): rellenos 4 en claro y 5 en oscuro; tintas 3 y 4.

Las áreas se dibujan como en Salud: glifo blanco en un cuadrado redondeado de 22 pt de su relleno y el nombre
en su tinta.

### 4.2 Tipografía

| Uso | Familia | Peso | Tamaño |
|---|---|---|---|
| Títulos grandes (alineados a la izquierda, como Tahoe) | SF Pro Display (del sistema) | 700 | 34 pt |
| Cifras | SF Pro Rounded (del sistema), cifras tabulares | 600 | 48 pt en Hoy · 34 pt en módulos |
| Interfaz | SF Pro Text (del sistema) | 400 · 590 | 13 pt |
| Códigos | SF Mono (del sistema) | 400 | 12 pt |

SF Pro viene con macOS: no es de Google Fonts y no hay que incluirla. **En la maqueta web:** `system-ui` en el
Mac; si no está, Inter (Google Fonts) 400 · 500 · 600 · 700 con cifras tabulares; para las cifras redondeadas,
`ui-rounded` o, si no, Nunito 700.

### 4.3 Forma, materiales y densidad

- **Radios concéntricos:** ventana 26 → panel 20 → grupo de lista 12 → fila 10 → controles en cápsula.
- Listas agrupadas con margen (como Ajustes).
- **Sombras:** solo las del sistema bajo el cristal flotante.
- **Densidad:** media. Filas de 32 pt en la barra y de 44 pt en las listas; resúmenes con aire.

### 4.4 Iconografía

SF Symbols en peso regular con representación jerárquica en la interfaz y multicolor solo en estados; 17 pt.
Áreas: `safari`, `chart.line.uptrend.xyaxis`, `shippingbox`, `creditcard`, `sparkles` y `person.2` (a
comprobar en SF Symbols 7). Maqueta web: Phosphor «regular».

### 4.5 Gráficas

- Estilo de Swift Charts: línea de 2 pt en el color del área con degradado del 30 % al 0 %; eje x con
  etiquetas cortas y eje y a la derecha con 3 marcas; barras de radio 4 con una línea de media rotulada
  («Media 3,3 h»).
- Encima, el **destacado en frase** en 15 pt seminegrita.
- **Al pasar:** regla vertical y una burbuja de material con fecha e importe; la cifra grande cambia.
  **Al arrastrar:** selección de rango.
- **Periodos:** el selector segmentado nativo. **Estimado:** tramo con trama de rayas y etiqueta.

### 4.6 Barra lateral

- Cristal flotante a 8 pt del borde de la ventana, radio 20. Secciones con cabecera pequeña («Áreas»,
  «Recientes»). Filas de 32 pt con el icono de área en su cuadrado de color. **Seleccionada:** cápsula de
  cristal tintado. La empresa arriba, con su icono de 32 pt y un menú. Favoritos: círculos de cristal.
- **Modo edición, como la pantalla de inicio del iPhone:** tiemblan; «−» en un círculo `secundario`; asa «≡»;
  «Listo» en cápsula tintada arriba a la derecha.
- **Arrastrar fuera:** la fila sale como un icono de cristal; fuera aparece «Ocultar» y, al soltar, la nube
  corta del Mac (0,3 s, dibujada por la app, porque el sistema ya no la ofrece).
- **Ocultos:** grupo plegable «Ocultos» al pie, con «Mostrar» en cada fila.
- **Indentar:** el hijo se mete bajo el padre, que gana un triángulo para plegar (como las carpetas de Notas).
  Un grupo es una carpeta tintada.

### 4.7 Módulos

Tarjetas del Resumen de Salud: radio 16 en `superficie`; arriba el icono y el área (en su tinta) a la
izquierda y la hora o el periodo a la derecha; la cifra redondeada y una minigráfica. Los inicios tienen tres
secciones: **Fijados**, **Destacados** (frases con gráfica) y **Tendencias** (cambios de varias semanas).
«Editar» en la cabecera de cada sección: tiemblan, «−», asa y «+ Añadir» con galería tipo Centro de control.

### 4.8 Documentos

- **Factura, como un pase de Wallet:** franja superior en el relleno de Finanzas con «Factura · Borrador» y el
  total a 48 pt; debajo, los campos en dos filas de rótulo y valor (Para · Vence · Forma de pago ·
  Oportunidad); luego las listas agrupadas Conceptos y Totales, y la Actividad como línea de tiempo. Barra
  flotante de cristal abajo con la cápsula tintada «Revisar y emitir», «Vista previa PDF» y «Ver como texto».
- **Ficha de sistema:** título grande y «Para qué» como subtítulo; el número clave como un Destacado con su
  gráfica; los pasos en lista agrupada con el icono de quién y el modo como menú de 4 posiciones; candado en
  los de «Siempre con tu OK».
- **Texto plano:** SF Mono 13 pt; claves en `secundario`, títulos en negrita, enlaces en acento.

### 4.9 Las tres pantallas

- **Hoy:** «Hoy» a 34 pt con la fecha; la frase; el foco como un grupo destacado con las cinco preguntas en
  filas y el botón; las decisiones como lista agrupada; después, Fijados, Destacados y Tendencias.
- **Ventas:** «Ventas» con su icono; un Destacado con la cifra; el tablero con columnas en listas agrupadas y
  tarjetas de radio 12; al arrastrar, sombra del sistema y escala 1,03; Ganada bloqueada muestra un candado y
  el aviso. Seguimientos en el inspector de la derecha, de cristal.
- **Documento:** texto y pantalla en dos paneles con divisor nativo; pestañas en el selector segmentado de la
  barra de herramientas.

### 4.10 Movimiento, riesgos y coste

- **Movimiento:** muelles del sistema; las piezas de cristal se funden entre sí al acercarse. Con «Reducir
  movimiento», fundidos.
- **Riesgos:** la legibilidad del cristal (por eso solo en la navegación y probado con «Reducir
  transparencia»); parecer «una app más de Apple» sin carácter propio (lo ponen el magenta, el monograma y las
  cifras); el cristal completo solo existe en macOS 26.
- **Coste:** bajo; casi todo es nativo, salvo la barra lateral propia y la nube.

---

## 5. Gaceta — la portada de tu empresa

**Idea.** Cada mañana, Hoy es la portada del periódico de tu empresa: un titular (el foco), columnas, gráficas
de prensa económica y documentos compuestos como páginas bien impresas.

**Para quién y por qué encaja.** Para quien lee antes de decidir y quiere que facturas, sistemas y propuestas
tengan presencia de papel. Encaja con «visualmente claro en texto plano»: es la dirección donde el texto y la
pantalla se parecen más.

**Referentes.** Portadas y gráficas de la prensa económica (Financial Times, The Economist: línea fina,
etiquetas directas y notas con línea guía) · revistas como Monocle · la calma de Things 3 y Bear 2 · Craft (un
documento que se comporta como una app).

**En qué no se parece a Obsidian ni a Multica.** Es tipografía y reglas: sin paneles ni iconos por todas
partes. Parece un periódico, no un editor de código.

### 5.1 Color

| Uso | Claro | Contraste en claro | Oscuro | Contraste en oscuro |
|---|---|---|---|---|
| Fondo | `#FFFFFF` | — | `#000000` | — |
| Superficie | `#F7F5F0` | — | `#0F0F0E` | — |
| Texto | `#121212` | 18,73 / 17,19 | `#F3F0EA` | 18,46 / 16,86 |
| Texto secundario | `#5C5A55` | 6,89 / 6,32 | `#A8A399` | 8,36 / 7,64 |
| Separador | `#D9D6CE` | 1,33 sobre superficie (línea; nunca es la única pista) | `#34322E` | 1,50 sobre superficie (línea; nunca es la única pista) |
| Acento (relleno) | `#B0005F` | texto `#FFFFFF` encima: 6,97 · como gráfico y foco: 6,97 / 6,40 | `#FF5CA8` | texto `#000000` encima: 7,35 · como gráfico y foco: 7,35 / 6,71 |
| Acento (texto y enlaces) | `#B0005F` | 6,97 / 6,40 | `#FF5CA8` | 7,35 / 6,71 |

Contraste «a / b»: sobre el fondo / sobre la superficie. Mínimos: 4,5:1 texto; 3:1 gráficos, bordes de control y anillo de foco.

- Fondo de papel blanco; la superficie `#F7F5F0` solo para el índice lateral y los recuadros.
- El magenta es la **tinta del corrector** (`#B0005F`): enlaces subrayados, la acción principal (rectángulo
  relleno con letra blanca; en oscuro, `#FF5CA8` con letra negra) y las marcas del editor.
- **Reglas:** gruesa de 2 pt en `texto` para la cabecera de la edición y de cada sección; fina de 0,5 pt en
  `separador` entre filas.
- **Aumentar contraste:** las reglas finas pasan a 1 pt en `secundario`.

| Área | Tinta en claro (texto, iconos) | Relleno en claro (puntos, barras, series) | Tinta en oscuro | Relleno en oscuro |
|---|---|---|---|---|
| Dirección | `#503076` · 9,52:1 · L* 27 | `#57377E` · 8,55:1 · L* 30 | `#B28ADA` · 6,89:1 · L* 64 | `#916CB9` · 4,61:1 · L* 52 |
| Ventas | `#297452` · 5,19:1 · L* 44 | `#468F6C` · 3,57:1 · L* 54 | `#8BD6AF` · 11,27:1 · L* 80 | `#7EC8A2` · 9,74:1 · L* 75 |
| Entrega | `#295593` · 6,85:1 · L* 36 | `#3D64A5` · 5,41:1 · L* 42 | `#91B0F7` · 8,91:1 · L* 72 | `#7A9AE0` · 6,87:1 · L* 64 |
| Finanzas | `#9C6302` · 4,59:1 · L* 47 | `#BF8129` · 3,02:1 · L* 59 | `#FFC787` · 12,58:1 · L* 84 | `#FEB960` · 11,25:1 · L* 80 |
| Marca | `#B61064` · 5,94:1 · L* 40 | `#D03479` · 4,33:1 · L* 49 | `#FF9FBF` · 10,01:1 · L* 76 | `#FF84B0` · 8,38:1 · L* 70 |
| Equipo | `#921D22` · 7,96:1 · L* 32 | `#9F2B2C` · 6,75:1 · L* 37 | `#FF8076` · 7,86:1 · L* 68 | `#E0655D` · 5,65:1 · L* 58 |

Contraste: el peor de fondo y superficie. Separación mínima de luminosidad entre dos áreas (ΔL*): rellenos 5 en claro y 5 en oscuro; tintas 3 y 4.

Tintas apagadas. El área se señala con un **cintillo**: su nombre en versalitas de su tinta sobre una regla
de su color.

### 5.2 Tipografía

| Uso | Familia (Google Fonts) | Peso | Tamaño |
|---|---|---|---|
| Titulares | Newsreader (óptico 72) | 600 | 40 pt en la portada · 28 pt en pantallas |
| Entradillas | Newsreader, cursiva | 400 | 18 pt |
| Texto largo | Newsreader (óptico 16) | 400 | 16 pt, interlineado 1,5, columna de 64 caracteres como máximo |
| Cifras protagonistas | Newsreader, cifras de caja alta y tabulares | 500 | 56 pt (si en la maqueta no salen tabulares: IBM Plex Sans 600) |
| Interfaz, tablas y rótulos | IBM Plex Sans, cifras tabulares | 400 · 500 · 600 | 13 pt |
| Cintillos | IBM Plex Sans Condensed, mayúsculas, +8 % de espaciado | 600 | 11 pt |
| Códigos | IBM Plex Mono | 400 | 12 pt |

### 5.3 Forma, materiales y densidad

- **Radios:** 0 en bloques; 2 en botones y campos.
- **Sin sombras.** Se separa con reglas y blanco.
- Rejilla de 12 columnas con medianil de 24 pt y márgenes amplios.
- **Densidad:** media-alta en información, pero aireada. Filas de 40 pt y mucho texto bien compuesto.

### 5.4 Iconografía

Mínima: trazo fino (1,25 pt) solo donde ayuda (estado, área, acción); casi todo es palabra. SF Symbols en peso
light. Maqueta web: Phosphor «light».

### 5.5 Gráficas

- Estilo de prensa económica: línea de 1,5 pt en `texto`, rejilla horizontal de reglas finas, eje y a la
  derecha en IBM Plex Sans 11 pt y la etiqueta al final de la línea (sin leyenda).
- Notas con línea guía en Newsreader cursiva: «20 oct · Impuestos del trimestre, −945 €».
- **Al pasar:** regla vertical fina y una nota al margen con fecha e importe en cursiva; la cifra del titular
  cambia. **Al arrastrar:** el tramo se sombrea con trama y la nota da la diferencia.
- **Periodos:** enlaces de texto «1 s · 1 m · 3 m · 1 a · Todo», el elegido subrayado en magenta.
- **Estimado:** línea discontinua y la nota «Estimado: no hay extracto antes del 30 jun».

### 5.6 Barra lateral

- Un **índice** sobre la superficie: arriba el nombre de la empresa en Newsreader 600 a 20 pt y la fecha de la
  edición. Cada entrada: el nombre en IBM Plex Sans 500 a 14 pt y, a la derecha, su dato (Decisiones «3»,
  Ventas «2 quietas»), separadas por reglas finas. **Seleccionada:** regla magenta de 3 pt a la izquierda y
  texto en negrita. Favoritos: tres palabras en versalitas arriba, «Destacados».
- **Modo edición («Componer índice»):** sin temblor; borde discontinuo, «≡» a la derecha y «Quitar» como
  palabra a la izquierda.
- **Arrastrar fuera:** la entrada se convierte en un recorte de papel con una sombra mínima; fuera aparece
  «Ocultar» y, al soltar, una línea la tacha y se pliega (0,3 s).
- **Ocultos:** sección al pie titulada «Ocultos» en versalitas, con las entradas tachadas en gris y «Volver a
  poner».
- **Indentar:** sangría de 16 pt con una raya delante, como un subapartado del índice.

### 5.7 Módulos

«Piezas» de la portada en la rejilla de 12 columnas (Pequeño = 3 columnas, Mediano = 6, Grande = 6 a doble
altura, Ancho = 12). Cada pieza: cintillo, titular (la cifra o la frase), entradilla y la fuente al pie.
Separadas por reglas verticales finas, no por cajas. **Editar inicio («Maquetar portada»):** reglas
discontinuas, asas en las esquinas, «Quitar pieza» y la galería «Añadir pieza» como un índice de secciones.

### 5.8 Documentos

- **Factura, como página impresa** centrada (720 pt de ancho) sobre el fondo: a la izquierda el emisor con el
  logo pequeño; a la derecha «Factura» y el estado; regla gruesa; «Para» con los datos del cliente; la tabla
  de conceptos con reglas finas; el total en Newsreader a 40 pt, a la derecha, con regla doble encima; forma de
  pago y notas en texto. Es la versión más parecida al PDF. Barra fija: rectángulo magenta «Revisar y emitir» y
  los enlaces «Vista previa PDF» · «Ver como texto».
- **Ficha de sistema, como un artículo:** titular (el nombre), entradilla (el «Para qué») y, en el margen
  derecho, las notas laterales «Recibe de y entrega a», el número clave con una gráfica pequeña y «Lo lleva».
  Los pasos como párrafos con el número grande en Newsreader a 28 pt y quién y modo en cintillo. «Aprendido» se
  presenta como una fe de erratas con fechas.
- **Texto plano:** IBM Plex Mono 14 pt sobre blanco, interlineado 1,6; títulos en negrita y propiedades en
  `secundario`.

### 5.9 Las tres pantallas

- **Hoy (la portada):** cabecera «Asesoría Ribera · Jueves, 22 de octubre de 2026 · Edición de las 8:45» con
  regla gruesa; el titular es el foco a 40 pt, con la entradilla («por qué importa» y «qué pasa si no») y el
  botón; en la columna derecha, «Pide tu decisión» con tres piezas numeradas; debajo, las piezas (Caja con su
  gráfica de prensa, Ritmo por área como tabla de 6 filas, Tu semana como tira).
- **Ventas:** cintillo «Ventas»; titular «Dos oportunidades llevan una semana quietas»; el tablero como
  columnas de periódico separadas por reglas verticales, con tarjetas sin caja (solo una regla arriba) y el
  nombre en Newsreader a 17 pt; al arrastrar, la tarjeta toma fondo de superficie y una sombra mínima; Ganada
  bloqueada muestra trama diagonal y una nota en cursiva. Seguimientos como «Agenda» en una columna estrecha.
- **Documento:** el texto en la página izquierda y la composición en la derecha, como un libro abierto;
  pestañas como entradas de índice.

### 5.10 Movimiento, riesgos y coste

- **Movimiento:** casi ninguno; fundidos de 0,2 s. Solo se mueve lo que arrastras.
- **Riesgos:** menos impacto en los paneles de números (lo compensan las cifras en serifa grande); la serifa
  no sirve en tamaños pequeños de interfaz (por eso la interfaz va en IBM Plex Sans); puede parecer «para leer»
  y no «para hacer» si los botones no destacan (regla: una sola acción magenta por pantalla).
- **Coste:** medio; la rejilla de columnas y las gráficas de prensa son a medida.

---

## 6. Sobremesa — cálida y humana

**Idea.** La app como una mesa tranquila con alguien que te ayuda: colores crema, formas redondeadas, un objeto
ilustrado por área y frases que te hablan como una persona.

**Para quién y por qué encaja.** Para el empresario que no se considera «de números» y al que una pantalla
técnica le da pereza. Cuenta la promesa de The Last (que la empresa funcione sin ti) desde la calma: menos
alarma y más acompañamiento. Mika tiene presencia como un personaje geométrico, sin emojis.

**Referentes.** Airbnb 2025 (iconos-objeto en 3D suave que se animan al tocarlos, bordes redondos, barra de
acción fija) · Headspace 2024 (calidez con el contraste cuidado) · Duolingo (formas solo redondeadas y
progreso visible) · Day One (frases que acompañan).

**En qué no se parece a Obsidian ni a Multica.** Nada de rejillas técnicas ni grises fríos: papel crema,
objetos y frases.

### 6.1 Color

| Uso | Claro | Contraste en claro | Oscuro | Contraste en oscuro |
|---|---|---|---|---|
| Fondo | `#FBF5EE` | — | `#000000` | — |
| Superficie | `#FFFDFA` | — | `#1C1814` | — |
| Texto | `#2B211B` | 14,52 / 15,48 | `#F7EFE6` | 18,44 / 15,50 |
| Texto secundario | `#6A5B50` | 6,01 / 6,41 | `#B9AC9F` | 9,46 / 7,95 |
| Separador | `#EBDFD1` | 1,29 sobre superficie (línea; nunca es la única pista) | `#352E27` | 1,32 sobre superficie (línea; nunca es la única pista) |
| Acento (relleno) | `#C8175D` | texto `#FFFFFF` encima: 5,62 · como gráfico y foco: 5,19 / 5,54 | `#F06292` | texto `#1C0B12` encima: 6,21 · como gráfico y foco: 6,87 / 5,77 |
| Acento (texto y enlaces) | `#B3124F` | 6,22 / 6,64 | `#FF7FAA` | 8,87 / 7,45 |

Contraste «a / b»: sobre el fondo / sobre la superficie. Mínimos: 4,5:1 texto; 3:1 gráficos, bordes de control y anillo de foco.

- El acento es **frambuesa** (`#C8175D`), la versión cálida del magenta de marca, con blanco encima a 5,62:1.
- En oscuro, el fondo sigue siendo negro puro (tu preferencia) con una superficie cálida `#1C1814`; el acento
  se aclara a `#F06292` con letra oscura `#1C0B12` (6,21:1).
- Un grano de papel al 2 % solo en el fondo claro, nunca bajo el texto pequeño. Se quita con «Aumentar
  contraste», que además pone borde de 1 pt a las tarjetas.

| Área | Tinta en claro (texto, iconos) | Relleno en claro (puntos, barras, series) | Tinta en oscuro | Relleno en oscuro |
|---|---|---|---|---|
| Dirección | `#4E3272` · 9,59:1 · L* 27 | `#563979` · 8,59:1 · L* 30 | `#AF8CD5` · 6,33:1 · L* 64 | `#8F6EB4` · 4,25:1 · L* 52 |
| Ventas | `#447148` · 5,24:1 · L* 44 | `#5E8C61` · 3,59:1 · L* 54 | `#A2D3A4` · 10,41:1 · L* 80 | `#94C596` · 8,98:1 · L* 75 |
| Entrega | `#14588B` · 6,93:1 · L* 36 | `#2D689C` · 5,43:1 · L* 43 | `#83B4EE` · 8,17:1 · L* 72 | `#6D9FD7` · 6,38:1 · L* 64 |
| Finanzas | `#8F6900` · 4,63:1 · L* 47 | `#B38717` · 3,03:1 · L* 59 | `#FECA5E` · 11,62:1 · L* 84 | `#F2BF53` · 10,38:1 · L* 80 |
| Marca | `#BB0054` · 5,99:1 · L* 40 | `#D72C68` · 4,36:1 · L* 49 | `#FFA1B4` · 9,25:1 · L* 76 | `#FF85A2` · 7,67:1 · L* 70 |
| Equipo | `#8D2511` · 8,06:1 · L* 32 | `#9B321B` · 6,77:1 · L* 37 | `#FB8465` · 7,22:1 · L* 68 | `#DC694C` · 5,18:1 · L* 58 |

Contraste: el peor de fondo y superficie. Separación mínima de luminosidad entre dos áreas (ΔL*): rellenos 5 en claro y 5 en oscuro; tintas 3 y 4.

Tonos de tierra: lavanda, salvia, azul cielo, mostaza, frambuesa y terracota.

### 6.2 Tipografía

| Uso | Familia (Google Fonts) | Peso | Tamaño |
|---|---|---|---|
| Títulos | Bricolage Grotesque (óptico 48) | 700 | 30 pt |
| Cifras | Bricolage Grotesque (óptico 96), cifras tabulares (si no las tiene en la maqueta: Figtree 700) | 700 | 56 pt en Hoy |
| Interfaz y texto | Figtree | 400 · 500 · 600 | 14 pt en filas · 16 pt para leer |
| Rótulos | Figtree, sin mayúsculas (tono de conversación) | 600 | 12 pt |
| Códigos | DM Mono, poco visibles (en «Detalle») | 400 | 12 pt |

### 6.3 Forma, materiales y densidad

- **Radios grandes:** tarjeta 24 · fila 16 · botones en cápsula de 48 pt · chips en cápsula. Formas suaves
  detrás de las ilustraciones.
- **Sombras cálidas** en claro: `0 2px 6px rgba(60,40,20,.06)` y `0 12px 32px rgba(60,40,20,.08)`. En oscuro,
  sin sombra y con borde blanco al 6 %.
- **Densidad:** baja. Filas de 56 pt, mucho aire y como mucho 5 filas por tarjeta.

### 6.4 Iconografía

- Trazo redondeado de 2 pt con extremos redondos (SF Symbols en peso medio; maqueta web: Phosphor «bold»).
- **Un objeto ilustrado por área** (de 28 a 96 pt), en sus tonos y con sombra suave: brújula (Dirección),
  escaparate con toldo (Ventas), caja que se abre (Entrega), hucha (Finanzas), megáfono (Marca) y mesa con dos
  sillas (Equipo). Más el personaje de Mika (formas redondas, sin cara de emoji). Se pueden generar con IA y
  revisar, en claro y en oscuro.

### 6.5 Gráficas

- Curva suave que no inventa picos (interpolación monótona) de 3 pt con extremos redondos y relleno degradado
  del 20 % al 0 % en el tono del área; barras con los extremos redondos; sin rejilla y con 3 etiquetas en el
  eje x.
- Encima, una frase amable: «Este mes la caja baja un poco: el martes se pagaron los impuestos del trimestre».
- **Al pasar:** un globito redondo con la fecha y una frase («Martes 20: pagaste 945,20 € de impuestos»); la
  cifra grande cambia con un rebote pequeño. **Al arrastrar:** tramo sombreado y frase con la diferencia.
- **Periodos con palabras:** «Semana · Mes · 3 meses · Año · Todo» (las siglas van en la etiqueta para
  VoiceOver).
- **Estimado:** tramo punteado con «Calculado sin extracto».

### 6.6 Barra lateral

- Una **estantería**: superficie crema con radio 24, separada 12 pt del borde. Cada área con su objeto pequeño
  (28 pt), el nombre en Figtree 600 a 15 pt y el estado en palabras. **Seleccionada:** pastilla blanca con
  sombra cálida. Arriba, el logo de la empresa en un círculo y «Hola, Elena». Favoritos: tres círculos con
  objeto.
- **Modo edición:** los elementos se balancean despacio (±1°, 0,25 s); «−» en un círculo crema con borde y un
  asa redondeada.
- **Arrastrar fuera:** el elemento se levanta como una tarjeta y fuera aparece un **cajón** abierto con el
  rótulo «Ocultar»; al soltarlo, cae dentro con un rebote corto y el cajón se cierra (0,35 s).
- **Ocultos:** el cajón al pie, «Ocultos (2)», que se abre y enseña lo guardado como fichas redondas con
  «Sacar».
- **Indentar:** el elemento se mete bajo el de arriba con un conector curvo de 2 pt, como una rama.

### 6.7 Módulos

Tarjetas blancas de radio 24 con el objeto del área en una esquina, un título en forma de pregunta («¿Hay
caja?»), la cifra y una frase. Editar inicio: se balancean, «−» y asa redondeada; «Añadir» abre una galería
de tarjetas de ejemplo ilustradas.

### 6.8 Documentos

- **Factura, como una nota de papel** de esquinas redondeadas sobre el crema: arriba la hucha pequeña y «Factura
  para Arquitectura Nexo»; el total en grande y un sello redondo con el estado («Borrador»); los conceptos en
  filas amplias con el importe a la derecha; los totales en una tarjeta interior. Barra fija con el botón
  frambuesa «Revisar y emitir» y la pregunta «¿La emitimos hoy? Vencería el 29 de octubre».
- **Ficha de sistema, como una receta:** el «Para qué» como entradilla; «Recibe de» como los ingredientes; los
  pasos numerados con quién lo hace (iniciales de Elena o el personaje del asistente), el modo en palabras y un
  candado cuando toca; los criterios como consejos con marca; «Aprendido» como notas a mano en cursiva.
- **Texto plano:** DM Mono 14 pt sobre crema, interlineado 1,6, con la sintaxis apenas coloreada.

### 6.9 Las tres pantallas

- **Hoy:** «Buenos días, Elena» en grande y la frase; el foco en una tarjeta grande con el personaje de Mika y
  el botón frambuesa; las decisiones como tres tarjetas con las opciones en pastillas 1·2·3; después, las
  tarjetas de módulos.
- **Ventas:** cabecera con el escaparate, la pregunta en grande y «2 oportunidades llevan una semana quietas»;
  el tablero en columnas crema con tarjetas blancas redondas y el avatar del responsable; al arrastrar, la
  tarjeta se levanta e inclina 2°; Ganada bloqueada se cierra con un candado ilustrado y una frase.
  Seguimientos como «Para escribir hoy».
- **Documento:** el texto en una hoja crema a la izquierda y la nota a la derecha; pestañas como pastillas
  grandes.

### 6.10 Movimiento, riesgos y coste

- **Movimiento:** muelles con rebote suave; los objetos se animan al pulsarlos (0,4–0,6 s): la hucha recibe
  una moneda al confirmar un cobro, la caja se cierra al entregar un proyecto. Con «Reducir movimiento», sin
  rebotes ni animaciones de objetos.
- **Riesgos:** que parezca infantil o poco seria (por eso: frases sobrias, sin globos de diálogo, sin rachas);
  producir 6 objetos y el personaje, en claro y en oscuro; menos densidad, más desplazamiento.
- **Coste:** medio-alto, por las ilustraciones y sus animaciones.

---

## 7. Póster — la marca a todo volumen

**Idea.** Cada pantalla es un cartel: una cifra gigante, una rejilla dura en blanco y negro y un solo bloque
magenta que dice qué es lo importante.

**Para quién y por qué encaja.** Para quien quiere que la app tenga la personalidad de The Last y se reconozca
a dos metros; para empresarios que deciden rápido y quieren jerarquía sin matices: lo importante, enorme; lo
demás, pequeño.

**Referentes.** El estilo tipográfico suizo y los carteles de festival · las campañas de resumen anual (cifras
enormes) · Apple Invites y los fondos de Revolut (un color que lo llena todo) · las portadas por área del
manual de marca de The Last.

**En qué no se parece a Obsidian ni a Multica.** Sin cajas grises ni iconos por todas partes: números
enormes, reglas gruesas y un bloque de color.

### 7.1 Color

| Uso | Claro | Contraste en claro | Oscuro | Contraste en oscuro |
|---|---|---|---|---|
| Fondo | `#FFFFFF` | — | `#000000` | — |
| Superficie | `#F0F0F0` | — | `#151515` | — |
| Texto | `#000000` | 21,00 / 18,43 | `#FFFFFF` | 21,00 / 18,26 |
| Texto secundario | `#4A4A4A` | 8,86 / 7,78 | `#B5B5B5` | 10,24 / 8,91 |
| Separador | `#000000` | 18,43 sobre superficie (línea; nunca es la única pista) | `#FFFFFF` | 18,26 sobre superficie (línea; nunca es la única pista) |
| Acento (relleno) | `#E6007E` | texto `#FFFFFF` encima: 4,50 · como gráfico y foco: 4,50 / 3,95 | `#E6007E` | texto `#FFFFFF` encima: 4,50 · como gráfico y foco: 4,67 / 4,06 |
| Acento (texto y enlaces) | `#C4006B` | 5,90 / 5,18 | `#FF3D9A` | 6,39 / 5,55 |

Contraste «a / b»: sobre el fondo / sobre la superficie. Mínimos: 4,5:1 texto; 3:1 gráficos, bordes de control y anillo de foco.

- El separador es el propio `texto`: aquí las reglas de 2 pt son estructura, no decoración.
- **Un único bloque `#E6007E` por pantalla:** en Hoy, el foco; en Ventas, la cifra; en el Documento, el total.
  El texto encima es blanco y grande (18 pt seminegrita o más).
- **Aumentar contraste:** el bloque pasa a `#C4006B`.

| Área | Tinta en claro (texto, iconos) | Relleno en claro (puntos, barras, series) | Tinta en oscuro | Relleno en oscuro |
|---|---|---|---|---|
| Dirección | `#4700BF` · 9,12:1 · L* 27 | `#510CC9` · 8,21:1 · L* 30 | `#B681FF` · 6,59:1 · L* 64 | `#9754FF` · 4,37:1 · L* 52 |
| Ventas | `#00764B` · 4,99:1 · L* 43 | `#01945F` · 3,41:1 · L* 54 | `#5ADE9E` · 10,76:1 · L* 80 | `#4ACF91` · 9,24:1 · L* 75 |
| Entrega | `#00569B` · 6,57:1 · L* 36 | `#0166B6` · 5,15:1 · L* 43 | `#85B1FF` · 8,46:1 · L* 72 | `#4F9CFF` · 6,55:1 · L* 64 |
| Finanzas | `#906600` · 4,51:1 · L* 46 | `#B48100` · 3,03:1 · L* 57 | `#FFC96C` · 12,02:1 · L* 84 | `#FFBA23` · 10,70:1 · L* 80 |
| Marca | `#B90064` · 5,68:1 · L* 40 | `#DF017A` · 4,17:1 · L* 48 | `#FF9FBF` · 9,53:1 · L* 76 | `#FF83B0` · 7,94:1 · L* 70 |
| Equipo | `#9B0600` · 7,62:1 · L* 32 | `#B00300` · 6,45:1 · L* 37 | `#FF8163` · 7,45:1 · L* 68 | `#FF4729` · 5,38:1 · L* 58 |

Contraste: el peor de fondo y superficie. Separación mínima de luminosidad entre dos áreas (ΔL*): rellenos 3 en claro y 5 en oscuro; tintas 3 y 4.

Además del color, cada área tiene su número grande (1–6) y su **trama**: Dirección rombos, Ventas puntos,
Entrega cuadrícula, Finanzas rayas horizontales, Marca rayas diagonales y Equipo cruces. Así se distinguen
incluso en blanco y negro.

### 7.2 Tipografía

| Uso | Familia (Google Fonts) | Peso | Tamaño |
|---|---|---|---|
| Cifras | Unbounded, −3 % de espaciado | 800 | 96 pt en Hoy y Ventas · 72 pt en documentos |
| Titulares | Unbounded | 700 | 32 pt |
| Rótulos de sección | Archivo, ancho 125 (Expanded) | 700 | 16 pt |
| Texto e interfaz | Archivo | 400 · 500 · 700 | 14 pt |
| Rótulos pequeños y códigos | JetBrains Mono, mayúsculas, +6 % de espaciado | 500 · 700 | 11 pt |

### 7.3 Forma, materiales y densidad

- **Radio 0 en todo**, también en los botones.
- Reglas de 2 pt en `texto` (4 pt en la cabecera de sección). Sin sombras, salvo la **sombra dura** de 4 pt
  desplazada en `texto` del elemento que arrastras.
- Rejilla de 12 columnas, visible en el modo edición.
- **Densidad:** baja: pocos elementos y enormes. Filas de 56 pt con regla de 1 pt.

### 7.4 Iconografía

Geométrica, trazo de 2,5 pt con extremos rectos, a 20 pt. Se usa poco: casi siempre la sustituye el número
del área o una palabra en mayúsculas. SF Symbols en negrita; maqueta web: Phosphor «bold».

### 7.5 Gráficas

- Línea escalonada o barras gruesas, trazo de 3 pt en `texto`, sin relleno; el tramo bajo la referencia lleva
  trama diagonal; etiquetas directas grandes en Archivo 700.
- **Al pasar:** una cruz de reglas que atraviesa la gráfica y una etiqueta invertida (fondo `texto`, letra
  `fondo`) con fecha e importe en JetBrains Mono; la cifra gigante cambia de golpe, sin rodar. **Al
  arrastrar:** el tramo se rellena de magenta al 20 % y la etiqueta da la diferencia.
- **Periodos:** cajas con regla de 2 pt; la elegida, invertida.
- **Estimado:** trama de puntos y el rótulo «ESTIMADO».

### 7.6 Barra lateral

- Columna blanca separada del contenido por una regla de 2 pt. Arriba, la empresa en Unbounded 700 a 18 pt.
  Las áreas como números grandes (Unbounded 800 a 28 pt, del «1» al «6») con el nombre al lado en JetBrains
  Mono y el estado en una palabra; Hoy, Decisiones y Tareas en Archivo Expanded 700 a 16 pt. **Seleccionada:**
  fila invertida (fondo negro, letra blanca). Favoritos: tres cuadrados de 36 pt con borde de 2 pt.
- **Modo edición, sin temblor:** aparece la rejilla; cada fila con un «×» en un cuadrado de 28 pt y un asa
  rayada; «LISTO» invertido arriba.
- **Arrastrar fuera:** la fila sale con su sombra dura; fuera espera una caja con trama diagonal y el rótulo
  «OCULTAR»; al soltar, corte seco (0,15 s, sin nube).
- **Ocultos:** caja con trama al pie, «OCULTOS (2)», con «VOLVER» en cada elemento.
- **Indentar:** la fila se desplaza 24 pt con un «↳» en JetBrains Mono.

### 7.7 Módulos

Celdas de la rejilla separadas por reglas de 2 pt; cada una con su índice y rótulo en mono («01 · CAJA»), una
cifra enorme y una línea. Un solo módulo en magenta por inicio (en Hoy ese papel lo tiene el foco). Editar
inicio: rejilla visible, «×» en la esquina, asa cuadrada y «+ AÑADIR», que abre una lista a pantalla completa.

### 7.8 Documentos

- **Factura, como un cartel:** bloque magenta a todo el ancho con «290,40 €» en Unbounded 800 a 72 pt en
  blanco y «BORRADOR · SE NUMERA AL EMITIR» en mono; debajo, la rejilla de datos (PARA · VENCE · FORMA DE PAGO ·
  OPORTUNIDAD) en celdas con regla; los conceptos en tabla con reglas de 1 pt. Barra fija con el botón
  rectangular invertido «REVISAR Y EMITIR» (negro con letra blanca en claro; blanco con letra negra en
  oscuro), «VISTA PREVIA PDF» y «VER COMO TEXTO».
- **Ficha de sistema:** el nombre gigante; el número clave en el bloque magenta; los pasos como 6 celdas «01»
  a «06» con quién y modo, y un candado en las de «Siempre con tu OK».
- **Texto plano:** JetBrains Mono 14 pt en negro sobre blanco, sin más color que los enlaces magenta
  subrayados.

### 7.9 Las tres pantallas

- **Hoy:** cabecera «HOY · JUEVES 22 OCT» en mono y la frase «3 decisiones. 2,5 h de 4.» en Unbounded a 32
  pt; el foco es el bloque magenta a todo el ancho con el titular en blanco y un botón blanco con letra negra;
  las decisiones en tres columnas numeradas «1 2 3»; los módulos en la rejilla.
- **Ventas:** la cifra «2» gigante en el bloque magenta con «OPORTUNIDADES QUIETAS · META 0 · ALERTA 1»; el
  tablero en columnas separadas por reglas, con tarjetas-fila y el valor grande; al arrastrar, sombra dura;
  Ganada bloqueada se cubre de trama con «NECESITA UN COBRO CONFIRMADO».
- **Documento:** dos columnas separadas por una regla de 2 pt; pestañas como cajas.

### 7.10 Movimiento, riesgos y coste

- **Movimiento:** cortes secos y entradas laterales de 0,15–0,2 s; nada rebota. Con «Reducir movimiento»,
  fundidos.
- **Riesgos:** cansa si se abusa (de ahí la regla de un bloque magenta por pantalla); los tamaños enormes piden
  más desplazamiento con el texto al 200 %; puede intimidar a quien empieza (Sobremesa es justo lo contrario).
- **Coste:** bajo-medio. Formas simples; el trabajo lo hace la tipografía.

---

## 8. Comparación

| | Mosaico | Saldo | Cristal | Gaceta | Sobremesa | Póster |
|---|---|---|---|---|---|---|
| **Cubre** | Fiel a la marca | Trade Republic y Revolut | Apple nativa | Editorial | Cálida y humana | Atrevida |
| **Sensación** | Ordenada, táctil | Rápida, financiera | Familiar, nativa | Serena, culta | Acogedora | Rotunda |
| **Modo natural** | Claro | Oscuro | Claro | Claro | Claro | Claro |
| **Densidad** | Media | Baja-media | Media | Media-alta | Baja | Baja |
| **Forma** | Redondeada (22) | Cápsulas y filas | Concéntrica | Recta, reglas | Muy redonda (24) | Recta (0) |
| **Letra** | Space Grotesk + DM Sans | Manrope | SF Pro | Newsreader + IBM Plex | Bricolage + Figtree | Unbounded + Archivo |
| **Gráficas** | Área con degradado | Línea a sangre, cifra que rueda | Swift Charts y frase | Prensa económica | Curva suave y globito | Escalonada, cruz invertida |
| **Factura** | Mosaico magenta | Detalle de movimiento | Pase de Wallet | Página impresa | Nota con sello | Cartel |
| **Modo edición de la barra** | Tiembla, nube de puntos | Sin temblor, se hunde | Tiembla, nube del Mac | Se tacha | Cajón | Corte seco, caja con trama |
| **Cambio frente a hoy** | Grande | Moderado | Grande | Muy grande | Muy grande | Muy grande |
| **Ilustraciones** | No | No | No | No | Sí (6 objetos y Mika) | No (tramas) |
| **Coste de construir** | Medio | Bajo-medio | Bajo | Medio | Medio-alto | Bajo-medio |
| **Riesgo principal** | Todo a la vez | Poco cambio | Sin carácter | Poco «de hacer» | Infantil | Cansa |

---

## 9. Lo que necesito que decidas (con propuesta)

1. **Modo de las maquetas.** Propuesta: claro y oscuro con un conmutador; cada dirección se enseña primero en
   su modo natural (Saldo en oscuro, las demás en claro).
2. **¿Se pueden mezclar?** Propuesta: eliges una como base y puedes tomar prestada **una sola** pieza de otra
   (por ejemplo, las gráficas de Saldo en Mosaico), para que no pierda carácter.
3. **Colores de área.** Propuesta: se mantiene el reparto actual (violeta, verde, azul, ámbar, magenta, rojo)
   por continuidad, y cambian los tonos según la dirección. Alternativa: Equipo pasa a turquesa para que el
   rojo quede solo para los avisos.
4. **Texto hasta el 200 %** (cambia `PLAN.md` §6.9). Propuesta: sí.
5. **Pie de la barra lateral vacío** (el interruptor de asistentes pasa a la barra de herramientas). Propuesta:
   sí; ya está en `SISTEMAS.md` §5.10.
6. **Si eliges Sobremesa:** ¿las ilustraciones se generan con IA y se revisan, o se encargan? Propuesta:
   generarlas y revisarlas, con una versión provisional mientras tanto.
7. **Si eliges Cristal:** el cristal completo pide macOS 26 y la app arranca en macOS 15. Propuesta: mantener
   macOS 15, con material translúcido en las versiones anteriores.

**Si me pides una apuesta:** Mosaico como base, porque responde a la vez a la marca, a los módulos y a la
personalización, con la gráfica de Saldo (la cifra que cambia al recorrerla) como la pieza prestada. Si lo que
más pesa es la sensación de la app que ya te gustó, Saldo.

---

## Anexo. Cómo se han calculado los colores

- **Contraste:** fórmula de WCAG 2.x (luminancia relativa en sRGB). Cada valor de las tablas es la pareja
  exacta: texto sobre fondo, texto sobre superficie o texto sobre relleno.
- **Colores de área:** se parte de un color semilla por área y dirección y se ajusta solo su luminosidad
  (L* de CIELAB, conservando el tono) hasta cumplir el contraste: 4,5:1 para la tinta y 3:1 para el relleno
  contra el fondo y la superficie a la vez. El orden de luminosidad es el de §1.7.
- **Semillas de Cristal:** los colores del sistema de Apple, oscurecidos o aclarados lo justo para cumplir.
- **Lo que queda por probar en las maquetas:** que las cifras tabulares existan en Newsreader y en Bricolage
  Grotesque, y que el cristal se lea con «Reducir transparencia» y con «Aumentar contraste».

**Procedencia.** Los referentes son públicos (guías de Apple, apps citadas y prensa sobre sus rediseños). Las
direcciones Mosaico (antes «Bento»), Cristal, Gaceta (antes «Papel»), Sobremesa (antes «Escaparate»), Póster y Saldo (antes
«Cifra») parten de las diez candidatas del informe de referencias; «Resumen» se integra en Cristal, y «Ruta»,
«Agenda» y «Mapa» quedan como capas que cualquier dirección puede usar (puesta en marcha, otra versión de Hoy y
la vista «Sistemas y flujos»). En este documento no se usa material de Blash. Todos los datos de ejemplo son de
Asesoría Ribera, que es ficticia.
