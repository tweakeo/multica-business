---
tls_type: account
tls_schema: 1
id: "{{id}}"
nombre: "{{titulo}}"
banco:
alias:
iban_ultimos4:                  # nunca el número completo
moneda: EUR
saldo_inicial:
fecha_saldo_inicial:
estado: Activa                  # Activa | Cerrada
formato_extracto:               # lo rellena la app la primera vez que importas un extracto
  separador: ";"
  decimal: ","
  formato_fecha: DD/MM/AAAA
  columnas:
    fecha:
    fecha_valor:
    concepto:
    importe:
    saldo:
plantilla: "Cuenta bancaria v1"
---
# {{titulo}}
> {{banco}} · terminada en {{iban_ultimos4}} · {{estado}}

## Para qué se usa
> Guía: cobros, pagos, impuestos, ahorro… Ayuda al asistente Contable a clasificar.

## Formato del extracto
> Guía: está en las propiedades. La primera vez que sueltas un extracto, la app adivina las columnas y te enseña tres filas para que lo confirmes.

## Notas
