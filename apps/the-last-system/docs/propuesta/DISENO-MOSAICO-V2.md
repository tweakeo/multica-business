# Mosaico v2 · diseño de producto de The Last System

> **Qué es esto.** La especificación que siguen quienes construyen la app en SwiftUI y quienes dibujan las
> maquetas. Parte de la dirección **Mosaico** (`DIRECCIONES.md` §2), ya elegida, y la lleva a una app completa:
> colores y valores exactos, cómo se navega en profundidad (contacto → sus proyectos → un proyecto → …), cómo es
> cada ficha, cómo se ven y se buscan todas las bases, cómo se editan las relaciones desde cualquier lado y cómo
> se construye todo con SwiftUI.
>
> **Lo que decidiste.** Mosaico, con tonos más de The Last pero **azules o morados**; el magenta se queda, sin
> protagonismo. Navegación **en profundidad**: dándole a las pestañas se llega a la ficha del contacto, de ahí a
> sus proyectos y a uno de ellos, con la información adecuada en cada momento. Acceso visual a **todas las bases**
> para buscar en ellas y tenerlas ordenadas. **Todo editable, también las relaciones**, desde los dos lados.
>
> **Respuestas que aplica este documento.** Paleta «Azul noche» (azul noche para botones y cabeceras, violeta
> para el módulo destacado, magenta solo para el foco y los avisos). Navegación con migas y Atrás/Adelante
> (⌘[ ⌘]), como Finder. Relaciones como enlaces en las propiedades (`SISTEMAS.md` §1.6), editables desde
> cualquiera de los dos lados.
>
> **Estado:** propuesta para aprobar · 22/10/2026 · no cambia nada en la app ni en ninguna carpeta.
>
> **Base:** `DIRECCIONES.md` §1–§2, `SISTEMAS.md` (§1.4, §1.5, §1.6, §3.5, §3.6, §4, §5), `PLANTILLAS.md`,
> `GUION-MAQUETAS.md`, `PLAN.md` §6, la maqueta Mosaico v1 (`D1-Hoy.dc.html`) y el código actual de `TLSUI` y
> `TLSDesign`. Los contrastes están calculados con la fórmula de WCAG 2.x y las distancias entre colores con
> ΔE2000 (Anexo). Todos los ejemplos son de Asesoría Ribera, que es ficticia.

---

## 0. En una página

1. **Tres colores con un papel cada uno.** Azul noche `#1E2A78` para actuar (botones, selección) y para las
   cabeceras; violeta `#7C3AED` para **el** destacado de cada pantalla (uno como mucho); magenta `#E6007E` como
   chispa, **solo** para el foco (dónde estás) y los avisos (algo te toca). El magenta ya no rellena nada grande.
2. **Las áreas cambian de tono para no confundirse con la marca:** Dirección pasa a **ciruela**, Entrega a
   **petróleo**, Marca a **oliva** y Equipo a **granate**; Ventas sigue en verde y Finanzas en ámbar. Se mantiene
   el orden de luminosidad de siempre, así que también se distinguen en gris.
3. **Navegación en profundidad dentro de la misma ventana.** Cada clic entra un nivel; arriba, las migas
   (`2 · Ventas › Arquitectura Nexo › Trimestrales › Factura`); ⌘[ y ⌘] van atrás y adelante como en Finder;
   ⌘clic abre en una pestaña nueva de la ventana; al pasar el puntero (o con la barra espaciadora) se ve una
   vista previa sin salir de donde estás.
4. **Todas las fichas tienen el mismo molde:** cabecera azul noche con estado y acciones, el destacado violeta,
   una franja «Ahora» con lo urgente (solo si lo hay), una franja «Conectado con» y pestañas con contador:
   Resumen · lo relacionado por tipo · Notas · Actividad · Fichero.
5. **La información adecuada en el momento adecuado:** la ficha abre en la pestaña que toca según su tipo y su
   estado (una oportunidad Aceptada abre en Facturas; una reunión Hecha, en sus acciones), dentro de cada
   pestaña lo abierto y lo urgente va primero, y un vacío siempre explica por qué y qué hacer.
6. **Bases:** una sección nueva en la barra lateral con las bases fijadas y «Todas las bases», una pantalla con
   las 24 colecciones agrupadas por área. Cada base tiene vistas Tabla · Tablero · Calendario · Galería · Lista,
   búsqueda instantánea, filtros, agrupación, columnas a tu gusto, edición en la propia celda, creación rápida y
   vistas guardadas. ⌘K busca en todas a la vez.
7. **Relaciones:** cada relación la guarda una sola ficha (la que dice `SISTEMAS.md` §3.6) y la otra la
   calcula. Se puede añadir, cambiar o quitar desde cualquiera de las dos; la app escribe siempre en la que la
   guarda, una sola línea, con Deshacer. Un selector con búsqueda permite crear la ficha que falta sin salir.
8. **Sin grafo.** Lo relacionado se ve en pestañas y en la franja «Conectado con». Propongo retirar el módulo
   «Mapa de relaciones» de la v1.
9. **Construible en SwiftUI** con macOS 15: `NavigationSplitView` de dos columnas con un `NavigationStack` de
   ruta tipada por pestaña de ventana, `Table` con columnas dinámicas, `inspector`, Swift Charts y paneles
   propios para ⌘K, el selector de relación y la vista previa (§7).
10. **Cambios en otros documentos** (§8) y **11 preguntas finales con propuesta** (§10). Las tres que más pesan:
    los nuevos colores de área, ⌘[ ⌘] para navegar (indentar en la barra pasa a ⌥⌘← ⌥⌘→) y dónde se guardan
    las vistas de cada base.

---

## 1. Color, letra y forma

### 1.1 Quién hace qué

| Color | Papel | Sí | No |
|---|---|---|---|
| **Azul noche** (principal) | Actuar y encabezar | Botón principal, selección (barra lateral, filas, pestaña activa), cabeceras de área, base y ficha, línea de las gráficas, interruptores y casillas del sistema | Texto corrido, rellenos de módulo |
| **Violeta** (secundario) | Lo primero que hay que mirar | **El destacado:** como mucho uno por pantalla. Hoy → tu foco; área → su número clave; ficha → su dato protagonista | Botones fuera del destacado, enlaces, selección, gráficas, áreas |
| **Magenta** (chispa) | Dónde estás y qué te toca | Anillo de foco del teclado, línea «ahora» del calendario, insignias de «te toca» y punto de novedad (§1.5) | Botones, selección, enlaces, títulos, rellenos, gráficas, áreas, estados |

**Proporción orientativa por pantalla:** neutros 85 %, azul noche 10 %, violeta 4 %, magenta 1 % o menos.

### 1.2 Neutros

| Valor | Claro | Contraste en claro | Oscuro | Contraste en oscuro |
|---|---|---|---|---|
| `fondo` | `#F3F5FA` | — | `#000000` | — |
| `superficie` (mosaicos, barra lateral) | `#FFFFFF` | — | `#10142A` | — |
| `superficieElevada` (vista previa, menús, hojas, tarjeta levantada) | `#FFFFFF` + sombra 2 | — | `#1A1F3E` | — |
| `bandeja` (hundida: columnas del tablero, buscador, chips) | `#E8EBF5` | — | `#0A0D1F` | — |
| `cabecera` (relleno) | `#1E2A78` | blanco encima 12,67 | `#1E2A78` | blanco encima 12,67 |
| `subtituloCabecera` | `#C3C9EE` | 7,79 sobre la cabecera | `#C3C9EE` | 7,79 |
| `texto` | `#0F1430` | 16,55 · 18,06 · 15,16 | `#EEF0FA` | 18,48 · 15,99 · 14,11 |
| `textoSecundario` | `#545A7A` | 6,17 · 6,73 · 5,65 | `#9AA1C4` | 8,27 · 7,16 · 6,31 |
| `separador` (línea; nunca es la única pista) | `#DFE3EE` | 1,18 · 1,28 | `#252B4D` | 1,53 · 1,33 |
| `bordeControl` (campos, casillas, bandeja «Ocultos») | `#7A819F` | 3,52 · 3,84 · 3,22 | `#6A72A0` | 4,53 · 3,92 · 3,46 |
| `velo` (detrás de una hoja) | `#0F1430` al 30 % | — | `#000000` al 60 % | — |

Contraste en claro: sobre `fondo` · `superficie` · `bandeja`. En oscuro: sobre `fondo` · `superficie` ·
`superficieElevada`. Mínimos: texto 4,5; iconos, bordes de control y anillo de foco 3.

### 1.3 Azul noche (principal) y sus estados

| Estado | Claro | Contraste | Oscuro | Contraste |
|---|---|---|---|---|
| Reposo | `#1E2A78`, texto `#FFFFFF` | 12,67 con el texto · 11,61 sobre el fondo | `#7C8CFF`, texto `#0B1030` | 6,24 con el texto · 7,05 / 6,10 / 5,39 sobre fondo, superficie y elevada |
| Al pasar el puntero | `#2B3A99` | 9,69 | `#95A2FF` | 7,86 |
| Pulsado | `#151D58` | 15,57 | `#6577F2` | 4,84 |
| Desactivado | relleno `bandeja`, texto `textoSecundario` y el motivo al lado | 5,65 | relleno `#1A1F3E`, texto `#9AA1C4` | 6,31 |
| Foco del teclado | anillo magenta (§1.5) | — | anillo magenta | — |
| `principalSuave` (selección secundaria, rango de la gráfica, fila de la ventana inactiva) | `#E8EAF2` | azul noche encima 10,55 | `#232A50` | `#7C8CFF` encima 4,64 |
| `enlace` (texto que lleva a otra ficha) | `#3346C2`, **siempre subrayado** | 6,89 · 7,51 · 6,31 | `#95A2FF`, siempre subrayado | 7,69 sobre la superficie |
| Selección (barra lateral, filas, pestaña activa) | relleno `#1E2A78`, texto blanco | 12,67 | relleno `#7C8CFF`, texto `#0B1030` | 6,24; el relleno frente a la superficie, 6,10 |

- **Desactivado** no rebaja el contraste: el botón se ve gris y legible, y a su lado se dice por qué («Ganada
  necesita un cobro confirmado por una persona»).
- **Enlaces subrayados:** el azul del enlace frente al texto da 2,40 (claro) y 2,08 (oscuro), menos de 3, así
  que el color solo no basta (WCAG 1.4.1).
- **Botón principal sobre la cabecera azul noche:** relleno blanco y texto azul noche (12,67).
- **Selección en oscuro con relleno claro:** un relleno azul oscuro con texto blanco quedaría a 1,82 de la
  superficie y no se vería qué está elegido.

### 1.4 Violeta (secundario): el destacado

| Uso | Claro | Contraste | Oscuro | Contraste |
|---|---|---|---|---|
| Relleno del destacado | `#7C3AED`, texto blanco | 5,70 con el texto · 5,22 sobre el fondo | `#7C3AED`, texto blanco | 5,70 · borde con el fondo 3,69 y con la superficie 3,19 |
| Al pasar / pulsado (la tarjeta entera es un botón) | `#6D28D9` / `#5B21B6` | 7,10 / 8,98 | `#8B4CF7` / `#6D28D9` | 4,69 / 7,10 |
| Botón dentro del destacado | relleno blanco, texto `#7C3AED` | 5,70 | igual | 5,70 |
| Texto violeta (solo el rótulo «Destacado» en la galería de módulos) | `#7C3AED` | 5,22 · 4,78 en la bandeja | `#A78BFA` | 7,72 · 6,68 · 5,89 |
| `violetaSuave` (el destacado vacío o en edición) | `#F2EBFD` | violeta encima 4,91 | `#281C55` | `#A78BFA` encima 5,56 |

Reglas:
- **Uno por pantalla como mucho.** Las bases no llevan destacado; las vistas previas tampoco.
- El destacado nunca va sobre `superficieElevada` en oscuro (2,81).
- Dentro del destacado, las pastillas de estado van en blanco, con su icono de color y la palabra en `texto`.

### 1.5 Magenta (chispa): cuándo sí y cuándo no

| Uso | Claro | Contraste | Oscuro | Contraste |
|---|---|---|---|---|
| Anillo de foco: 2 pt, con 2 pt de hueco del color de debajo | `#E6007E` | 4,13 fondo · 4,50 superficie · 3,78 bandeja | `#E6007E` | 4,67 · 4,04 · 3,56 elevada · 4,28 bandeja |
| Línea «ahora» (calendario, cronograma, «Lo que cabe hoy») | `#E6007E`, 2 pt | 4,50 | `#E6007E` | 4,04 |
| Insignia «te toca» con número (12 pt seminegrita) | `#E6007E` y número blanco | 4,50 (justo) | igual | 4,50 |
| Punto de novedad (8 pt) | `#E6007E` | ≥ 3,78 | `#E6007E` | ≥ 3,56 |
| Texto magenta (solo «Nuevo» junto al punto, si hace falta palabra) | `#C4006B` | 5,41 · 5,90 · 4,95 | `#FF3D9A` | 6,39 · 5,53 · 4,88 |

**Sí:**
1. **Foco:** dónde estás con el teclado (anillo) y en el tiempo (línea «ahora»).
2. **Avisos («te toca»):** la insignia con el número de lo que pide **tu** acción (Decisiones 3; «Por revisar 2»
   en la pestaña de una ficha cuyos borradores esperan tu OK) y el punto de novedad (algo cambió desde tu
   última visita: una fila, una pestaña, una ficha).

**No:** botones, selección, enlaces, títulos, rellenos de módulo, gráficas, colores de área, estados, la
pastilla «Falta» (es Atención) ni texto corrido. Nunca dos insignias magenta seguidas sin palabra al lado.

**Aviso no es Atención.** El aviso magenta dice «aquí tienes algo que hacer» y no es malo. Atención (naranja
tostado, §1.6) dice «esto va mal pronto». Así no se mezclan «3 decisiones» con «vence hoy».

**Sobre un relleno de color** (cabecera, botón azul noche, destacado violeta), el anillo de foco es **blanco**
(12,67 sobre azul noche; 5,70 sobre violeta): el magenta daría 2,81 y 1,27.

