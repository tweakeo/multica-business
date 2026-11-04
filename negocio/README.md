# Negocio

El conocimiento de negocio con el que se construye la app. **TLB** es la teoría, **The Last System (TLS)** es el programa que la pone en marcha y **Mika Business** es este fork de Multica.

Todo es genérico. Aquí no hay datos de ninguna empresa real: ni clientes, ni importes, ni personas. Los procesos usan la figura del **director**, uno de los seis roles de TLB, y el ejemplo completo es la empresa ficticia [Asesoría Ribera](../examples/empresa-ejemplo/).

## Por dónde empezar

| Quiero entender | Dónde |
|---|---|
| La teoría entera, en orden | [TLB](<1-teoria-tlb/TLB.md>), el manual de 13 capítulos |
| Las 6 áreas | [TLB · 5 · Las seis áreas](<1-teoria-tlb/manual/TLB · 5 · Las seis áreas.md>) y las [fichas de cada área](1-teoria-tlb/fichas-de-area/) |
| Los 6 roles y las 6 etapas | [TLB · 6](<1-teoria-tlb/manual/TLB · 6 · Los seis roles.md>) y [TLB · 8](<1-teoria-tlb/manual/TLB · 8 · Las seis etapas.md>) |
| Una regla concreta («el proyecto nace del cobro») | [Notas](1-teoria-tlb/notas/): 32 ideas atómicas, una por fichero |
| Cómo trabaja una empresa en la práctica | [Áreas y sistemas](2-areas-y-sistemas/): 6 áreas y 24 sistemas, con la misma plantilla |
| Cómo se hace un diagnóstico y una propuesta | [Metodología](3-metodo/METODOLOGIA.md) (sin precios) |

## Estructura

```
negocio/
├── 1-teoria-tlb/          TLB.md · manual/ (capítulos 0–12) · fichas-de-area/ · notas/
├── 2-areas-y-sistemas/    1 · Dirección … 6 · Equipo, cada una con Área.md y Sistemas/
└── 3-metodo/              METODOLOGIA.md: dossier de diagnóstico y propuesta
```

## Cómo encaja con la app

Cada empresa es una carpeta legible con las mismas 6 áreas (`1 · Dirección/` … `6 · Equipo/`). Cada área tiene su `Área.md` y sus `Sistemas/`, y cada sistema sigue la plantilla **Para qué · Cuándo se usa · Pasos · Quién lo hace · Rutina · Qué deja hecho**. La app lee esa carpeta tal cual: el formato está en [`docs/tls/ARQUITECTURA.md`](../docs/tls/ARQUITECTURA.md).

Las reglas que la app hace cumplir salen de aquí:

- **Ninguna salida sin aprobación.** Los agentes preparan borradores; enviar, emitir, publicar o confirmar dinero lo decide una persona.
- **El proyecto nace del cobro**, no del sí.
- **Fuentes únicas.** Los importes viven solo en `4 · Finanzas/Registros/*.csv`, y los procedimientos, solo en `Sistemas/`.
- **Retirar es mover a `Archivo/`**, nunca borrar.

## Qué no está y por qué

Los datos reales de la empresa (registros, fiscal, contactos, clientes, decisiones y la oferta con precios) se quedan fuera del repositorio. Si añades algo, pasa antes `scripts/privacidad/escanear.sh`.
