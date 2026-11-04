# The Last — Manual de Marca

> Sistema visual completo para presentaciones, web, redes sociales y cualquier pieza de diseño.
> Actualizado: mayo 2026.

---

## 01 · Esencia

The Last es un sistema operativo de negocio. La identidad refleja eso: **estructura, claridad y energía**.

Tres rombos entrelazados que se sostienen entre sí — como Dirección, Ventas y Entrega; o Sistemas, Equipo y Marca.

- **Estructura** — forma geométrica precisa, repetición rítmica, sistema no dibujo.
- **Energía** — gradiente azul → magenta: movimiento, calor, dirección.
- **Confianza** — tipografía limpia, espaciados generosos, dark mode dominante.

---

## 02 · Logo

Cuatro variantes principales:

| Variante | Archivo | Uso |
|---|---|---|
| Color sobre claro | `logo/logo.svg` · `logo/logo-completo-color.jpg` | Fondos blancos o cream |
| Color isotipo | `logo/isotipo-color.jpg` | Cuando "THE LAST" ya aparece en el contexto |
| Blanco sobre oscuro | `logo/logo-white.svg` · `logo/logo-completo-blanco.jpg` | Dark mode, gradiente brand |
| Cover social | `logo/logo-cover-social.jpg` | Portadas RRSS, OG image |

**Reglas:**
- Mantener proporciones — no estirar ni recortar.
- Área de protección mínima: el ancho de un rombo a cada lado.
- Tamaño mínimo: 24 px pantalla, 12 mm impresión.
- Sobre foto: variante blanca con sombra suave.

---

## 03 · Color

### Brand core
| Color | Hex | Variable |
|---|---|---|
| Dark Blue | `#0A1628` | `--dark-blue` |
| Intense Blue | `#1A3A8A` | `--intense-blue` |
| Magenta | `#E6007E` | `--magenta` |
| Cream | `#FDFBF7` | `--cream` |

### Neutros
| Color | Hex | Variable |
|---|---|---|
| Off Black | `#050C18` | `--off-black` |
| Gray Blue | `#8490B0` | `--gray-blue` |
| White | `#FFFFFF` | `--white` |

### Acentos funcionales
| Color | Hex | Función |
|---|---|---|
| Green | `#00D4AA` | Éxito |
| Yellow | `#FFB800` | Aviso |
| Red | `#FF6B6B` | Error |
| Purple | `#9B59B6` | Especial |

---

## 04 · Gradientes

| Token | Definición | Uso |
|---|---|---|
| `--grad-brand` | 135° intense-blue → magenta | Hero, CTA, isotipo |
| `--grad-brand-h` | 90° horizontal | Barras, separadores, text-gradient |
| `--grad-brand-soft` | Versión suave (6b8edb → ff3da0) | Headers light, overlays |
| `--grad-white` | Blanco → rosa pálido | Cards premium en presentaciones light |

---

## 05 · Tipografía

| Familia | Uso | Weights |
|---|---|---|
| **Space Grotesk** | Display, títulos, números | 300–700 |
| **DM Sans** | Body, UI, botones | 300–700 |
| **JetBrains Mono** | Código, tokens, eyebrows | 400–600 |

Carga vía Google Fonts CDN (ya incluido en `tokens.css`).

### Escala
| Nivel | Tamaño | Weight |
|---|---|---|
| Hero | 96px | 700 |
| Display | 56px | 700 |
| H1 | 34px | 600 |
| H2 | 24px | 600 |
| Body L | 18px | 500 |
| Body M | 15px | 400 |
| Eyebrow | 13px mono uppercase | 500 |

---

## 06 · Áreas del sistema

Cada área operativa de The Last tiene su color. Usar en dashboards, tags, iconografía interna.

| Área | Hex | Variable |
|---|---|---|
| Dirección | `#A855F7` | `--area-direccion` |
| Ventas | `#22C55E` | `--area-ventas` |
| Entrega | `#3B82F6` | `--area-entrega` |
| Finanzas | `#F97316` | `--area-finanzas` |
| Marca | `#EC4899` | `--area-marca` |
| Equipo | `#EF4444` | `--area-equipo` |

---

## 07 · Fondos y texturas

| Archivo | Tipo | Uso |
|---|---|---|
| `fondos/gradiente-plano.jpg` | Gradiente diagonal limpio | Base, textos largos |
| `fondos/dinamico-oscuro.jpg` | Orgánico cinematográfico | Portadas premium |
| `fondos/cover-isotipo-claro.jpg` | Cover con isotipo centrado, contraste suave | Slide 1 presentación |
| `fondos/cover-isotipo-intenso.jpg` | Cover con isotipo, magenta intenso | Posts impactantes RRSS |

---

## 09 · Componentes

### Botones
- **Primary** — `var(--grad-brand-h)` + `var(--shadow-glow-magenta)`. Acciones principales (CTA).
- **Ghost** — borde sutil, fondo transparente. Acciones secundarias.
- **Light** — fondo blanco, texto off-black. Para versiones light o fondos oscuros.

### Radios
| Token | Valor | Uso |
|---|---|---|
| `--r-sm` | 10px | Inputs, badges |
| `--r-md` | 16px | Cards pequeñas, tiles |
| `--r-lg` | 24px | Cards principales |
| `--r-xl` | 32px | Bloques grandes |
| `--r-pill` | 999px | Botones, pills |

### Sombras
| Token | Definición |
|---|---|
| `--shadow-soft` | 0 12px 40px rgba(14,12,68,.08) |
| `--shadow-md` | 0 20px 50px rgba(14,12,68,.12) |
| `--shadow-glow-magenta` | 0 18px 48px rgba(230,0,126,.28) |
| `--shadow-glow-blue` | 0 18px 48px rgba(26,58,138,.28) |

---

## 10 · Aplicaciones

### Web y landings
Importar `styles/tokens.css` y usar las variables.

```html
<link rel="stylesheet" href="styles/tokens.css">
```

### Presentaciones
- Slides 16:9 sobre `--off-black` o `--dark-blue`.
- Portada con `fondos/cover-isotipo-*.jpg`.
- Títulos en Space Grotesk 700, body en DM Sans 500.
- Eyebrow numerada (`01 — Esencia`) en JetBrains Mono uppercase magenta.

### Carruseles RRSS
- **Slide 1** — cover con isotipo (cover-isotipo-claro o intenso).
- **Slides medias** — fondo `--dark-blue` con tipografía blanca.
- **Slide final** — CTA en `--grad-brand`.
- Formato 1080×1350 (Instagram) o 1080×1080 (genérico).

---

## 11 · Recursos

### Estructura
```
docs/diseno/marca/
├── manual-marca.md        ← este archivo
├── styles/tokens.css      ← variables CSS
├── logo/                  ← SVG, PNG y JPG del logo y el isotipo
└── fondos/                ← 4 texturas
```

### Importación rápida
```html
<link rel="stylesheet" href="styles/tokens.css">
```

Y ya tienes acceso a `var(--grad-brand)`, `var(--magenta)`, `var(--font-display)`, etc.

### Dependencias externas
- Google Fonts: Space Grotesk, DM Sans, JetBrains Mono (via CDN, incluido en tokens.css)
- Material Symbols Outlined (Google, opcional para iconografía)