### 1.6 Estados

Se mantienen los de `DIRECCIONES.md` §1.7, comprobados con los fondos nuevos:

| Estado | Icono (SF Symbols) | Claro | Contraste (fondo · superficie · bandeja) | Oscuro | Contraste (fondo · superficie · elevada) |
|---|---|---|---|---|---|
| Bien (En ritmo, Hecho, Cobrada) | `checkmark.circle.fill` | `#00786E` | 4,92 · 5,37 · 4,51 | `#59C1B5` | 9,72 · 8,41 · 7,42 |
| Atención (vence pronto, quieta, falta un dato) | `exclamationmark.triangle.fill` | `#C33900` | 4,93 · 5,38 · 4,51 | `#FF946C` | 9,70 · 8,40 · 7,41 |
| Mal (En alerta, vencida, bloqueada) | `xmark.octagon.fill` | `#D01C36` | 4,93 · 5,38 · 4,52 | `#FF928D` | 9,75 · 8,44 · 7,44 |
| Sin dato · Sin meta | `minus.circle` | `#6A6A70` | 4,93 · 5,37 · 4,51 | `#B0B0B6` | 9,73 · 8,42 · 7,43 |

**Pastilla de estado:** fondo del color del estado al 10 % (claro) o al 18 % (oscuro), icono en el color del
estado y **la palabra en `texto`**. Con la palabra en el color del estado, sobre el tinte y sobre el fondo, el
contraste bajaría a 4,2 en claro; así pasa siempre y el color sigue estando en el icono y el tinte.

### 1.7 Áreas reajustadas

**Por qué cambian.** Con el violeta como secundario y el magenta como chispa, tres áreas chocaban con la marca:
Dirección era violeta (el mismo tono que el secundario), Marca era magenta (se leería como un aviso junto a
«Decisiones 3») y Entrega era azul (a 20° del azul noche). Se recolocan en los huecos libres del círculo de
color, sin tocar las otras tres más que en el tono, y **conservando el orden de luminosidad de
`DIRECCIONES.md` §1.7** (Dirección → Equipo → Entrega → Marca → Ventas → Finanzas, de más oscura a más clara),
para que también se distingan en gris o con daltonismo.

| Área | Antes | Ahora | Por qué este |
|---|---|---|---|
| 1 · Dirección | Violeta | **Ciruela** | Sigue en la familia morada de siempre, pero 37° más hacia el rojo y 13 puntos más oscura que el violeta secundario: el violeta es eléctrico y azulado, la ciruela es vino. Es el área más cercana a la marca, y se nota |
| 6 · Equipo | Rojo | **Granate** | Más oscuro y apagado que el carmín de «Mal», para que el rojo vivo quede para los avisos de estado |
| 3 · Entrega | Azul | **Petróleo** | Azul verdoso: conserva el «azul» de Entrega, pero se separa 45° del azul noche, sobre todo en oscuro, donde el azul de los botones es lavanda |
| 5 · Marca | Magenta | **Oliva** | El magenta pasa a ser la chispa. El oliva es el único hueco libre lejos de la marca y de los estados, y queda entre el ámbar y el verde a la misma distancia de los dos |
| 2 · Ventas | Verde | Verde | Sin cambio de tono |
| 4 · Finanzas | Ámbar | Ámbar | Sin cambio de tono |

**Valores** (contraste: el peor de los tres fondos de cada modo; «glifo»: el blanco sobre el relleno claro y
`#0F1430` sobre el relleno oscuro):

| Área | Tinta en claro (texto, iconos) | Relleno en claro (icono de app, punto, barra, serie) | Tinta en oscuro | Relleno en oscuro |
|---|---|---|---|---|
| 1 · Dirección (ciruela) | `#6B0C68` · 9,39 · L* 25 | `#791E74` · 7,83 · glifo 9,33 · L* 30 | `#DE7ED6` · 6,16 · L* 66 | `#BE61B7` · 4,26 · glifo 4,80 · L* 55 |
| 6 · Equipo (granate) | `#841A2E` · 8,13 · L* 29 | `#952C3C` · 6,52 · glifo 7,77 · L* 35 | `#FC8992` · 6,97 · L* 70 | `#E1717B` · 5,23 · glifo 5,89 · L* 61 |
| 3 · Entrega (petróleo) | `#0A546B` · 7,07 · L* 33 | `#0F6681` · 5,45 · glifo 6,49 · L* 40 | `#4CC3ED` · 7,89 · L* 74 | `#32AED7` · 6,24 · glifo 7,03 · L* 66 |
| 5 · Marca (oliva) | `#575B0B` · 6,07 · L* 37 | `#6D7010` · 4,44 · glifo 5,28 · L* 46 | `#C1C75D` · 8,85 · L* 78 | `#B1B74C` · 7,44 · glifo 8,38 · L* 72 |
| 2 · Ventas (verde) | `#106F49` · 5,20 · L* 41 | `#178A5C` · 3,65 · glifo 4,35 · L* 51 | `#72E1A9` · 9,97 · L* 82 | `#65D49E` · 8,75 · glifo 9,86 · L* 78 |
| 4 · Finanzas (ámbar) | `#925E10` · 4,60 · L* 45 | `#B87817` · 3,07 · glifo 3,66 · L* 56 | `#FDCF9B` · 11,13 · L* 86 | `#FDC483` · 10,23 · glifo 11,52 · L* 83 |

**Distancias comprobadas:**
- **Luminosidad (ΔL\*) mínima entre dos áreas:** rellenos 5,0 en claro y 5,4 en oscuro; tintas 3,3 y 3,9. En
  gris, los rellenos se distinguen; las tintas van siempre con el nombre del área.
- **Entre áreas (ΔE2000):** 20 como mínimo (Marca y Finanzas), en claro y en oscuro.
- **Frente a la marca:** 19,1 como mínimo en claro (Equipo y el magenta; Dirección queda a 19,2 del azul noche
  y a 19,7 del violeta) y 13,9 en oscuro (Equipo y el magenta de texto). Por encima de 10 se ven como colores distintos a simple vista.
- **Frente a los estados:** Equipo y «Mal» quedan a 12,2 (claro) y 9,9 (oscuro); Ventas y «Bien», a 12,9. Es la
  misma cercanía que ya se aceptó en `DIRECCIONES.md` §1.7: un área es siempre un icono con su nombre y un
  estado es siempre una pastilla con icono y palabra. Si prefieres separarlos más, pregunta 2 de §10.

**Cómo se usan** (sin cambios respecto a v1):
- Cada área es un **icono de app**: cuadrado de 24 pt (radio 7) con el relleno y el glifo blanco en claro o
  `#0F1430` en oscuro. Sobre la cabecera azul noche, el cuadrado es blanco y el glifo va en la tinta del área.
- El nombre del área va en `texto`; la tinta solo se usa para texto cuando el color ayuda a encontrarla (la
  cabecera de columna en «Ritmo por área»).
- En las gráficas, cada área conserva su forma de marcador (`DIRECCIONES.md` §1.4).

### 1.8 Aumentar contraste y Reducir movimiento

| Ajuste del Mac | Claro | Oscuro |
|---|---|---|
| Aumentar contraste | `textoSecundario` → `#3F4563` (8,58); `separador` → `bordeControl`; mosaicos con borde de 1 pt en `texto` al 20 %; rellenos de área → sus tintas; insignia → `#C4006B` (blanco 5,90); anillo de foco de 3 pt | `textoSecundario` → `#BCC1DD` (10,22); `separador` → `bordeControl`; bordes de 1 pt en blanco al 24 %; rellenos de área → sus tintas; el destacado lleva borde blanco al 24 % |
| Reducir movimiento | Sin temblor (borde discontinuo), sin desplazamientos al entrar un nivel: fundidos de 0,15 s | Igual |
| Reducir transparencia | No cambia nada: todo es sólido | Igual |

### 1.9 Tipografía

Las tres son de Google Fonts con licencia OFL y van **dentro de la app** (sin internet). Space Grotesk para
títulos y cifras grandes; DM Sans para toda la interfaz y el texto; JetBrains Mono solo para códigos y «Ver como
texto».

| Estilo | Familia | Peso | Tamaño / interlínea (pt) | Uso |
|---|---|---|---|---|
| `cifraHoy` | Space Grotesk, cifras tabulares | 600 | 56 / 60 | Número clave en el destacado de un área |
| `cifraGrande` | Space Grotesk, tabulares | 600 | 40 / 44 | Destacado de ficha, módulo Grande |
| `cifraMedia` | Space Grotesk, tabulares | 600 | 28 / 32 | Módulo Pequeño, totales, dato protagonista en la vista previa |
| `tituloPantalla` | Space Grotesk | 700 | 28 / 34 | Título de área, base y ficha (en la cabecera) |
| `tituloSeccion` | Space Grotesk | 600 | 20 / 26 | Bloques de Resumen y secciones `##` de Notas |
| `tituloModulo` | Space Grotesk | 500 | 15 / 20 | Título de mosaico, columna de tablero, vista previa |
| `lectura` | DM Sans | 400 | 15 / 23 | Notas, descripciones, actas |
| `interfaz` | DM Sans | 400 · 500 | 13 / 18 | Filas, celdas, menús, migas, barra lateral (500) |
| `interfazFuerte` | DM Sans | 600 | 13 / 18 | Botones, pestañas, título de fila |
| `secundario` | DM Sans | 400 | 12 / 16 | Líneas de contexto, «Sale de…», contadores |
| `rotulo` | DM Sans, mayúsculas, +4 % de espaciado | 600 | 11 / 14 | Secciones de la barra lateral, cabeceras de columna |
| `cifraFila` | DM Sans, cifras tabulares | 500 | 13 / 18 | Importes y fechas en tablas, alineados a la derecha |
| `codigo` | JetBrains Mono | 500 | 12 / 16 | T-0041, F-2026-0014, FI1, FIN-AR |
| `textoPlano` | JetBrains Mono | 400 | 13 / 20 | «Ver como texto» (⌘E) |

- Texto del 85 al 200 % (Ajustes › Visualización), como fija `DIRECCIONES.md` §1.6: las filas pasan a dos
  líneas, los mosaicos se recolocan y las migas se pliegan antes.
- Por debajo de 15 pt, las cifras van en DM Sans: Space Grotesk se reserva para tamaños grandes.
- Hay que comprobar que los ficheros incluidos traen cifras tabulares (`tnum`) en Space Grotesk y DM Sans.

### 1.10 Forma, sombras, espacio y densidad

| Qué | Valor |
|---|---|
| Radios | mosaico, cabecera y destacado 22 · bloque interior y tarjeta de tablero 14 · vista previa y ventana flotante 16 · hoja 20 · fila y campo 10 · botones, chips, pestañas e insignias en cápsula · icono de área 7 (24 pt) y 9 (32 pt) · avatar redondo |
| Sombra 1 (mosaicos, en claro) | `0 1 2` de `#0F1430` al 4 % y `0 6 16` al 6 % |
| Sombra 2 (vista previa, menús, tarjeta levantada, en claro) | `0 2 6` al 8 % y `0 12 32` al 14 % |
| En oscuro | Sin sombra en el nivel 1, con borde de 1 pt blanco al 8 %; en el nivel 2, `superficieElevada` con borde blanco al 12 % y sombra `0 12 32` negra al 50 % |
| Espacio | Base de 4 pt: 4 · 8 · 12 · 16 · 20 · 24 · 32 · 48 |
| Márgenes | 24 pt de margen de pantalla (16 por debajo de 900 pt de ancho) · 12 pt entre mosaicos · 16 pt de relleno en un mosaico pequeño y 20 en uno grande |
| Alturas de fila | Barra lateral 36 · Lista 44 · Tabla 32 (28 en «Compacta») · fila de cabecera de tabla 28 |
| Objetivo mínimo | 28 × 28 pt, también el «−», las asas y la «×» de un chip |
| Materiales | Todo sólido, sin cristal |

### 1.11 Iconos

- **En la app:** SF Symbols, peso medio, 17 pt en la barra lateral y en la barra de herramientas, 15 pt en
  filas y 13 pt en chips y migas. Las áreas, en variante rellena dentro de su icono de app.
- **En las maquetas:** iconos de trazo de 24 × 24 con trazo de 1,8 y extremos redondos (los de la maqueta v1),
  y versión rellena para las áreas.

| Qué | SF Symbol | Qué | SF Symbol |
|---|---|---|---|
| Hoy | `sun.max` | Contactos | `person.crop.circle` |
| Decisiones | `signpost.right.and.left` | Empresas | `building.2` |
| Tareas | `checkmark.square` | Oportunidades | `target` |
| 1 · Dirección | `safari.fill` (brújula) | Servicios | `tag` |
| 2 · Ventas | `chart.line.uptrend.xyaxis` | Propuestas | `doc.text` |
| 3 · Entrega | `shippingbox.fill` | Reuniones | `calendar.badge.clock` |
| 4 · Finanzas | `creditcard.fill` | Proyectos | `square.stack.3d.up` |
| 5 · Marca | `sparkles` | Facturas | `eurosign.circle` |
| 6 · Equipo | `person.2.fill` | Gastos | `cart` |
| Asistentes y Mika | `sparkle` | Movimientos | `arrow.left.arrow.right` |
| Carpeta | `folder` | Contenidos | `square.and.pencil` |
| Bases (sección y pantalla) | `tablecells` | Conversaciones | `bubble.left.and.bubble.right` |
| Atrás · Adelante | `chevron.left` · `chevron.right` | Sistemas | `gearshape.2` |
| Pestaña nueva | `plus.square.on.square` | Activos | `cube` |
| Vista previa | `eye` | Roles | `person.text.rectangle` |
| Relacionar | `link` | Objetivos | `scope` |
| Quitar relación | `xmark.circle` | Incidencias | `exclamationmark.bubble` |
| Filtrar · Agrupar · Ordenar | `line.3.horizontal.decrease.circle` · `rectangle.3.group` · `arrow.up.arrow.down` | Rutinas | `arrow.triangle.2.circlepath` |
| Columnas | `slider.horizontal.3` | Planes de entrega | `list.bullet.rectangle` |
| Vistas: Tabla · Tablero · Calendario · Galería · Lista · Cronograma | `tablecells` · `rectangle.split.3x1` · `calendar` · `square.grid.2x2` · `list.bullet` · `chart.bar.doc.horizontal` | Decisiones (base) · Cobros · Borradores | `signpost.right.and.left` · `checkmark.seal` · `envelope` |

