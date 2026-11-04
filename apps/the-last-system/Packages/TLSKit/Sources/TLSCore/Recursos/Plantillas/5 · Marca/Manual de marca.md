---
tls_type: brand
tls_schema: 1
id: "{{id}}"
nombre: "{{mi_empresa.nombre}}"
eslogan:
estado: Borrador                # Borrador | Aprobado
version: 1
logo: "{{marca.logo}}"          # enlace a Activos/Logo/Logo.md
color_principal:                # hex, p. ej. "#E6007E"
color_secundario:
fondo_claro: "#FFFFFF"
fondo_oscuro: "#000000"
tipografia_titulos:             # vacío: la app usa DM Sans en todo
tipografia_texto:
tipografia_cifras:
tono: []                        # tres palabras
plantilla: "Manual de marca v1"
---
# Manual de marca de {{mi_empresa.nombre}}
> {{estado}} · versión {{version}} · tono: {{tono}}

> Guía: las propiedades de arriba las leen todos los PDF y el portal del cliente. Cambiar un color aquí cambia los documentos nuevos; los ya emitidos no se tocan.

## Esencia
> Guía: qué hacemos y para quién, en una frase.

## A quién hablamos (y a quién no)

## Cómo hablamos
| Decimos | No decimos |
|---|---|
| | |

## Bios
| Bio | Texto | Límite |
|---|---|---|
| Larga | | 600 caracteres |
| Corta | | 160 caracteres |
| Mínima | | 60 caracteres |

## Logo
> Guía: enlace al kit de logo, con sus variantes y usos.

## Color
- **Principal** `{{color_principal}}` — botones, cifras destacadas y cabeceras de documento
- **Secundario** `{{color_secundario}}` — apoyos y gráficas
- **Fondo claro** `{{fondo_claro}}`
- **Fondo oscuro** `{{fondo_oscuro}}`

> Guía: la app comprueba si el color principal se lee como texto (contraste 4,5:1) sobre fondo claro y oscuro. Si no llega, usa para el texto una variante más oscura o más clara del mismo color y te la enseña. Como relleno de botones vale el original.

## Tipografía
- **Títulos** `{{tipografia_titulos}}`
- **Texto** `{{tipografia_texto}}`
- **Cifras** `{{tipografia_cifras}}`

## Formatos
| Formato | Medida | Para qué |
|---|---|---|
| Carrusel | 1080 × 1350 | Redes |
| Vídeo vertical | 1080 × 1920 | Redes |
| Miniatura | 1280 × 720 | Vídeo horizontal |
| Avatar | 1024 × 1024 | Perfil |
| Portada de redes | 1500 × 500 | Cabecera |
| Documento | A4 | Propuestas, facturas, contratos |

## Plantillas visuales
> Guía: enlaces a las portadas y plantillas de Activos que usan este manual.

## Revisión de materiales
| Material | Veredicto | Qué cambiar |
|---|---|---|
| | Apta | |

> Guía: veredicto: Apta, Ajustar o Replantear.
