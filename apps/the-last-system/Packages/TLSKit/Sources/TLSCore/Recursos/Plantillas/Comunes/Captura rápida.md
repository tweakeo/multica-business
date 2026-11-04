---
tls_type: capture
tls_schema: 1
id: "{{id}}"
creada: "{{fecha}}"
hora: "{{hora}}"
canal: teclado                  # teclado | voz | archivo | correo
estado: Por ordenar             # Por ordenar | Ordenada
destino:                        # adónde fue al ordenarla
plantilla: "Captura rápida v1"
---
# {{titulo}}
> {{estado}} · {{creada:corta}} {{hora}}

{{cursor}}
