---
tls_type: project
tls_schema: 1
id: "{{id}}"
nombre: "{{empresa.nombre}} · {{servicio.nombre}}"
clase: entrega
estado: Sin empezar             # Sin empezar | En curso | Pausado | Cerrado | Archivado
fase: Arranque
empresa: "{{empresa.enlace}}"
contacto: "{{contacto.enlace}}"
oportunidad: "{{oportunidad.enlace}}"   # obligatoria y única
servicio: "{{servicio.enlace}}"
plan: "{{plan.enlace}}"
responsable: "{{yo}}"
inicio: "{{fecha}}"
fin: "{{plan.fin}}"
fecha_cierre:
sesiones_incluidas: "{{plan.sesiones_incluidas}}"
horas_previstas:
franja:                         # «martes 10:00»
portal:
plantilla: "Proyecto de entrega v1"
---
# {{nombre}}
> {{estado}} · fase {{fase}} · {{sesiones_hechas}} de {{sesiones_incluidas}} sesiones · fin {{fin:corta}}

## Resultado prometido
> Guía: la frase destino del cliente, literal y entre comillas.

## Traspaso
| Pieza | Estado | Dónde está |
|---|---|---|
| Pago inicial confirmado | Falta | |
| Acuerdo aceptado | Falta | |
| Datos fiscales y de contacto | Falta | |
| Dolores y cuello confirmado | Falta | |
| Frase destino literal | Falta | |
| Objetivos por área | Falta | |

> Guía: «Sí» o «Falta». Si falta algo, el proyecto no arranca y vuelve a Ventas con una tarea.

## Alcance
| Incluye | No incluye |
|---|---|
| | |

## Quién trabaja en él
| Persona | Papel | Acuerdo |
|---|---|---|
| {{yo}} | Responsable | — |

> Guía: un colaborador sin acuerdo enlazado genera un aviso en Equipo.

## Enlaces de interés

## Riesgos
