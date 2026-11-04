# Empresa de ejemplo: Asesoría Ribera

Una carpeta de empresa **ficticia** con la estructura «humana» (`.tls/layout.json` → `{"preset": "humana"}`), que es la que lee el fork web (`scripts/tls/the-last.sh`). Todos los nombres, importes y números de documento son inventados.

Sirve para probar la app sin datos reales:

```sh
cp -R examples/empresa-ejemplo "$HOME/TLS/Asesoría Ribera"
export TLS_INSTANCE_DIR="$HOME/Library/Application Support/TLS/Ribera" TLS_API_PORT=8091 TLS_WEB_PORT=3002
export TLS_COMPANY_FOLDER="$HOME/TLS/Asesoría Ribera"
scripts/tls/the-last.sh setup
scripts/tls/the-last.sh abrir     # http://localhost:3002
```

`TLS_INSTANCE_DIR` y los puertos separan esta instancia de cualquier otra del mismo Mac. Los requisitos están en [`docs/tls/DESPLIEGUE.md`](../../docs/tls/DESPLIEGUE.md).

La app escribe en la carpeta (marcas de `id`, filas de `Registros/`), así que trabaja siempre sobre una copia, nunca sobre esta.

La app nativa trae su propio ejemplo, más completo y con el mismo nombre, en `apps/the-last-system/App/Recursos/Ejemplos/Asesoria-Ribera/`.

| Dónde | Qué hay |
|---|---|
| `Empresa.md` | Qué es la empresa y sus reglas |
| `1 · Dirección/Decisiones.md` | Una línea por decisión |
| `2 · Ventas/` | Una empresa cliente y su contacto |
| `4 · Finanzas/Registros/` | `emitidas.csv`, `recibidas.csv`, `pagos.csv` y un extracto por importar, con su `Esquema.md` |
| `Sistemas/` de cada área | Vacíos: los procedimientos genéricos están en `negocio/2-areas-y-sistemas/` |
