import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · «Sin dato» en vez de 0, lo privado fuera y nada de jerga")
struct SinDatoYPrivadoTests {
    static let finanzas = ["FIN-AR", "FIN-CASH", "FIN-MARGIN", "FIN-RUNWAY", "FIN-UNREC"]

    /// Ribera con los CSV de registros y movimientos vaciados (solo la cabecera).
    func vaciarCSV(_ c: MetricasApoyo.Carpeta) {
        for p in ["4 · Finanzas/Registros/emitidas.csv", "4 · Finanzas/Registros/recibidas.csv", "4 · Finanzas/Registros/pagos.csv",
                  "4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv",
                  "4 · Finanzas/Registros/Bancos/cuenta-ahorro-banco-demo/movimientos.csv"] {
            let cabecera = c.texto(p).components(separatedBy: "\n").first!
            c.escribir(p, cabecera + "\n")
        }
    }

    @Test("Con los CSV vacíos y sin saldo inicial, los números de Finanzas dicen «Sin dato», nunca 0")
    func csvVacios() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        vaciarCSV(c)
        c.cambiar("4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/Cuenta.md", "saldo_inicial: 18400.00\n", "")
        c.cambiar("4 · Finanzas/Registros/Bancos/cuenta-ahorro-banco-demo/Cuenta.md", "saldo_inicial: 5000.00\n", "")
        let p = c.panel()
        for codigo in Self.finanzas {
            let k = p.evaluador.evaluar(codigo)
            #expect(k.medida.numero == nil, "\(codigo) da \(k.textoValor)")
            #expect(k.textoValor == "Sin dato")
            #expect(k.estado == .sinDato)
            #expect(k.ritmo.estado == .sinDato)
        }
        #expect(p.evaluador.evaluar("FIN-AR").medida.motivoSinDato == "No hay facturas emitidas")
        #expect(p.evaluador.evaluar("FIN-CASH").medida.motivoSinDato == "Sin datos del banco: importa un extracto o escribe el saldo inicial")
        #expect(p.evaluador.evaluar("FIN-UNREC").medida.motivoSinDato == "No hay movimientos del banco importados")
        // El objetivo de caja tampoco se inventa un ritmo.
        #expect(p.objetivos.first { $0.objetivo.medidoPor == "FIN-RUNWAY" }?.estado == .sinDato)
        // Ningún número de toda la tabla es un 0 que salga de una fuente vacía.
        #expect(p.chequeos.first { $0.codigo == "CHQ-6" }?.n == 0)
    }

    @Test("Con los CSV vacíos pero con saldo inicial, la caja es el saldo inicial (y los meses de caja, sin dato)")
    func soloSaldoInicial() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        vaciarCSV(c)
        let p = c.panel()
        #expect(p.evaluador.evaluar("FIN-CASH").medida.numero == 23_400)       // 18.400 + 5.000 a 30/06
        #expect(p.evaluador.evaluar("FIN-RUNWAY").medida.motivoSinDato == "Hace falta al menos un mes entero de movimientos del banco")
    }

    @Test("Una cuenta sin saldo conocido deja la caja sin dato y dice cuál falta")
    func cuentaSinSaldo() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = "4 · Finanzas/Registros/Bancos/cuenta-ahorro-banco-demo/movimientos.csv"
        c.escribir(p, c.texto(p).components(separatedBy: "\n").first! + "\n")
        c.cambiar("4 · Finanzas/Registros/Bancos/cuenta-ahorro-banco-demo/Cuenta.md", "saldo_inicial: 5000.00\n", "")
        let k = c.panel().evaluador.evaluar("FIN-CASH")
        #expect(k.medida.motivoSinDato == "Falta el saldo de Cuenta ahorro Banco Demo")
    }

    @Test("Sin Metas.md: los números del catálogo, todos «Sin meta» o «Sin dato»")
    func sinMetas() {
        let c = MetricasApoyo.vacia()
        defer { c.limpiar() }
        let p = c.panel()
        #expect(p.metas == nil)
        #expect(p.kpis.count == 21)
        #expect(p.kpis.allSatisfy { $0.estado == .sinMeta || $0.estado == .sinDato })
        #expect(p.kpis.allSatisfy { $0.medida.numero == nil })     // carpeta vacía: nada de qué sacar una cifra
        #expect(!p.hayRojo)
        #expect(p.lineaMika() == "Revisé a las 8:45: nada en rojo.")
    }

    @Test("Lo privado no entra en ningún número, chequeo, tarjeta, agenda ni alerta")
    func privado() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let antes = c.panel()
        let carpeta = "4 · Finanzas/Trámites/Expediente privado"
        c.cambiar(".tls/config.yaml", "privado: []", "privado: [\"\(carpeta)\"]")
        c.escribir("\(carpeta)/Tareas/t-0099-asunto-reservado.md",
                   MetricasApoyo.tarea(99, "Asunto reservado", planificada: "2026-10-19", vence: "2026-10-10", estimacion: 3))
        c.escribir("\(carpeta)/oportunidad-reservada.md", """
        ---
        tls_type: opportunity
        nombre: Oportunidad reservada
        estado: Propuesta
        valor: 99999
        probabilidad: 90
        creada: 2026-09-01
        ---
        # Oportunidad reservada
        """)
        c.escribir("\(carpeta)/conversacion-reservada.md", """
        ---
        tls_type: conversation
        perfil: "@reservado"
        fecha: 2026-10-19
        estado: Cualificada
        ---
        # Conversación reservada
        """)
        c.escribir("\(carpeta)/Bancos/cuenta-reservada/movimientos.csv",
                   "id,fecha,concepto,importe,saldo,estado_conciliacion\nMOV-x,2026-10-18,RESERVADO,-50000.00,1.00,\n")
        let p = c.panel()
        #expect(p.foto.layout.isPrivate(VaultPath("\(carpeta)/oportunidad-reservada.md")))
        // Los números siguen igual que sin lo privado.
        for k in p.kpis { #expect(k.medida == antes.evaluador.evaluar(k.codigo).medida, "\(k.codigo) cambió") }
        #expect(p.foto.tareas.allSatisfy { !$0.tarea.ruta.raw.hasPrefix(carpeta) })
        #expect(p.foto.oportunidades.count == antes.foto.oportunidades.count)
        #expect(p.foto.cuentas.count == 2)
        #expect(p.semana.totalHoras == 0)
        #expect(p.mazo.tarjetas.map(\.id) == antes.mazo.tarjetas.map(\.id))
        #expect(p.chequeos.map(\.n) == antes.chequeos.map(\.n))
        let textos = p.mazo.tarjetas.flatMap { [$0.titulo, $0.quePasa, $0.porQueImporta, $0.siNo, $0.recomendacion] }
            + p.alertas.map(\.texto) + p.chequeos.flatMap { $0.casos.map(\.detalle) } + [p.frase(), p.lineaMika()]
        #expect(textos.allSatisfy { !$0.lowercased().contains("reservad") })
    }

    @Test("Ningún texto que fabrican las métricas con Ribera usa jerga")
    func glosario() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        for p in [c.panel(), c.panel("2026-11-02"), c.panel("2026-10-24")] {
            var textos = [p.frase(), p.lineaMika(), p.mapa.textoCuello, p.mapa.veredicto, p.etapaEmpresa.porque, p.semana.fraseHoy, p.semana.titulo]
            textos += p.kpis.flatMap { [$0.indicador, $0.textoValor, $0.textoMeta, $0.textoAlerta, $0.fuente, $0.calculo,
                                        $0.estado.etiqueta, $0.ritmo.estado.etiqueta, $0.medida.motivoSinDato ?? ""] }
            textos += p.objetivos.map { $0.motivo ?? "" }
            textos += p.ritmoAreas.flatMap { [$0.frase, $0.estado.etiqueta] }
            textos += p.etapas.flatMap { [$0.paso.que, $0.paso.porque, $0.porque] + $0.sistemas.map(\.estado.etiqueta) }
            textos += p.chequeos.flatMap { [$0.titulo, $0.regla, $0.arreglo, $0.nivel.etiqueta] + $0.acciones + $0.casos.map(\.detalle) }
            textos += p.salud.flatMap { [$0.detalle ?? "", $0.dimension.etiqueta, $0.estado.etiqueta] }
            textos += p.mapa.camino.flatMap { [$0.porque, $0.entrada, $0.salida] }
            textos += p.mazo.tarjetas.flatMap { [$0.titulo, $0.quePasa, $0.porQueImporta, $0.queHago, $0.siNo, $0.recomendacion,
                                                 $0.tipo.etiqueta, $0.prioridad.etiqueta] }
            textos += [p.foco.titulo, p.foco.recomendacion] + p.alertas.map(\.texto)
            textos += p.semana.dias.compactMap(\.aviso)
            for t in textos {
                #expect(MetricasApoyo.palabrasDeJerga(t).isEmpty, "«\(t)» usa jerga")
                #expect(!t.contains("NaN") && !t.contains("inf ") && !t.contains("—"), "«\(t)»")
            }
        }
    }
}