Todos existen en macOS 15 (comprobado en el catálogo de símbolos del sistema). Se evita `receipt`, que pide una
versión posterior.

### 1.12 Movimiento

- **Entrar un nivel:** la pantalla nueva entra con fundido y 12 pt de desplazamiento desde la derecha (0,2 s);
  Atrás hace lo contrario. Con «Reducir movimiento», solo fundido.
- **Cambiar de pestaña en una ficha:** fundido de 0,12 s, sin desplazamiento; la altura se ajusta sin saltos.
- **Muelles** de respuesta 0,35 s para mosaicos, tarjetas y la barra lateral, como en v1.
- **Vista previa:** aparece a los 0,6 s con escala de 0,96 a 1 y fundido (0,15 s).

### 1.13 Valores para las maquetas (CSS)

```css
.mosaico {
  --bg:#F3F5FA; --sf:#FFFFFF; --sf2:#FFFFFF; --tray:#E8EBF5; --hd:#1E2A78; --hd-sub:#C3C9EE;
  --tx:#0F1430; --tx2:#545A7A; --sep:#DFE3EE; --bd:#7A819F;
  --pr:#1E2A78; --pr-h:#2B3A99; --pr-p:#151D58; --on-pr:#FFFFFF; --pr-soft:#E8EAF2; --link:#3346C2;
  --vi:#7C3AED; --vi-h:#6D28D9; --vi-p:#5B21B6; --vi-soft:#F2EBFD;
  --mg:#E6007E; --mg-t:#C4006B; --ring:#E6007E;
  --ok:#00786E; --warn:#C33900; --bad:#D01C36; --nod:#6A6A70; --glyph:#FFFFFF;
  --dir-t:#6B0C68; --dir-r:#791E74; --equ-t:#841A2E; --equ-r:#952C3C; --ent-t:#0A546B; --ent-r:#0F6681;
  --mar-t:#575B0B; --mar-r:#6D7010; --ven-t:#106F49; --ven-r:#178A5C; --fin-t:#925E10; --fin-r:#B87817;
  --sh1:0 1px 2px rgba(15,20,48,.04),0 6px 16px rgba(15,20,48,.06);
  --sh2:0 2px 6px rgba(15,20,48,.08),0 12px 32px rgba(15,20,48,.14);
}
.mosaico[data-oscuro="true"] {
  --bg:#000000; --sf:#10142A; --sf2:#1A1F3E; --tray:#0A0D1F;
  --tx:#EEF0FA; --tx2:#9AA1C4; --sep:#252B4D; --bd:#6A72A0;
  --pr:#7C8CFF; --pr-h:#95A2FF; --pr-p:#6577F2; --on-pr:#0B1030; --pr-soft:#232A50; --link:#95A2FF;
  --vi-h:#8B4CF7; --vi-p:#6D28D9; --vi-soft:#281C55; --mg-t:#FF3D9A;
  --ok:#59C1B5; --warn:#FF946C; --bad:#FF928D; --nod:#B0B0B6; --glyph:#0F1430;
  --dir-t:#DE7ED6; --dir-r:#BE61B7; --equ-t:#FC8992; --equ-r:#E1717B; --ent-t:#4CC3ED; --ent-r:#32AED7;
  --mar-t:#C1C75D; --mar-r:#B1B74C; --ven-t:#72E1A9; --ven-r:#65D49E; --fin-t:#FDCF9B; --fin-r:#FDC483;
  --sh1:none; --sh2:0 12px 32px rgba(0,0,0,.5);
}
```

---

## 2. Navegación en profundidad

### 2.1 El modelo

- **Una ventana por empresa** (`PLAN.md` §6.1), con **pestañas del Mac** (⌘T abre una en Hoy). Cada pestaña
  tiene su propio camino y su propio historial.
- **El camino** es lo que se ve en las migas: una **raíz** (lo que elegiste en la barra lateral) y los
  **niveles** por los que has entrado.
- **Raíces:** Hoy · Decisiones · Tareas · un área (con su pestaña) · una base · Todas las bases · Asistentes ·
  Carpeta · un resultado de búsqueda.
- **Niveles:** una ficha (con la pestaña en la que estaba), una base filtrada por lo que vienes viendo («Facturas
  de Arquitectura Nexo») o el texto de un fichero.

| Haces | Pasa |
|---|---|
| Clic en una fila, tarjeta, chip o enlace de otra ficha | **Entras un nivel.** Las migas crecen por la derecha |
| Clic en la barra lateral, en ⌘1–9 o en ⌘K | **Raíz nueva.** Las migas empiezan de nuevo; el historial lo guarda |
| Clic en una miga | Vuelves a ese nivel; lo que quitas queda en Adelante |
| ⌘[ · ⌘] · botones ‹ › | Atrás y adelante por todo el historial de la pestaña, como Finder y Safari. Mantener pulsado ‹ o › enseña los 10 últimos sitios |
| ⌘↑ | Subes al nivel anterior de las migas. Mientras escribes en un campo o en Notas, ⌘↑ hace lo de siempre (ir al principio) |
| ⌘clic | Abre en una **pestaña nueva** de la ventana, detrás; ⇧⌘clic la abre y te lleva a ella |
| ⌥⌘clic | Abre en una ventana nueva |
| Pasar el puntero 0,6 s, o barra espaciadora sobre lo elegido | **Vista previa** sin salir de donde estás (§2.5) |
| Clic derecho en cualquier enlace, fila o miga | Abrir · Abrir en pestaña nueva · Abrir en ventana nueva · Vista previa · Copiar enlace |

**Un solo comportamiento al hacer clic:**
- **En Tabla y Tablero:** clic elige la fila o la tarjeta (y abre su panel si la vista lo tiene, como el de la tarea
  dentro del tablero de un proyecto); doble clic o ↩ entra un nivel; la barra espaciadora abre la vista previa. La
  fila elegida enseña «Abrir la ficha» para entrar con un clic más.
- **En listas, «Conectado con» y los mosaicos del Resumen:** clic entra. Si lo enlazado aún no tiene pantalla (en las
  maquetas, empresa, oportunidad y factura), el clic abre la vista previa con «Abrir» desactivado y su motivo.
- La vista previa flotante es la misma en todas las pantallas.

Reglas:
1. **Sin bucles.** Si entras en una ficha que ya está en las migas (Arquitectura Nexo › Trimestrales ›
   Arquitectura Nexo), las migas se recortan hasta ella en lugar de repetirla.
2. **Cambiar de pestaña dentro de una ficha no es un nivel** ni entra en el historial; pero la ficha recuerda la
   pestaña, y al volver con Atrás o con su miga estás donde la dejaste, con el mismo desplazamiento, filtros y
   selección.
3. **Desde ⌘K, un enlace profundo o una tarjeta de Decisiones**, las migas se siembran con el camino natural de
   la ficha (`Facturas › F-2026-0013`), para que siempre se pueda subir a algo con sentido.
4. **Sin tope de profundidad.** Las migas se pliegan (§2.3).
5. **Al cerrar y abrir la app,** cada pestaña vuelve a su camino.
6. Las fichas se identifican por su `id`, no por su ruta: si alguien renombra o mueve una ficha mientras está en
   tus migas o en tu historial, el camino sigue funcionando.

### 2.2 Qué enseña cada nivel

| Nivel | Ejemplo | Arriba, lo esencial | Debajo | Lo urgente primero |
|---|---|---|---|---|
| Raíz: área | 2 · Ventas | Cabecera azul noche (qué convierte, quién la lleva, su pregunta) y el destacado violeta con el número clave «2» | Pestañas Resumen · Operación · Control · Sistemas y activos (`SISTEMAS.md` §4.2) | Las alertas del área encabezan el Resumen |
| Raíz o nivel: base | Oportunidades | Cabecera baja con la frase de su nota índice y tres cifras («Valor abierto 3.270 €» · «Ponderado 1.773 €» · «Ganadas sobre cerradas: 1 de 2») | Pestañas por estado o por tipo y vistas guardadas; la vista elegida | Lo quieto, vencido o bloqueado sube arriba en el orden por defecto |
| Nivel: ficha | Arquitectura Nexo | Cabecera con identidad, estado y acciones; el destacado con su dato protagonista | Franja «Ahora» (si hay algo) · «Conectado con» · pestañas con contador | Franja «Ahora» |
| Nivel: ficha relacionada | Factura en borrador | El mismo molde | Lo mismo | Lo mismo |

**Principios de «la información adecuada en el momento adecuado»:**
1. **Orden de lectura fijo:** qué es y en qué estado está (cabecera) → lo más importante (destacado) → lo que te
   pide algo ahora (franja «Ahora») → con qué está conectado → todo lo demás, en pestañas.
2. **La pestaña inicial depende del tipo y del estado** (§3.3): se abre donde está el trabajo de ese momento.
3. **Contadores en las pestañas:** cuentan lo abierto; si dentro solo hay cerradas, la pestaña va sin número.
   Si dentro hay algo urgente, el contador lleva delante el icono del estado («Facturas ⚠ 2» se lee «Facturas, 2, 1
   vence hoy»). La insignia magenta solo aparece si dentro hay algo que espera **tu** OK, y siempre con palabra
   («Facturas 1 · Por confirmar 1»); el número del contador nunca va en magenta.
4. **Dentro de cada pestaña:** lo abierto antes que lo cerrado; lo urgente arriba (pide tu decisión → vencido →
   vence hoy o quieto → falta un dato → por fecha); lo cerrado y lo archivado, plegado al final («Cerradas (4)»).
5. **Lo que se calcula no se escribe:** pendiente de cobro, avance, último contacto, días quieta y servicios
   contratados se calculan al momento (`PLANTILLAS.md` §1.4).
6. **Un vacío siempre explica y propone:** nunca un «0» mudo. «Aún no hay proyecto: nace cuando se confirme el
   cobro de la factura inicial (290,40 €, en borrador) · Abrir la factura».

### 2.3 Migas

- **Dónde:** en la barra de la ventana, a la izquierda, después de ‹ ›. Por debajo de 960 pt de ancho bajan a una
  franja de 32 pt bajo la barra.
- **Forma:** cada miga lleva el icono de su tipo (13 pt) y un nombre corto; separadas por `chevron.right` de
  9 pt en `textoSecundario`. La última va en `interfazFuerte` y no es un botón; las demás, en `interfaz` 500
  con fondo `bandeja` al pasar el puntero.
- **La pestaña de origen:** la miga de una ficha lleva detrás, en gris, la pestaña desde la que saliste:
  «Arquitectura Nexo · Oportunidades». Clic en ella vuelve a esa pestaña.
- **Nombre corto, en este orden:**
  1. el número o código si lo tiene (F-2026-0014, T-0041, FI1);
  2. el título sin el nombre de un nivel anterior, ni al principio ni al final («Arquitectura Nexo ·
     Trimestrales» bajo «Arquitectura Nexo» se queda en «Trimestrales»; «Factura a Arquitectura Nexo SLP», en
     «Factura»);
  3. el otro nombre más corto (`aliases`);
  4. recorte a 24 caracteres con «…» al final, y el nombre completo al pasar el puntero.
- **Plegado por espacio:** primero se quita el gris de la pestaña de origen; después, los niveles intermedios se
  juntan en una miga «…» que abre un menú con ellos en orden. Siempre se ven la raíz, la penúltima y la última.
  Si aún no cabe, la penúltima también se pliega; la última, nunca.
- **Menú de cada miga** (clic derecho): Abrir en pestaña nueva · Copiar enlace · en la raíz, Mostrar en la
  barra lateral.
- **VoiceOver:** el grupo se llama «Estás en»; cada miga es un botón «Volver a Empresas».

### 2.4 Pestañas de la ventana

- Son las del Mac: ⌘T nueva (en Hoy), ⌘W cerrar, ⌃Tab y ⌃⇧Tab para pasar de una a otra, y Ventana › Combinar
  todas las ventanas.
- El título de la pestaña es la última miga; el icono, el del tipo.
- Arrastrar una fila, una tarjeta o un chip a la barra de pestañas la abre en una pestaña nueva.
- Todas las pestañas de una ventana son de la misma empresa.

### 2.5 Vista previa

- **Cuándo:** al dejar el puntero 0,6 s sobre un enlace, un chip, una tarjeta o el título de una fila; o con la
  **barra espaciadora** sobre lo elegido en una lista, una tabla o un tablero (como la Vista rápida de Finder).
  Con ↑ y ↓ cambia la selección y la vista previa la sigue. Esc la cierra.
- **Qué enseña** (360 pt de ancho, hasta 320 de alto, `superficieElevada`, radio 16, sombra 2):
  - icono del tipo, título, código y pastilla de estado;
  - el dato protagonista en `cifraMedia` (sin violeta: el destacado es de la pantalla, no de la vista previa);
  - hasta 4 datos secundarios;
  - la primera línea de «Ahora», si la hay;
  - las 3 últimas entradas de su actividad;
  - al pie, «Abrir» (↩) y «En pestaña nueva» (⌘↩).
- **Nunca edita ni escribe nada.** Los enlaces de dentro abren la ficha y cierran la vista previa.
- Desaparece al salir con el puntero, con 0,2 s de margen para poder entrar en ella.
- **Ajustes › Vista previa:** «Al pasar el puntero» (por defecto) · «Solo con la barra espaciadora» · «Al pasar
  con ⌘ pulsado».
- **VoiceOver:** acción «Vista previa» en cada fila y cada chip; lee el resumen.

### 2.6 Un recorrido con Asesoría Ribera

Todo sale del guion (`GUION-MAQUETAS.md` §3.3, §3.5 y §6).

