# Diseño

Hay tres capas. Cada pieza tiene su fuente y no se copia entre ellas.

| Capa | Para qué | Fuente |
|---|---|---|
| **Sistema visual del fork** (web y app de macOS de Mika Business) | La interfaz de la app | `packages/ui/styles/tokens.css` y las pantallas de `packages/views/empresa/` |
| **Mosaico v2** (app nativa The Last System) | La interfaz de la app nativa | [`apps/the-last-system/docs/propuesta/DISENO-MOSAICO-V2.md`](../../apps/the-last-system/docs/propuesta/DISENO-MOSAICO-V2.md) y `Packages/TLSKit/Sources/TLSDesign/` |
| **Marca The Last** | Material hacia fuera: web, presentaciones, documentos | [`marca/`](marca/): guía, logo, `tokens.css` y fondos |

## Sistema visual del fork

Es minimalista, en la línea de Trade Republic: se toma su lenguaje visual, nunca su marca. Por encima va la estructura de Multica (navegación, layout y rutas), que no cambia.

- **Jerarquía por tipografía.** Una cifra protagonista por pantalla (`--text-hero`), texto secundario en gris y pocos pesos.
- **Casi monocromo.** Lienzo blanco o negro puro, paleta neutra y sin sombras de superficie. El color solo significa algo: positivo, negativo o el estado del ritmo.
- **Una gráfica de línea limpia** con selector de periodo en texto (1S · 1M · 3M · 1A · Todo), sin rejilla ni ejes recargados.
- **Filas en lugar de tarjetas**: nombre a la izquierda, cifra y variación a la derecha. El detalle aparece al entrar en la fila.
- **Iconos mínimos**: solo los de navegación. Las áreas del menú lateral son texto, sin puntos de color.

### Ritmo por área

Es la función del programa antiguo que se recuperó en la app. Compara el valor real con lo esperado a fecha de hoy, y en cada área manda el indicador más atrasado:

| Banda | Umbral |
|---|---|
| Por delante | ≥ 105 % |
| En ritmo | ≥ 95 % |
| Atención | ≥ 80 % |
| En riesgo | ≥ 55 % |
| Crítico | < 55 % (token `--critical`) |

El cálculo está en `packages/core/biz/pace.ts` (con sus tests) y la vista, en `packages/views/empresa/area-pace.tsx`.

### Reglas al tocar la interfaz

- Usa los tokens semánticos de `packages/ui/styles/` y la escala `--text-*`. No uses colores ni tamaños sueltos.
- Una pantalla responde a una pregunta: arriba lo principal y el detalle detrás de la fila.
- Comprueba siempre los modos claro y oscuro.

## Marca The Last

[`marca/manual-marca.md`](marca/manual-marca.md) tiene la esencia, el logo, el color, los gradientes, la tipografía (Space Grotesk, DM Sans y JetBrains Mono), los colores por área, los fondos, los componentes y las aplicaciones. Las variables están en [`marca/styles/tokens.css`](marca/styles/tokens.css).

Fuera del repositorio quedan, a propósito, las fotos del equipo, las portadas, el QR y las landings de terceros.
