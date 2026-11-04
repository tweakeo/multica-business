---
tls_type: import_report
tls_schema: 1
id: "{{id}}"
fecha: "{{fecha}}"
fuente:                         # carpeta o programa de origen
fecha_corte:                    # lo anterior a esta fecha entra como antecedente
ficheros:
movidos:
adoptados:
archivados:
verificados:
estado: Aplicado                # Vista previa | Aplicado | Deshecho
plantilla: "Informe de importación v1"
---
# Importación del {{fecha:larga}}
> {{estado}} · {{verificados}} de {{ficheros}} ficheros verificados · no se borró nada

## Resumen
| Qué | Cuántos |
|---|---|
| Ficheros revisados | {{ficheros}} |
| Movidos a su área | {{movidos}} |
| Con propiedades añadidas | {{adoptados}} |
| Llevados a Archivo | {{archivados}} |
| Verificados (recuento y huella) | {{verificados}} |

## Por bloques
| Bloque | Ficheros | Destino |
|---|---|---|
| | | |

## Lo que se quedó donde estaba

## Duplicados
> Guía: cada pareja, con la versión que se quedó y adónde fue la otra (Archivo › Duplicados).

## Calidad de los datos
| Aviso | Fichas | Qué hacer |
|---|---|---|
| | | |

## Cómo deshacer
Se puede deshacer entera desde Carpeta › Historial de cambios mientras no termine la puesta en marcha.