1. Barra lateral › **2 · Ventas**. Migas: «2 · Ventas». Pestaña Operación › Directorio.
2. Clic en **Arquitectura Nexo**. Migas: «2 · Ventas · Directorio › Arquitectura Nexo». La ficha de la empresa
   abre en Resumen:
   - destacado: «Siguiente paso · Emitir la factura inicial · hoy»;
   - «Ahora»: «Factura inicial en borrador · 290,40 € · Revisar y emitir» (es tu foco de hoy) · «T-0040 Revisar
     el contrato · hoy 11:00» · «Aceptó la propuesta el 21 oct: ¿pasarla a Activo? · Confirmar»;
   - pestañas: Resumen · Personas 1 · Oportunidades 1 · Reuniones 1 · Propuestas 2 · Facturas 1 · Tareas 2 ·
     Notas · Actividad · Fichero, y «Más» con Proyectos, Incidencias y Conversaciones, que están vacías.
3. Pestaña **Oportunidades** › «Arquitectura Nexo · Trimestrales». Migas: «… › Arquitectura Nexo ·
   Oportunidades › Trimestrales». Como está **Aceptada**, abre en **Facturas**; el destacado dice «621 €
   ponderado (690 € al 90 %)» y la franja «Conectado con» enseña «Proyecto: nace al confirmar el cobro».
4. Clic en la factura. Migas: «… › Trimestrales · Facturas › Factura». Destacado «290,40 €»; barra fija
   «Revisar y emitir».
5. ⌘[ dos veces: vuelves a Arquitectura Nexo en la pestaña Oportunidades, donde estabas (cambiar de pestaña
   no cuenta como paso). Un ⌘[ más te deja en Ventas › Directorio. ⌘] adelanta.
6. ⌘clic en el chip «Sergio Nexo» de la oportunidad: se abre su ficha en una pestaña nueva, detrás.
7. Barra espaciadora sobre «Propuesta v1» en la pestaña Propuestas: vista previa sin moverte.

Con la ventana estrecha, las migas del paso 4 quedan: «2 · Ventas › … › Trimestrales › Factura».

**El recorrido que siguen las maquetas M2 (Jorge Martín, Talleres Martín e Hijos SL):**

1. **Hoy** (`M2-Hoy`). La decisión «¿Confirmas el cobro de Talleres Martín?» lleva «Ver a Jorge Martín»; al decidir
   «Confirmar el cobro», «Abrir el proyecto». El módulo «Cobros por confirmar» lleva a lo mismo.
2. **2 · Ventas** (`M2-Contacto`, estado «2 · Ventas»). «Abrir Contactos».
3. **Base Contactos** (`M2-Bases#contactos`). Clic en Jorge Martín lo elige; «Abrir la ficha» (o doble clic) entra.
4. **Jorge Martín** (`M2-Contacto`). Migas «2 · Ventas › Contactos › Jorge Martín». Destacado «Confirmar el cobro ·
   hoy · pide tu decisión». Confirmar con la opción recomendada hace nacer «Trimestrales 2026» **En curso**, con las
   6 tareas de su plan; el destacado pasa a «Revisar la petición de documentos a Jorge · hoy».
5. **Pestaña Proyectos** (`M2-Contacto#confirmado-proyectos`). «Trimestrales 2026 · En curso · Nuevo». Clic entra.
6. **Trimestrales 2026** (`M2-Proyecto`). Migas «2 · Ventas › Contactos › Jorge Martín · Proyectos › Trimestrales
   2026»; ⌘[ vuelve a Jorge en la pestaña Proyectos. Abre en Tareas, con T-0042 elegida en su panel.
7. **T-0042** (`M2-Proyecto#T-0042`, y «Abrir como ficha» entra un nivel más): el correo a Jorge espera tu OK.

El estado viaja en la dirección de la página (`#contactos`, `#confirmado-proyectos`, `#T-0042`, `#buscar`), así
Atrás y las migas devuelven al sitio donde estabas. Empresa, oportunidad y factura aún no tienen maqueta: se ven en
vista previa y se abren en su base.

---

## 3. La ficha

### 3.1 Anatomía

De arriba abajo, en la rejilla de 4 columnas del mosaico:

1. **Cabecera** (3 columnas, azul noche, radio 22, de 132 a 168 pt de alto):
   - identidad: avatar de 44 pt (iniciales o logo para personas y empresas; icono del tipo en blanco al 20 %
     para lo demás), rótulo «Empresa · 2 · Ventas», título en `tituloPantalla` blanco, la línea de resumen
     (`> …` de la nota) en `subtituloCabecera` y el código en `codigo`;
   - estado: pastilla blanca editable (clic → menú con los estados posibles; los que no se pueden elegir salen
     desactivados con su motivo) y hasta 3 datos clave;
   - acciones, a la derecha: la principal (botón blanco con texto azul noche), «Nuevo ▾» con los «+ Nuevo…» de
     esa ficha y «⋯» (Ver como texto ⌘E · Propiedades ⌥⌘I · Abrir en pestaña nueva · Copiar enlace · Mostrar
     en Finder · Renombrar · Archivar).
2. **Destacado** (1 columna, violeta, misma altura): el dato protagonista y, si la tiene, su acción. Por debajo
   de 900 pt de ancho pasa bajo la cabecera.
3. **Franja «Ahora»** (solo si hay algo): hasta 3 líneas, cada una con su icono de estado, una frase y un botón.
   Orden: pide tu decisión → vencido → vence hoy o quieto → falta un dato que bloquea → siguiente paso con fecha.
4. **«Conectado con»:** chips de las relaciones de uno a uno de esta ficha (las que guarda ella y las que se
   calculan, como «Servicios contratados»). Cada chip: icono del tipo, nombre corto y punto de estado; «×» al
   pasar el puntero; «+ Relacionar» al final. Una relación obligatoria vacía sale como chip «Falta empresa» en
   Atención.
5. **Pestañas** en cápsula, desplazables: Resumen · lo relacionado por tipo · Notas · Actividad · Fichero, con
   contador. Las de lo relacionado que están vacías van a «Más ▾» (salvo las que tienen un «+ Nuevo» propio del
   momento). ⌃1–⌃9 saltan a cada pestaña.
6. **Contenido de la pestaña.**
7. **Barra fija abajo,** solo en los documentos (factura, propuesta, presupuesto, contrato, recibo): acción
   principal, «Vista previa PDF» y «Ver como texto» (`DIRECCIONES.md` §1.5).
8. **Inspector** a la derecha (⌥⌘I): todas las propiedades como formulario, «Enlazan aquí» (desde el texto de
   otras notas) y «Menciones sin enlazar».

### 3.2 Las pestañas comunes

- **Resumen:** mosaicos fijos por tipo (en la v1 no se editan): propiedades clave editables (6 como mucho),
  siguiente paso, lo último (3 entradas de actividad), un minimosaico por relación con sus 3 primeras filas y
  «Ver las N», y la frase literal del cliente si la hay (destacada como cita).
- **Contadores:** cuentan lo abierto (oportunidades sin cerrar, reuniones previstas, facturas sin cobrar, tareas sin
  hacer); si solo hay cerradas, sin número. Lo que espera tu OK lleva además la insignia magenta con palabra (§2.2).
- **Una pestaña por cada tipo relacionado:** Lista por defecto, con conmutador Lista · Tabla (más Tablero en
  Tareas y Calendario en Reuniones). Arriba a la derecha: «+ Nueva …» (crea la ficha ya enlazada),
  «Añadir existente…» (selector de relación, §5) y «Ver en la base» (entra un nivel: la base filtrada por esta
  ficha).
- **Notas:** el texto de la nota, un bloque plegable por cada `##`, editable en el sitio. Las «Guía:» se ven como
  pista en gris hasta que escribes. Los `[falta: …]` son pastillas «Falta». En las fichas sin sección
  «Actividad», «Añadir nota» escribe una línea con fecha al final de «## Notas» (`2026-10-21 · …`), el formato
  que ya usa el guion.
- **Actividad:** línea de tiempo con los cambios de propiedades (de las versiones), las entradas de
  «## Actividad» (tareas, decisiones, incidencias), los eventos que la tocan, los trabajos de los asistentes y
  los borradores. Filtros Todo · Comentarios · Cambios · Asistentes.
- **Fichero:** la ruta, «Ver como texto» lado a lado, las versiones (`SISTEMAS.md` §5.8), los adjuntos (PDF
  generados, `Materiales/`), los enlaces que salen de esta nota y su salud, Mostrar en Finder y Abrir en
  Obsidian.

**«Fichero» y no «Archivo».** En la app, «Archivar» y la carpeta `Archivo/` significan retirar. Una pestaña
llamada «Archivo» se leería como «lo archivado». Ver pregunta 5 de §10.

### 3.3 Pestaña con la que abre cada ficha

| Ficha | Estado | Abre en |
|---|---|---|
| Contacto y empresa | Cualquiera | Resumen |
| Oportunidad | Prospecto · Diagnóstico | Reuniones |
| | Propuesta | Propuestas |
| | Aceptada | Facturas |
| | Ganada | Resumen (con su proyecto en «Conectado con») |
| | Perdida · Pausada | Notas (motivo) |
| Proyecto | Sin empezar | Resumen (el traspaso: 6 piezas Sí o Falta) |
| | En curso · Pausado | Tareas (con la franja «Fases del plan» encima); Viaje si el servicio tiene sesiones |
| | Cerrado · Archivado | Resumen (cierre y margen) |
| Reunión | Prevista | Resumen (ficha previa y preguntas guía) |
| | Hecha | Notas, con «Acciones» arriba |
| Factura | Cualquiera | Resumen (el documento) |
| Tarea | Cualquiera | Actividad |
| Sistema | Cualquiera | Resumen (Cómo va) |

Si ya habías abierto esa ficha en esta pestaña de la ventana, vuelve a la última pestaña que usaste. Si llegas
desde un aviso o una decisión, abre en la pestaña de lo que te pide.

### 3.4 Fichas concretas

| Ficha | Destacado (violeta) | Cabecera: 3 datos | Conectado con | Pestañas, en este orden | Acción principal | «Nuevo ▾» |
|---|---|---|---|---|---|---|
| **Empresa** (nodo central) | Siguiente paso con fecha; debajo, «Pendiente de cobro» si lo hay | Relación · Personas · Cliente desde | Servicios contratados (calculado) · Llegó por (recomendación o pieza) | Resumen · Personas · Oportunidades · Reuniones · Propuestas · Proyectos · Facturas · Tareas · Incidencias · Conversaciones y casos · Notas · Actividad · Fichero | Escribir un correo (borrador) | Reunión (descubrimiento si está Interesado, seguimiento si está Activo) · Propuesta · Proyecto · Factura · Persona · Tarea |
| **Contacto** | Siguiente paso con fecha | Relación · Verificado · Cargo en su empresa | Empresa · Recomendado por · Conversación de origen | Resumen · Oportunidades · Reuniones · Propuestas · Proyectos · Facturas · Tareas · Conversaciones · Notas · Actividad · Fichero | Escribir un correo (borrador) | Reunión · Propuesta · Proyecto · Factura · Tarea |
| **Oportunidad** | Valor × probabilidad («621 € ponderado · 690 € al 90 %») | Etapa · Días en la etapa · Responsable | Empresa · Contacto · Servicio · Versión de oferta · Conversación · Recomendado por · Proyecto (único) | Resumen · Reuniones · Propuestas · Facturas · Tareas · Notas · Actividad · Fichero | Según etapa: Preparar la reunión de descubrimiento · Generar el borrador de propuesta · Preparar seguimiento · Revisar y emitir la factura inicial · Abrir el proyecto | Reunión · Propuesta · Presupuesto · Tarea |
| **Proyecto** | Con sesiones: sesiones hechas sobre incluidas, en anillo. Sin sesiones: tareas hechas sobre las del plan. Debajo, % cobrado | Fase · Responsable · Próxima sesión (o próximo vencimiento) | Empresa · Contacto · Oportunidad · Servicio · Plan de entrega · Portal | Resumen · Viaje (solo con sesiones) · Tareas · Reuniones · Facturas · Materiales · Notas · Actividad · Fichero; en «Más», Incidencias e Informes mientras estén vacías | Preparar kit de la próxima sesión, o lo que pide tu OK | Tarea · Seguimiento · Acta de sesión · Incidencia · Factura del hito · Informe |
| **Tarea** | Estado y vencimiento con su acción (Empezar ahora · Marcar como hecha) o el estado vivo del asistente | Número · Área · Responsable | Proyecto u oportunidad · Empresa · Tarea madre · Bloqueada por · Bloquea a · Función | Actividad · Subtareas · Fichero | Empezar ahora · Marcar como hecha | Subtarea |
| **Reunión** | Fecha y hora con cuenta atrás («mañana 10:00») o «Hecha · 14 oct · 60 min» | Tipo · Duración · Lugar | Oportunidad o proyecto · Empresa · Personas · Servicio | Resumen · Notas · Tareas · Propuestas · Actividad · Fichero | Prevista: Abrir la ficha previa · Hecha: Convertir acciones en tareas · Descubrimiento hecha: Generar el borrador de propuesta | Tarea · Propuesta |
| **Factura** | Total («290,40 €» · «Borrador · se numera al emitir») | Estado · Número o «Se numera al emitir» · Creada | Empresa · Oportunidad · Proyecto · Rectifica | Resumen · Cobros · Envíos · Actividad · Fichero | Según estado: Revisar y emitir · Preparar envío · Confirmar cobro · Preparar recordatorio | Rectificativa (solo emitida) |
| **Sistema** | Número clave frente a meta («100 %» · «3 de 3 facturas de encargo cobradas a tiempo desde julio») | Estado · Quién lo lleva · Revisado hace | Área · Rol · Número clave · Conexiones · Recibe de · Entrega a | Resumen · Pasos · Ejecuciones · Plantillas y activos · Procedimientos · Referencias y ejemplos · Aprendido · Notas · Actividad · Fichero | Probar con un caso | Procedimiento · Activo · Plantilla |

Detalles por ficha:

- **Empresa y contacto, el nodo central.** Todo lo que los enlaza se agrupa por relación con nombre, no en una
  lista genérica (`SISTEMAS.md` §4.4). Las iniciales o el logo pasan al avatar de la cabecera; el destacado es
  el **siguiente paso**, que es lo que se hace con un cliente (cambio respecto a `PLANTILLAS.md` §1.7). Los
  cuatro «+ Nuevo» de siempre (reunión, propuesta, proyecto, factura) crean la nota ya enlazada con empresa,
  contacto, oportunidad y servicio, y si hay varias oportunidades abiertas preguntan cuál.
- **Oportunidad.** Bajo la cabecera, la línea de etapas Prospecto → Diagnóstico → Propuesta → Aceptada → Ganada,
  con Perdida y Pausada aparte. Clic en una etapa la cambia; Ganada sale bloqueada con su motivo mientras no haya
  cobro confirmado (`GUION-MAQUETAS.md` §5). La pestaña «Propuestas» reúne propuestas, presupuestos y el
  contrato, con su versión.
- **Proyecto.** Bajo la cabecera va, fija, la franja **«Fases del plan»**: una pieza por fase con sus fechas, su
  estado y la línea «hoy» en magenta; clic en una fase filtra el tablero de Tareas. En curso, la ficha abre en
  **Tareas**: tablero por estado (o por fase) y, a la derecha, el **panel de la tarea elegida** con sus propiedades
  editables (estado, prioridad, responsable, fechas, proyecto con «Cambiar…»), su descripción, el borrador que
  espera tu OK y su actividad; «Abrir como ficha» entra un nivel. ⌥⌘I cambia ese panel por el de propiedades del
  proyecto (todas, «Enlazan aquí» y «Menciones sin enlazar»). «Viaje» es la fila de sesiones S1–S9 con su estado
  (Pendiente, Programada, Kit listo, Hecha, No incluida) y su fecha, agrupada por las fases del plan de entrega, y
  solo sale en los servicios con sesiones (Trimestrales no las tiene). «Portal» se ve en vista interna o en vista
  cliente (sin notas internas, responsable ni correos). «Materiales» es una galería de la carpeta. Las relaciones
  se editan también desde aquí: «Añadir existente…» en Tareas y Reuniones escribe «proyecto» en la tarea o la
  reunión, y «Quitar de Trimestrales 2026» lo vacía sin borrar nada.
- **Tarea, con actividad como en un gestor de incidencias pero con la cara de Mosaico.** Dos columnas: a la
  izquierda, «Descripción» (lo único editable del cuerpo) y la línea de tiempo (cambios de estado en una línea
  compacta, comentarios con autor y hora, trabajos de asistente como tarjeta con resumen, uso y «Detalle
  técnico» plegado, aprobaciones con enlace a Decisiones) con la caja de comentario al pie (con @ se menciona a
  un asistente, que retoma la tarea); a la derecha, el panel fijo de propiedades (Estado, Prioridad,
  Responsable, Planificada, Vence, Estimación y dedicadas, Área en solo lectura con «Mover a…»). Las reglas de
  `PLAN.md` §4 y §6.4 no cambian: ningún asistente pone Hecha ni Cancelada.
- **Reunión.** Prevista: arriba «Antes de la reunión» (ficha previa), las preguntas guía y lo pendiente del
  seguimiento anterior. Hecha: «Acciones» arriba con «Convertir en tareas» (cada acción, una casilla; al
  confirmar nacen las tareas enlazadas), luego «Qué se habló» y «Decisiones».
- **Factura.** El documento de `GUION-MAQUETAS.md` §6.1 con su línea de estados Borrador → Emitida → Enviada →
  Cobrada. «Cobros» enseña recibos y movimientos conciliados; «Envíos», los borradores de correo y lo enviado.
  Una factura emitida no se edita: el «⋯» ofrece «Rectificar».
- **Sistema.** El Resumen son los 5 mosaicos de «Cómo va» y la minigráfica recorrible de `GUION-MAQUETAS.md`
  §6.2; «Pasos» es la tabla con quién y en qué modo, con candado en «Siempre con tu OK»; «Ejecuciones» son las
  tareas y documentos que salieron de él (calculado, no se escribe).

---

## 4. Bases

### 4.1 En la barra lateral y en «Todas las bases»

- **Sección «Bases»** en la barra lateral, entre Áreas y Asistentes. Por defecto fija 6: Contactos · Empresas ·
  Oportunidades · Proyectos · Reuniones · Facturas, cada una con el icono de app de su área, su nombre y su
  número de fichas abiertas a la derecha. La última fila es **«Todas las bases»** (⇧⌘B). Se personaliza como el
  resto de la barra (§6): reordenar, ocultar, fijar en favoritos.
- **Tareas no se repite:** ya está arriba, junto a Hoy y Decisiones.
- **Pantalla «Todas las bases»:** un mosaico por área (más «Comunes»), con una pieza por base: icono, nombre,
  número de fichas, la frase de su nota índice, lo urgente en una línea con su icono («2 quietas», «1 vence
  hoy») y el último cambio. Arriba, un buscador que filtra las bases por nombre. Cada pieza tiene en su menú:
  Abrir · Abrir en pestaña nueva · Fijar en la barra · Nueva… Las bases de módulos apagados salen al final en
  «Apagadas», con «Encender el módulo».

### 4.2 Catálogo

Las plantillas no salen nunca en ninguna base.

| Base | Qué guarda | Hogar | Área | Vista por defecto | Pestañas | Columnas de serie |
|---|---|---|---|---|---|---|
| Contactos | `contact` | `2 · Ventas/Contactos/` | Ventas | Tabla | Por `estado`: Activos · Interesados · Antiguos clientes · Archivados | Nombre · Empresa · Relación · Estado · Último contacto · Siguiente paso |
| Empresas | `organization` | `2 · Ventas/Empresas/` | Ventas | Galería (logo o iniciales) | Por `estado` | Nombre · Tipo · Relación · Estado · Proyectos activos · Pendiente de cobro |
| Oportunidades | `opportunity` | `2 · Ventas/Oportunidades/` | Ventas | Tablero por etapa | — (Perdida y Pausada plegadas) | Título · Empresa · Servicio · Etapa · Valor · Prob. · Días quieta · Siguiente paso |
| Servicios | `service` | `2 · Ventas/Productos/` | Ventas | Galería | Por `estado`: Activos · En pruebas · Retirados | Nombre · Precio · Estado · Clientes activos · Ingresos del año |
| Propuestas | `proposal`, `quote`, `agreement` | `2 · Ventas/Oportunidades/<slug>/` | Ventas | Tabla | Por `estado` | Referencia · Empresa · Tipo · Versión · Total · Estado · Válida hasta |
| Reuniones | `meeting` | `Reuniones/` de cada oportunidad, proyecto o área | Ventas y Entrega | Calendario (semana) | Por `tipo`: Descubrimiento · Seguimiento · Sesión · Interna | Fecha · Título · Empresa · Tipo · Estado · Acciones pendientes |
| Proyectos | `project` | `3 · Entrega/Proyectos/` y `Proyectos/` de cada área | Entrega | Tabla (y Cronograma) | Por `estado`, Archivados al final | Nombre · Empresa · Fase · Avance · Cobrado · Próxima sesión · Responsable |
| Planes de entrega | `delivery_template` | `3 · Entrega/Planes de entrega/` | Entrega | Lista | — | Nombre · Servicio · Días · Sesiones |
| Incidencias | `incident` y filas de `Incidencias.md` | `Proyectos/<slug>/` | Entrega | Tablero por estado | Por `gravedad` | Número · Título · Proyecto · Gravedad · Plazo · Estado |
| Tareas | `task` | `Tareas/` de cada área y proyecto | Todas | Lista agrupada por estado (y Tablero) | Lo mío · Hoy · Semana · Vencidas · Sin programar | Número · Título · Área · Proyecto u oportunidad · Responsable · Planificada · Vence |
| Facturas | `invoice` | `4 · Finanzas/Fiscal/` | Finanzas | Tabla | Por `estado`: Borradores · Emitidas · Enviadas · Cobradas · Rectificadas | Número · Empresa · Fecha · Vence · Total · Estado · Cobrado |
| Cobros | `receipt` y filas de `pagos.csv` | `Ingresos/Cobros/` y `Registros/` | Finanzas | Tabla | — | Fecha · Factura · Empresa · Importe · Movimiento |
| Gastos | filas de `recibidas.csv` | `4 · Finanzas/Registros/` | Finanzas | Tabla | Por categoría | Fecha · Proveedor · Base · IVA · Total · Categoría |
| Movimientos | filas de `movimientos.csv` | `Registros/Bancos/<cuenta>/` | Finanzas | Tabla | Sin conciliar · Conciliados | Fecha · Concepto · Importe · Saldo · Conciliado con |
| Contenidos | `content` | `5 · Marca/Contenidos/` | Marca | Calendario (mes) y Tablero | Por `tipo` | Título · Tipo · Canal · Estado · Fecha de publicar |
| Conversaciones | `conversation` | `5 · Marca/Conversaciones/` | Marca | Lista | — | Contacto · Pieza de origen · Canal · Fecha · Oportunidad |
| Sistemas | `system` | `N · Área/Sistemas/` | Todas | Lista agrupada por área | Por `estado` | Código · Nombre · Área · Estado · Número clave · Revisado · Pasos sin ti |
| Activos | `asset` | `N · Área/Activos/` | Todas | Galería | Por área | Nombre · Sistema · Estado · Último uso · Buen ejemplo |
| Roles | `role` | `6 · Equipo/Roles/` | Equipo | Galería | Personas · Asistentes | Rol · Ocupante · Áreas · Sistemas |
| Decisiones | `decision` y líneas de `Decisiones.md` | `1 · Dirección/` | Dirección | Lista por fecha | Por `estado` | Fecha · Decisión · Área · Afecta a · Revisar el |
| Objetivos | `objective` | `1 · Dirección/Objetivos/` | Dirección | Galería con anillos | Por trimestre | Objetivo · Cifra · Meta · Ritmo |
| Rutinas | `routine` | `1 · Dirección/Rutinas/` | Dirección | Lista | — | Rutina · Próxima · Último veredicto |
| Colaboraciones | `collaboration` | `6 · Equipo/Colaboraciones/` | Equipo | Lista | Por `estado` | Colaborador · Proyecto · Estado · Desde |
| Borradores | `draft` | `N · Área/Borradores/` | Todas | Lista | Pendientes de tu OK · Enviados | Para · Asunto · Tipo · Preparado por · Estado |

Objetivos está apagado en The Last (decisión A) y sale en «Apagadas».

### 4.3 Pantalla de una base

1. **Cabecera** azul noche, más baja (96 pt): icono, nombre, la frase de la nota índice («Editar descripción»
   abre la nota) y tres cifras de resumen. Sin destacado.
2. **Pestañas** por la propiedad de `pestanas_por` (en el orden del diccionario, más «Todas»; lo archivado en la
   última y fuera de «Todas», `SISTEMAS.md` §1.4) y, tras un separador, las **vistas guardadas**, con «+» para
   guardar la vista actual.
3. **Barra de la base** (se queda fija al desplazar): conmutador de vista · buscador (⌘F) · Filtrar · Agrupar ·
   Ordenar · Columnas (solo en Tabla) · «+ Nueva …» (principal, ⌘N dentro de la base).
4. **Filtros activos** como chips bajo la barra: «Estado es Activo ×», «Responsable es Lucía ×», «Quitar todos».
5. **Contenido** en la vista elegida.
6. **Pie:** «Sale de 14 fichas en 2 · Ventas/Oportunidades» y, con el módulo encendido, «Exportar a Obsidian».

### 4.4 Las vistas

| Vista | Cómo es | Editar desde ella |
|---|---|---|
| **Tabla** | Columnas del diccionario; clic en la cabecera ordena; se arrastran para reordenar; clic derecho en la cabecera: Ocultar · Agrupar por esta · Filtrar por esta · Ajustar ancho. Grupos plegables con subtotal. Pie opcional con suma o recuento por columna | Doble clic o ↩ en la celda; Tab pasa a la siguiente; Esc cancela; ⌘Z deshace |
| **Tablero** | Una columna por valor de la propiedad de agrupación (estado por defecto), en `bandeja`, con número y suma; tarjetas `superficie` de radio 14 con título, 3 datos y distintivos; columnas plegadas al final | Arrastrar cambia esa propiedad, con sus reglas (Ganada bloqueada). Sin arrastrar: «Mover a… ›» y ⌘← ⌘→. «+» al pie de cada columna crea con ese valor |
| **Calendario** | Mes o semana, sobre la fecha que elijas (`fecha`, `vence`, `planificada`, `siguiente_fecha`…); línea «ahora» magenta en la semana; bandeja lateral «Sin fecha (n)» | Arrastrar cambia la fecha; arrastrar desde «Sin fecha» la pone |
| **Galería** | Tarjetas de 220 × 160 (S, M, L) con logo, portada o primera página del PDF, o las iniciales; título y 3 datos | Menú de la tarjeta |
| **Lista** | Filas de 44 pt: título, dos datos debajo, estado o fecha a la derecha; agrupada. Es la vista de las pestañas de una ficha | Menú de la fila |
| **Cronograma** (Proyectos, Contenidos) | Barras de inicio a fin por fila, hoy en magenta | Arrastrar mueve; arrastrar el borde cambia el fin |

Todo arrastre tiene alternativa con un clic, con teclado y con VoiceOver.

### 4.5 Buscar, filtrar, agrupar y ordenar

- **Búsqueda instantánea** en la base: filtra mientras escribes por título, otros nombres, número, propiedades de
  texto y cuerpo; resalta lo que coincide. Si lo escrito parece un filtro, lo propone: «vencidas» → «Filtro:
  Vence antes de hoy»; «Lucía» → «Responsable: Lucía Andreu».
- **Filtrar:** «+ Filtro» → propiedad → condición (es · no es · contiene · antes de · después de · está vacía ·
  enlaza con) → valor. Para las relaciones, el valor se elige con el selector de relación. Se combinan con «y»;
  «alguna de» es opcional.
- **Agrupar:** por cualquier propiedad de opción, relación (empresa, proyecto), persona, área o fecha (por
  semana o mes). Un solo nivel en la v1.
- **Ordenar:** por cualquier columna; el orden por defecto es «lo urgente primero» (§2.2).

### 4.6 Vistas guardadas

- **Guardar vista** recoge: tipo de vista, pestaña, filtros, agrupación, orden, columnas y anchos, propiedad de
  fecha del calendario y tamaño de la galería. Lleva nombre y aparece como pestaña en la base.
- **Dónde se guarda (propuesta):** la **nota índice** declara la vista por defecto de la colección (`vista`,
  `agrupar_por`, `pestanas_por`, como ya dice `SISTEMAS.md` §1.4) y las vistas que guardas van en
  `.tls/vistas/<coleccion>.yaml`, una por colección (`SISTEMAS.md` §5.7). Así la nota índice no se reescribe cada
  vez que guardas una vista (se evitan los choques con iCloud) y las vistas viajan con la carpeta.
  «Exportar a Obsidian» escribe junto a la nota índice un `.base` con todas. Ver pregunta 4 de §10.
- «Hacer vista por defecto» sí escribe en la nota índice, en una sola línea, con su vista previa y Deshacer.

### 4.7 Columnas y edición en la celda

- **Columnas…** abre una lista con casillas y asas para elegir y ordenar; «Restaurar las de serie».
- Cada celda se edita según el tipo del diccionario:
  - texto: campo de una línea;
  - opción: menú con los valores en su orden y su pastilla;
  - fecha: campo de fecha con «Hoy», «Mañana», «+1 semana»;
  - dinero: campo con euros y cifras a la derecha;
  - relación: chips y selector (§5);
  - persona o responsable: menú con personas y asistentes;
  - sí/no: casilla.
- **Una celda escribe solo su clave** en la ficha (o solo su fila en un CSV), sin reformatear nada.
- Lo calculado (pendiente de cobro, avance, días quieta) se ve con un icono de calculadora y no se edita; al
  pasar el puntero dice de dónde sale.
- Lo que no se puede tocar desde una celda (el número de una factura emitida, el área de una tarea) se ve en gris
  con el motivo.

### 4.8 Crear rápido

- **«+ Nueva …»** abre una hoja corta que solo pregunta lo que pide la plantilla (`preguntas` de
  `.tls/plantillas.yaml`), ya rellena con lo que tengas filtrado, la pestaña y el grupo (en la columna
  «Propuesta» del tablero, la oportunidad nace en Propuesta). El nombre lo pone la plantilla. ↩ crea y abre; ⌘↩
  crea y deja la hoja lista para la siguiente.
- **Fila de creación** al final de la Tabla y la Lista: escribes el título y ↩ crea con los valores por defecto,
  en los tipos que solo piden título (tarea, contacto, contenido).

### 4.9 ⌘K: buscar en todas las bases

- **Un campo, «Buscar o hacer…»,** en una ventana flotante de 640 pt.
- **Vacío,** enseña: Recientes (5) · Pide tu decisión (3) · Bases fijadas.
- **Al escribir,** agrupa por: Mejores resultados (3) · una sección por base con resultados (Contactos, Empresas,
  Facturas…) · Acciones («Nueva factura para Arquitectura Nexo», «Ir a Facturas») · Bases · Dentro de notas
  (texto completo, con la línea donde aparece).
- **Encuentra por:** título, otros nombres, número o código (F-2026-0013, T-0041, FI1), propiedades de texto y
  cuerpo. Sin acentos ni mayúsculas.
- **Acotar:** chips Todo · Fichas · Bases · Acciones · Texto; y si empiezas por el nombre de una base («facturas
  vencidas»), propone buscar dentro de ella con ese filtro.
- **Teclado:** ↑ ↓ · ↩ abre (las migas se siembran con su base) · ⌘↩ en pestaña nueva · barra espaciadora para la
  vista previa · ⌥↩ «Relacionar con lo que tengo abierto», si el tipo encaja.
- **⌘O** sigue siendo «Abrir rápido», solo por nombre.

---

## 5. Editar las relaciones

### 5.1 El principio: la guarda un lado, se edita desde los dos

- **Cada relación vive en una sola ficha:** la que lleva la propiedad según `SISTEMAS.md` §3.6 (el proyecto
  guarda `empresa`, la factura guarda `proyecto`, la reunión guarda `personas`). Se escribe como enlace legible:
  `empresa: "[[arquitectura-nexo|Arquitectura Nexo SLP]]"`.
- **El otro lado se calcula** del índice al momento y nunca se escribe. Así no hay dos copias que puedan no
  coincidir.
- **Se edita desde cualquiera de los dos lados.** Desde la ficha que la guarda, en «Conectado con» o en el
  formulario; desde la otra, en la pestaña de ese tipo. **La app escribe siempre en la ficha que la guarda,** una
  sola línea, y lo dice: «Enlacé la reunión del 14 oct a Arquitectura Nexo · Deshacer».

**Por qué en propiedades y no en el texto:** una relación en una propiedad tiene nombre y tipo (se sabe que es
«la empresa de»), se puede filtrar y contar en las bases, aparece en la otra ficha en su pestaña con nombre, se
edita desde los dos lados y sobrevive a los cambios de nombre (`SISTEMAS.md` §5.2). Un enlace en el texto
(`[[` en Notas) es una mención libre: se ve en «Enlazan aquí» del inspector, no en las pestañas.

**`responsable` no es un enlace:** en tareas, proyectos y oportunidades se guarda un identificador estable que no se
renombra (`responsable: lucia`, `responsable: elena`, `responsable: agente:implementador`; `SISTEMAS.md` §1.6). La
app enseña el nombre («Lucía Andreu») y escribe siempre el identificador.

**Quién guarda cada relación** (resumen de `SISTEMAS.md` §3.6 para quien implementa):

| La guarda | Propiedad | Apunta a | Cuántas | Regla |
|---|---|---|---|---|
| Contacto | `empresa` | Empresa | 1 | Opcional |
| Oportunidad | `empresa`, `contacto` | Empresa, Contacto | 1 y 1 | Obligatorias |
| Oportunidad | `servicio`, `oferta_version` | Servicio, Versión | 1 y 1 | Obligatorias desde Propuesta |
| Oportunidad | `conversacion`, `referido_por` | Conversación, Contacto | 1 y 1 | Opcionales |
| Propuesta, presupuesto, contrato | `oportunidad` | Oportunidad | 1 | Obligatoria |
| Proyecto de entrega | `oportunidad` | Oportunidad | 1 | Obligatoria y **única**: una oportunidad tiene como mucho un proyecto |
| Proyecto | `empresa`, `plan` | Empresa, Plan | 1 y 1 | Obligatoria / opcional |
| Tarea | `proyecto` u `oportunidad` | Proyecto u Oportunidad | 1 | Una de las dos, o suelta |
| Tarea | `padre`, `bloqueada_por` | Tarea | 1 y varias | Opcionales |
| Reunión | `proyecto` u `oportunidad`, `empresa` | — | 1 y 1 | Una de las dos o el área |
| Reunión | `personas` | Contactos | Varias | — |
| Factura | `empresa`, `oportunidad`, `proyecto`, `rectifica` | — | 1 cada una | `empresa` obligatoria |
| Recibo | `factura` | Factura | 1 | Obligatoria |
| Incidencia | `proyecto`, `tarea` | — | 1 y 1 | `proyecto` obligatoria |
| Sistema | `rol` | Rol | 1 | Obligatoria |
| Procedimiento, activo | `sistema` | Sistema | 1 | Obligatoria |

### 5.2 El selector de relación

Una ventana flotante de 360 pt que sale del chip, de la celda o de «Añadir existente…»:
- **Buscador con el foco puesto.** Debajo, solo las fichas del tipo que admite esa propiedad (lo dice el
  diccionario), con las del contexto primero (en una reunión de Arquitectura Nexo, sus personas) y luego las
  recientes.
- **Cada fila:** icono, nombre, contexto («Arquitectura Nexo · Activo») y una marca si ya está enlazada.
- **Varias** (personas, bloqueada por): casillas y «Listo».
- **Crear al vuelo:** la última fila dice «Crear "Clínica Nueva" como empresa nueva» (↩ si no hay coincidencias;
  ⌘↩ siempre). Crea la ficha con su plantilla, en su carpeta y con su nombre estándar, y la enlaza. Si la
  plantilla pide algo obligatorio, lo pregunta en dos o tres campos dentro del propio selector.
- **¿No está?** «Buscar en todo» enseña también las de otros tipos, en gris y con el motivo («Una reunión se
  enlaza a personas, no a empresas»).
- **Teclado:** ↑ ↓ ↩ Esc. **VoiceOver:** «Elegir empresa para la reunión del 14 oct».

### 5.3 Añadir desde cualquier lado

| Desde | Haces | Se escribe en |
|---|---|---|
| Empresa Arquitectura Nexo › Proyectos | «Añadir existente…» y eliges un proyecto | El `Proyecto.md` elegido: `empresa: "[[arquitectura-nexo\|Arquitectura Nexo SLP]]"` |
| Contacto Sergio Nexo › Reuniones | «Añadir existente…» y eliges la reunión del 14 oct | La reunión: Sergio se añade a `personas` |
| Reunión › Conectado con | «+ Persona» | La propia reunión, en `personas` |
| Factura › Conectado con | Proyecto › «Elegir…» | La propia factura, en `proyecto` |
| Empresa › Facturas | «+ Nueva factura» | Nace en `Fiscal/Borradores/` con `empresa` y, si hay una sola abierta, `oportunidad` y `proyecto` (si hay varias, pregunta) |
| Tabla de Tareas | Celda «Proyecto» | La tarea, en `proyecto` |

**Si la relación es de una sola y ya tiene valor,** se pide confirmación con el cambio a la vista: «Este proyecto
es de Talleres Martín. ¿Pasarlo a Arquitectura Nexo?» con la línea antes y después.

### 5.4 Quitar y cambiar

- **Desde el lado que la guarda:** «×» en el chip, o su menú: Cambiar… · Quitar · Abrir · Abrir en pestaña
  nueva.
- **Desde el otro lado:** menú de la fila: «Quitar de Arquitectura Nexo» borra esa clave (o ese elemento de la
  lista) en la ficha que la guarda.
- **Obligatorias:** no tienen «Quitar», solo «Cambiar…», con el motivo («Una oportunidad siempre tiene empresa»).
- **Únicas:** al intentar dar un segundo proyecto a una oportunidad: «Esta oportunidad ya tiene proyecto ·
  Abrirlo».
- **En cadena, solo si lo eliges:** al cambiar la empresa de una oportunidad, la app pregunta «¿Cambiarla también
  en 2 fichas que cuelgan de ella (Propuesta v1 y la factura en borrador)?», con la lista. Una factura emitida
  nunca se cambia.
- **Quitar una relación nunca borra ni archiva ninguna ficha.**
- Cada cambio deja «Quité Arquitectura Nexo de la reunión del 14 oct · Deshacer» durante 6 s, y ⌘Z.

### 5.5 Relaciones múltiples

- Se guardan como lista: `personas: ["[[sergio-nexo|Sergio Nexo]]", "[[lucia-andreu|Lucía Andreu]]"]`.
- En «Conectado con» se ven 4 chips y «+3»; el orden se cambia arrastrando (y se guarda).
- En la Tabla, la celda enseña los chips que caben y «+n».

### 5.6 Enlaces en el texto

- En Notas, `[[` abre el autocompletado e inserta un enlace Markdown relativo, el estilo de G3 (`SISTEMAS.md`
  §1.6, `PLAN.md` §6.6).
- **Ascender una mención:** si el texto de una reunión enlaza a una empresa y su propiedad `empresa` está vacía,
  la franja «Conectado con» propone «¿Es la empresa de esta reunión? · Relacionar».
- Los enlaces que aún no existen (migas grises de `SISTEMAS.md` §5.4) llevan «Crear», con la plantilla que toca;
  los rotos, «Reparar» en Atención.

### 5.7 Lo que protege los ficheros

- Cada cambio toca solo su línea (`mergeFrontmatter` de una clave) y nunca reformatea.
- Si la ficha que guarda la relación cambió fuera desde que la leíste, se fusiona por clave; si choca, va a
  Decisiones › Archivos en conflicto (`SISTEMAS.md` §5.8).
- Si está en iCloud sin descargar, el chip dice «Descargando…» y el cambio espera.
- Renombrar o mover una ficha actualiza todos sus enlaces, también los de las propiedades (`SISTEMAS.md` §5.2).

### 5.8 Sin grafo

Lo relacionado se ve como **pestañas** (lo que cuelga de la ficha, con contador) y como la franja **«Conectado
con»** (aquello de lo que cuelga). «Enlazan aquí» y «Menciones» quedan en el inspector. **Propuesta:** retirar de
la v1 el módulo opcional «Mapa de relaciones» (`SISTEMAS.md` §4.4 y §5.9); el «Mapa de sistemas y flujos» se
queda, porque enseña sistemas y eventos, no notas.

---

## 6. Barra lateral y módulos con la paleta nueva

El comportamiento es el de `DIRECCIONES.md` §1.2–§1.3 y `SISTEMAS.md` §5.10. Cambia el aspecto y se añade la
sección Bases.

**Barra lateral (248 pt, sobre `superficie`, separador a la derecha):**
- **Empresa:** monograma «AR» en un cuadrado azul noche de 28 pt (radio 8), «Asesoría Ribera» y el chip
  «EJEMPLO» en `bandeja` con `textoSecundario`.
- **Favoritos:** cuadrados de 36 pt en `bandeja` con su icono en `texto`.
- **Orden:** Hoy · Decisiones · Tareas · ÁREAS · BASES · Asistentes · Carpeta · RECIENTES. Rótulos de sección en
  `rotulo` y `textoSecundario`.
- **Filas-pastilla de 36 pt,** radio 10: icono (las áreas y las bases, con su icono de app; el resto, SF Symbol en
  `textoSecundario`), nombre en `interfaz` 500 y el dato a la derecha en `secundario`.
- **Seleccionada:** pastilla azul noche con texto e icono blancos (en oscuro, `#7C8CFF` con texto `#0B1030`). El
  icono de app del área conserva su relleno, con un borde blanco de 1,5 pt.
- **Decisiones (3):** insignia magenta, porque te toca. «Tareas · 3 para hoy» va en `textoSecundario`, sin
  insignia. «2 · Ventas · 2 quietas» lleva el triángulo de Atención y la palabra.
- **Modo edición:** los elementos tiemblan ±1,5° (con «Reducir movimiento», borde discontinuo en
  `bordeControl`); a la izquierda, «−» en un círculo de 20 pt relleno de `textoSecundario` con el signo blanco
  (zona de toque de 28 pt); a la derecha, el asa «≡»; arriba, «Listo» en cápsula azul noche; Hoy lleva un
  candado en lugar del «−».
- **Arrastrar fuera:** la fila se despega con sombra 2; a 40 pt se queda al 60 % y aparece la pastilla
  «Ocultar» (fondo `texto`, letra `superficie`). Al soltar se encoge y se deshace en seis puntos de
  `textoSecundario` (0,3 s). El magenta ya no se usa aquí.
- **Ocultos:** bandeja con borde discontinuo de `bordeControl` y radio 14, con chips y «Mostrar».
- **Indentar:** guía vertical de 2 pt en el relleno del padre; el hijo entra 20 pt. **Atajos nuevos: ⌥⌘→ y
  ⌥⌘← para indentar y sacar** (y Tab y ⇧Tab dentro del modo edición), porque ⌘] y ⌘[ pasan a ser Adelante y
  Atrás. ⌥⌘↑ y ⌥⌘↓ siguen moviendo.
- **Mensaje con Deshacer** («Ocultaste 6 · Equipo · Deshacer»): `superficieElevada`, sombra 2, el botón como
  enlace.

**Módulos de inicio (Hoy y el Resumen de cada área):**
- Rejilla de 4 columnas; tamaños Pequeño 1×1, Mediano 2×1, Grande 2×2 y Ancho 4×1; 8 como mucho.
- Cada mosaico en `superficie`, radio 22, sombra 1: arriba el icono del área (16 pt) y el nombre en `rotulo`; en
  medio la cifra en Space Grotesk; debajo la línea de contexto; al pie «Sale de…» en `secundario`.
- **Un solo destacado violeta por inicio:** en Hoy, tu foco; en un área, su número clave.
- **Hoy, arriba:** a la izquierda, la cabecera azul noche con «Buenos días, Elena», la fecha y la frase del día;
  a la derecha, el foco en violeta con «Revisar y emitir» (botón blanco con texto violeta). Debajo, «Pide tu
  decisión» con las tres decisiones en mosaicos blancos; la opción recomendada lleva borde azul noche y la
  palabra «Recomendada».
- **Gráficas:** línea de 2,5 pt en azul noche (en oscuro, `#7C8CFF`) con degradado del 24 % al 0 %; al pasar,
  regla de 1 pt en `textoSecundario`, punto azul noche con anillo blanco y pastilla en `superficieElevada`; al
  arrastrar, el tramo en `principalSuave`; «Estimado» con línea discontinua 4–4; periodos en cápsula, el elegido
  en azul noche.
- **Editar inicio:** tiemblan, «−» arriba a la izquierda, asa de tamaño de 28 pt abajo a la derecha, «+ Añadir»
  abre la galería en una hoja; «Listo» en azul noche.

---

## 7. Cómo se construye en SwiftUI

Objetivo: macOS 15 (`Package.swift`). Lo que sigue encaja con lo que ya hay en `TLSUI` (`VaultWindow`,
`VaultSession`, `NoteInspector`, `CommandPaletteSheet`) y `TLSDesign` (`TLSTokens`).

### 7.1 Ventanas y pestañas

- `WindowGroup(id: "vault", for: VentanaRuta.self)`, con `VentanaRuta: Codable, Hashable` = empresa + camino
  inicial + un `UUID`. El `UUID` hace falta porque `WindowGroup` reutiliza la ventana si el valor es igual, y
  ⌘clic debe abrir siempre una pestaña nueva.
- Pestañas del Mac: en la ventana, `NSWindow.tabbingMode = .preferred` y `tabbingIdentifier` = id de la empresa,
  con un pequeño `NSViewRepresentable` que accede a la ventana. ⌘clic llama a
  `openWindow(id: "vault", value: VentanaRuta(…))` y la ventana nueva entra como pestaña.
- `.windowToolbarStyle(.unified(showsTitle: false))`: el título lo dan las migas.

### 7.2 Navegación

**Hoy hay tres columnas** (barra lateral, columna central y nota). **Pasa a dos:** barra lateral y detalle con
una pila. Lo que hoy va en la columna central (área, carpeta, búsqueda) es la raíz de la pila.

```swift
enum Destino: Hashable, Codable {
    case hoy, decisiones, tareas, asistentes, todasLasBases
    case area(AreaCode, pestana: PestanaArea)
    case base(ColeccionID, vista: VistaID?, contexto: FichaID?)   // contexto: «Facturas de esta empresa»
    case ficha(FichaID, pestana: PestanaFicha?)                     // FichaID = `id` del frontmatter
    case fichero(VaultPath)
    case busqueda(String)
}

@MainActor @Observable final class Navegacion {
    var raiz: Destino
    var pila: [Destino]                       // ligada a NavigationStack(path:)
    private(set) var atras: [Paso] = []       // Paso = (raiz, pila, estado de cada pantalla)
    private(set) var adelante: [Paso] = []
    func entrar(_ d: Destino)                 // recorta si ya está en la pila (sin bucles)
    func nuevaRaiz(_ d: Destino)
    func volver(a indice: Int)
    func irAtras(); func irAdelante(); func subir()
}
```

```swift
NavigationSplitView(columnVisibility: $columnas) {
    BarraLateral(seleccion: $nav.raiz)
        .navigationSplitViewColumnWidth(min: 232, ideal: 248, max: 320)
} detail: {
    NavigationStack(path: $nav.pila) {
        PantallaRaiz(nav.raiz)
            .navigationDestination(for: Destino.self) { destino in
                PantallaDestino(destino)
                    .navigationBarBackButtonHidden(true)   // ‹ › son nuestros
            }
    }
}
.toolbar {
    ToolbarItemGroup(placement: .navigation) { BotonesAtrasAdelante(); Migas() }
    ToolbarItemGroup(placement: .primaryAction) { BotonBuscar(); BotonMika(); InterruptorAsistentes() }
}
.focusedSceneValue(\.navegacion, nav)
```

- **‹ ›:** `Menu { historial } label: { Image(systemName: "chevron.left") } primaryAction: { nav.irAtras() }`
  da clic = atrás y mantener pulsado = historial.
- **Atajos:** `CommandMenu("Ir")` con Atrás (⌘[), Adelante (⌘]), Hoy, Decisiones, Tareas (⌘1–3), áreas (⌘4–9) y
  Todas las bases (⇧⌘B), que actúan sobre `@FocusedValue(\.navegacion)`. **⌘↑ no va en el menú:** se atiende con
  `.onKeyPress` en la pantalla, para que en un campo de texto o en el editor siga yendo al principio.
- **Restaurar:** `@SceneStorage("navegacion")` con `raiz` y `pila` codificadas.
- **Un nivel cuesta poco:** cada pantalla carga una instantánea del índice (GRDB), no lee ficheros al entrar; el
  objetivo es menos de 100 ms por nivel. Las pestañas de la ficha cargan al elegirlas.

### 7.3 La ficha

- `FichaPantalla(id:)` con `FichaModelo` (`@Observable`): nota, propiedades, relaciones de uno a uno
  («Conectado con»), inversas agrupadas por propiedad (pestañas), contadores y urgentes.
- Disposición: `ScrollView` con la rejilla del mosaico, un `Layout` propio (`MosaicoLayout`, 4 columnas, tamaños
  S/M/L/W) que se reutiliza en Hoy, el Resumen de las áreas y el Resumen de la ficha.
- Pestañas: control propio en cápsula (`PestanasFicha`), con
  `.accessibilityRepresentation { Picker(…) }` para VoiceOver y ⌃1–⌃9.
- Barra fija de los documentos: `.safeAreaInset(edge: .bottom) { BarraDocumento(…) }`.
- Inspector: `.inspector(isPresented:)` con el `NoteInspector` que ya existe, ampliado a formulario de
  propiedades, `.inspectorColumnWidth(min: 260, ideal: 300, max: 420)`. En la tarea, el panel de propiedades va
  siempre abierto.
- Notas: el editor de `PLAN.md` §6.6 (`NSTextView` con TextKit 2) por sección, con `replaceSection`.
- Vacíos: `ContentUnavailableView` con la frase y el botón de §2.2.

### 7.4 Las bases

- `BasePantalla(coleccion:)` con `BaseModelo` (`@Observable`): consulta (`SchemaQuery`), pestaña, filtros,
  agrupación, orden, columnas, vista y búsqueda. Lee del índice con `ValueObservation` para refrescar sola.
- **Tabla:**
  ```swift
  Table(filas, selection: $seleccion, sortOrder: $orden, columnCustomization: $columnas) {
      TableColumnForEach(columnasVisibles) { col in
          TableColumn(col.etiqueta, sortUsing: ComparadorPropiedad(col.clave)) { fila in
              CeldaEditable(fila: fila, columna: col)
          }
          .customizationID(col.clave)
      }
  }
  .contextMenu(forSelectionType: FichaID.self) { ids in MenuFila(ids) } primaryAction: { ids in abrir(ids) }
  .onKeyPress(.space) { vistaPrevia(seleccion); return .handled }
  ```
  `TableColumnForEach` (macOS 14.4) permite columnas que salen del diccionario; `TableColumnCustomization` guarda
  orden, anchos y ocultas. Si la agrupación con `Section` dentro de `Table` no basta en macOS 15, la vista
  agrupada se hace con `List`.
- **Celdas:** `TextField`, `Picker` (`.labelsHidden()`), `DatePicker` (`.field`), `Toggle` y `CeldaRelacion`
  (chips con el selector en un `popover`). Al confirmar, una escritura de una clave.
- **Tablero:** `ScrollView(.horizontal)` con `LazyHStack` de columnas; tarjetas `.draggable(FichaRef)`
  (`Transferable`) y columnas `.dropDestination(for: FichaRef.self)` con `isTargeted` para el aviso de bloqueo;
  `.accessibilityAction(named: "Mover a Propuesta")` y ⌘← ⌘→.
- **Calendario:** propio (`LazyVGrid` de 7 columnas para el mes; rejilla de horas para la semana), con
  `.draggable` y `.dropDestination` para cambiar fechas.
- **Galería:** `LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))])`.
- **Lista:** `List(selection:)` con `Section` por grupo y fila propia.
- **Cronograma:** Swift Charts con `BarMark(xStart:xEnd:y:)` y `RuleMark` magenta para hoy.
- **Buscador de la base:** va en la barra de la base, no en la de la ventana (allí está ⌘K): un `TextField` con
  `@FocusState` y ⌘F, y sugerencias de filtro en un menú bajo el campo.
- **Vistas guardadas:** `VistaGuardada: Codable`, escrita con Yams en `.tls/vistas/<coleccion>.yaml`.

### 7.5 ⌘K

- El `CommandPaletteSheet` actual pasa a ventana flotante centrada (`.sheet` sin velo, o un `NSPanel` si hace
  falta que flote sobre la barra), con `TextField` y `List` por secciones.
- Resultados del índice con texto completo (FTS5 de SQLite, en GRDB), sin acentos, con prefijo, y ordenados por
  coincidencia, uso reciente y tipo.
- Teclado con `.onKeyPress(.upArrow)`, `.onKeyPress(.downArrow)` y `.onKeyPress(.return)`, mirando las teclas
  de modificación para ⌘↩ y ⌥↩.

### 7.6 Selector de relación y escritura

- `.popover(isPresented:arrowEdge: .bottom) { SelectorRelacion(propiedad:, ficha:) }` con `TextField`
  (`.defaultFocus`), `List(selection:)` y la fila «Crear …».
- Los tipos permitidos salen de `.tls/propiedades.yaml`; el lado que guarda la relación, de una tabla
  `RelacionesEsquema` que traduce `SISTEMAS.md` §3.6 (§5.1).
- Escritura: `VaultService.mergeFrontmatter(ruta:, clave:, valor:)` en la ficha dueña, registrada en el
  `UndoManager` de la ventana (`@Environment(\.undoManager)`), con el mensaje «… · Deshacer».
- Crear al vuelo: el servicio de plantillas (`.tls/plantillas.yaml`) con el contexto rellenado, y después el
  enlace, como **un solo paso de deshacer**.

### 7.7 Vista previa

- `.onHover` con una espera de 600 ms (`Task.sleep`) que se cancela al salir; después,
  `.popover(item: $previa, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) { VistaPreviaFicha(id) }`.
- En listas, tablas y tableros, `.onKeyPress(.space)`.
- `.accessibilityAction(named: "Vista previa")` en filas y chips.
- Sale del índice (instantánea), sin leer el fichero.

### 7.8 Valores de diseño, letra y foco

- **Colores:** se amplía `TLSTokens` con los nombres de §1 (`fondo`, `superficie`, `superficieElevada`,
  `bandeja`, `cabecera`, `texto`, `textoSecundario`, `separador`, `bordeControl`, `principal` y sus estados,
  `violeta…`, `chispa…`, estados y áreas con tinta y relleno). Se construyen con el `dynamic(name:light:dark:)`
  que ya existe, ampliado para «Aumentar contraste» con
  `appearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])`.
- **Color de acento** del catálogo de recursos = azul noche, para que los controles del sistema (casillas,
  interruptores, selección de `Table` y `List`) lo usen solos.
- **Foco:** en los controles propios, `.focusEffectDisabled()` y un anillo dibujado (`AnilloFoco`) con
  `@FocusState`: magenta sobre neutros, blanco sobre rellenos de color. Los controles del sistema que no se
  pueden cambiar mantienen el anillo del sistema, que sigue el color de acento (azul noche). Ver pregunta 11.
- **Letra:** las tres familias van en el paquete y se registran al arrancar
  (`CTFontManagerRegisterFontsForURL`); `Font.custom` con un factor de escala propio (85–200 %), porque el Mac
  no tiene tamaño de texto dinámico. Los nombres exactos de cada peso se toman de los ficheros incluidos.
- **Sombras:** dos `.shadow` por nivel (el radio de SwiftUI es la mitad del desenfoque de CSS).
- El comentario de `Tokens.swift` («el magenta solo va en el botón principal y el foco») y los colores de área de
  `PLAN.md` §6.9 quedan sustituidos por este documento.

### 7.9 Accesibilidad

- Cada fila con una etiqueta completa: «Factura F-2026-0013, Talleres Martín, 181,50 €, Emitida».
- Migas como grupo «Estás en»; pestañas con su contador y lo urgente en palabras; «Conectado con» como lista de
  botones.
- `accessibilityRotor` «Relacionados» en la ficha y «Urgente» con las líneas de «Ahora».
- Teclado completo: Tab pasa por barra lateral → migas → cabecera → «Ahora» → «Conectado con» → pestañas →
  contenido.
- Todo arrastre con su alternativa por menú, por atajo y con acción con nombre en VoiceOver.

### 7.10 Componentes

| Componente | Dónde | Qué hace |
|---|---|---|
| `Migas`, `BotonesAtrasAdelante` | TLSUI | §2.3 y §2.1 |
| `CabeceraPantalla` | TLSDesign | Cabecera azul noche de área, base y ficha |
| `Destacado` | TLSDesign | El bloque violeta; comprueba en depuración que solo hay uno por pantalla |
| `FranjaAhora`, `ConectadoCon`, `ChipRelacion` | TLSUI | §3.1 |
| `PestanasFicha` | TLSDesign | Cápsulas con contador, urgente y «Más» |
| `FichaPantalla` + una configuración por tipo (`FichaTipo`) | TLSUI | Destacado, datos, pestañas, pestaña inicial y acciones de §3.3–§3.4 |
| `BasePantalla`, `VistaTabla`, `VistaTablero`, `VistaCalendario`, `VistaGaleria`, `VistaLista`, `VistaCronograma` | TLSUI | §4 |
| `SelectorRelacion`, `CeldaRelacion` | TLSUI | §5 |
| `VistaPreviaFicha` | TLSUI | §2.5 |
| `MosaicoLayout`, `Mosaico`, `PastillaEstado`, `IconoArea`, `InsigniaAviso`, `AnilloFoco` | TLSDesign | §1 y §6 |

---

## 8. Qué cambia en otros documentos

| Documento | Antes | Con este |
|---|---|---|
| `DIRECCIONES.md` §2.1 | Acento magenta en botones, selección y bloque principal | Azul noche para actuar y encabezar, violeta para el destacado, magenta solo foco y avisos |
| `DIRECCIONES.md` §1.7 y §2.1 | Dirección violeta, Entrega azul, Marca magenta, Equipo rojo | Ciruela, petróleo, oliva y granate; Ventas y Finanzas con valores nuevos; el orden de luminosidad no cambia |
| `DIRECCIONES.md` §1.1 | Orden de la barra sin bases; ⌘[ ⌘] sin uso | Sección Bases entre Áreas y Asistentes; ⌘[ ⌘] Atrás y Adelante; ⌘↑ subir; ⇧⌘B Todas las bases; ⌃1–9 pestañas de la ficha |
| `DIRECCIONES.md` §1.2, `SISTEMAS.md` §5.10, `GUION-MAQUETAS.md` §2.3 | Indentar con ⌘] y ⌘[ | Indentar con ⌥⌘→ y ⌥⌘← (y Tab y ⇧Tab en modo edición) |
| `DIRECCIONES.md` §2.6–§2.8 | Selección, «Listo» y puntos al ocultar en magenta; factura en mosaico magenta | Selección y «Listo» en azul noche; puntos neutros; la factura en destacado violeta |
| `PLANTILLAS.md` §1.7 y `GUION-MAQUETAS.md` §6.3 | Protagonista del contacto: sus iniciales | Las iniciales van al avatar; el destacado es el siguiente paso |
| `SISTEMAS.md` §4.4 y §5.9 | Módulo «Mapa de relaciones» (grafo) | Retirado de la v1 (propuesta) |
| `SISTEMAS.md` §3.6 | El rol guarda `sistemas` y el sistema guarda `rol` (dos copias) | Solo el sistema guarda `rol`; los sistemas del rol se calculan (propuesta, pregunta 8) |
| `PLAN.md` §6.1 | Tres columnas | Dos columnas y una pila con migas por pestaña de ventana |
| `PLAN.md` §6.9 | Acento magenta en botones; interfaz en SF; colores de área de Tailwind | Lo de §1; interfaz en DM Sans |
| `TLSDesign/Tokens.swift` | Magenta en el botón principal; áreas «aclaradas» en oscuro | Valores de §1, con tinta y relleno por modo |
| `GUION-MAQUETAS.md` §8 | Sin datos de proyectos | Hay que añadir lo de §9 para maquetar la profundidad |

---

## 9. Maquetas de Mosaico v2

Hay **cuatro maquetas**, con los datos de Ribera, la paleta de §1, claro y oscuro con conmutador y «Aumentar
contraste». Se recorren en este orden y se enlazan entre ellas (§2.6):

1. **`M2-Hoy`:** la de v1 con la paleta nueva (cabecera azul noche, foco violeta, insignia magenta en Decisiones,
   foco de teclado magenta visible), la barra lateral con la sección Bases y en modo edición, «Conectado con» en
   vista previa y la decisión del cobro de Talleres que lleva a Jorge y a su proyecto.
2. **`M2-Bases`:** «Todas las bases» (las 24, con la frase de su nota índice, su último cambio y el menú Abrir ·
   Abrir en pestaña nueva · Fijar en la barra lateral · Nueva…); **Contactos**, **Proyectos** y **Facturas** con sus
   fichas en Tabla o Lista, pestañas por estado, Filtrar, Agrupar, Ordenar, Columnas, edición en la celda (también
   de la empresa, con selector y confirmación) y lo que no se edita en gris con su motivo; **Oportunidades** con sus
   vistas guardadas, Tabla, Tablero, Calendario («Sin fecha» con teclado), Galería y Lista; y **⌘K** con «nexo».
3. **`M2-Contacto`:** 2 · Ventas y la ficha de **Jorge Martín**, con «Ver estado» (antes de confirmar el cobro ·
   cobro confirmado · pestaña Proyectos), migas, franja «Ahora», «Conectado con» editable, pestañas en el orden de
   §3.4, «+ Nuevo» ya enlazado, Notas con `[[`, Fichero y panel de propiedades.
4. **`M2-Proyecto`:** **Trimestrales 2026** en curso, con «Fases del plan», tablero de Tareas y panel de la tarea
   T-0042 (con su borrador esperando tu OK), relaciones editables desde el proyecto, Notas editables en el sitio,
   panel de propiedades (⌥⌘I) y la ficha de la tarea un nivel más abajo.

**Faltan** (se ven en vista previa o en su base hasta que tengan maqueta): **Empresa** (Arquitectura Nexo o Talleres
Martín), **Oportunidad** (Arquitectura Nexo · Trimestrales, con su línea de etapas y Ganada bloqueada) y **Factura**
(el borrador de Arquitectura Nexo con su barra fija).

**Lo que el guion tiene que añadir** para que la profundidad sea real:
- un proyecto en curso de un cliente activo (por ejemplo, el de Clínica Dental Sonrisa, que ya tiene la tarea
  T-0037 en Entrega), con su plan, sus fases, 2 sesiones hechas de las incluidas, una reunión de seguimiento,
  una factura cobrada y su recibo;
- la reunión de diagnóstico del 14 oct con Sergio Nexo como ficha (hoy solo se cita en la ficha del contacto);
- el contrato de Arquitectura Nexo en borrador (T-0040 lo revisa);
- tres o cuatro empresas más para que la Galería y la Tabla de Empresas tengan contenido (las del embudo ya
  tienen nombre).

---

## 10. Preguntas finales, con propuesta

> **Respondidas el 22/10/2026.** Manu aprueba Mosaico v2 tal como está en las cuatro maquetas. Elige
> expresamente la propuesta en la 1 (colores de área), la 6 (vista previa al pasar el puntero) y la 11 (anillo
> de foco magenta). En las demás se aplica la propuesta.

1. **Colores de área.** Dirección ciruela, Equipo granate, Entrega petróleo, Marca oliva, Ventas verde y
   Finanzas ámbar (§1.7). *Propuesta: sí.* Alternativa: Marca en oro viejo, más «destellos», pero más cerca del
   ámbar de Finanzas (ΔE 18, frente a más de 20 con el oliva).
2. **Equipo y «Mal»** quedan cerca (ΔE 12 en claro, 10 en oscuro), como ya pasaba. *Propuesta: dejarlo:* Equipo
   está en reposo hasta la etapa 5 y nunca es una pastilla. Alternativa: llevar Equipo a un rojo frambuesa, que
   se acerca al magenta.
3. **⌘[ y ⌘] para Atrás y Adelante, y ⌥⌘← ⌥⌘→ para indentar en la barra lateral.** *Propuesta: sí,* es lo que
   hacen Finder y Safari.
4. **Vistas guardadas.** *Propuesta:* la nota índice dice la vista por defecto y las tuyas van en
   `.tls/vistas/` (no se reescribe la nota cada vez y no hay choques con iCloud). Alternativa: todas dentro de la
   nota índice, a la vista en cualquier editor pero con más escrituras.
5. **«Fichero» en lugar de «Archivo»** para la pestaña del fichero, versiones y adjuntos. *Propuesta: sí.*
6. **Vista previa al pasar el puntero** (0,6 s), desactivable. *Propuesta: sí.* Alternativa: solo con la barra
   espaciadora.
7. **⌘clic abre en una pestaña del Mac.** *Propuesta: sí.* Alternativa: un panel dividido dentro de la ventana
   (más trabajo, y menos parecido a Finder).
8. **Relación rol–sistema guardada solo en el sistema** (`rol`), y los sistemas del rol calculados.
   *Propuesta: sí;* evita dos copias que se desajusten.
9. **Retirar «Mapa de relaciones»** (el grafo) de la v1. *Propuesta: sí.*
10. **El destacado del contacto y de la empresa es el siguiente paso,** no las iniciales. *Propuesta: sí.*
11. **Anillo de foco magenta** en los controles propios, aunque los del sistema (tablas, campos estándar)
    mantengan el anillo del sistema en azul noche. *Propuesta: sí.* Alternativa: anillo azul noche en todo, más
    coherente con el Mac pero con el magenta aún más escondido.

---

## 11. Criterios de aceptación

1. Desde la base Empresas, al proyecto de un cliente en 3 clics (empresa, pestaña Proyectos, proyecto). Un ⌘[
   vuelve a la empresa en la pestaña Proyectos y otro, a la base con el mismo desplazamiento y los mismos filtros.
2. Todas las parejas de color de §1 pasan una prueba automática con la fórmula de WCAG (en `DesignTests`).
3. Ningún botón, selección ni relleno mayor de 24 pt usa el magenta; cada pantalla tiene como mucho un destacado
   violeta (comprobación en depuración).
4. Añadir una relación desde el lado que no la guarda cambia **una línea** en el fichero que la guarda; deshacer
   deja los mismos bytes.
5. Editar una celda escribe solo esa clave; en un CSV, solo esa fila.
6. Con 8 niveles y la ventana a 1.100 pt, las migas enseñan la raíz, la penúltima y la última.
7. ⌘K encuentra por número, por otro nombre y por texto en menos de 100 ms con 5.000 fichas.
8. La vista previa no escribe nada y se abre igual con el teclado que con el puntero.
9. Todo lo que se hace arrastrando (barra lateral, inicio, tablero, calendario, chips) se puede hacer con menú,
   con atajo y con VoiceOver.
10. Entrar un nivel tarda menos de 100 ms con la carpeta de Ribera.

---

## Anexo. Cómo se han calculado los colores

- **Contraste:** fórmula de WCAG 2.x (luminancia relativa en sRGB), pareja a pareja, con los fondos de cada modo:
  `fondo`, `superficie` y `bandeja` en claro; `fondo`, `superficie` y `superficieElevada` en oscuro. Cada valor
  de las tablas es el peor de esos fondos salvo que se diga otro.
- **Áreas:** cada una tiene un tono fijo en OKLCH (Dirección 330°, Equipo 16°, Entrega 225°, Marca 112°,
  Ventas 160°, Finanzas 70°) y una saturación máxima; se ajusta solo la luminosidad hasta un L* objetivo que
  respeta el orden de §1.7 y los mínimos (tinta ≥4,5 y relleno ≥3 contra los tres fondos de cada modo; glifo ≥3
  sobre el relleno).
- **Distancias:** ΔE2000 entre rellenos (y entre tintas) del mismo modo, y frente al azul noche, el violeta, el
  magenta y los cuatro estados.
- **Marca:** el azul noche `#1E2A78`, el violeta `#7C3AED`, el magenta `#E6007E` y el azul de oscuro `#7C8CFF` son
  los elegidos y no se tocan; los estados al pasar, pulsado, suave y enlace se derivan de ellos.
- **Pendiente de comprobar en la app:** las cifras tabulares de Space Grotesk y DM Sans en los ficheros incluidos,
  y que el anillo del sistema en tablas y campos estándar convive bien con el magenta.

**Procedencia.** Decisión de Manu del 22/10/2026 y documentos de esta carpeta. Los nombres de los SF Symbols se
han comprobado en el catálogo del sistema de este Mac. Los datos de ejemplo son de Asesoría Ribera, que es
ficticia.
