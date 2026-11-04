import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Revisión final de F2 (diseño y claridad): lo que arregló el corrector final, como pruebas de regresión. Siempre sobre
/// copias temporales de Ribera; nunca el ejemplo del repositorio.
@Suite("Revisión final F2 · diseño y claridad", .serialized)
@MainActor
struct RevisionFinalF2Tests {
    // MARK: P1 · la caja sin extracto

    /// Regla 3: sin extracto del banco (registros vacíos), la caja no puede decir «0,00 € · 0,0 %» ni «no cambia»:
    /// no se sabe. Ni en Finanzas › Operación (`VariacionCajaFinanzas`) ni en el módulo de Hoy y del Resumen.
    @Test("Caja · sin movimientos del banco, la variación es «Sin dato», nunca «0,00 €» ni «no cambia»")
    func cajaSinExtracto() throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        // Con Ribera tal cual, en tres meses hay movimientos: la variación se calcula.
        let normal = c.hoy()
        let tresMeses = try #require(normal.modulos.caja.series[.trimestre])
        let v = try #require(VariacionCajaFinanzas(tresMeses))
        #expect(!v.sinMovimientos)
        #expect(v.texto != "Sin dato")
        #expect(ModuloCaja.variacion(tresMeses)?.hasPrefix("Sin dato") == false)
        // Con los registros vacíos (solo el saldo inicial de cada cuenta).
        HoyApoyo.vaciarRegistros(c)
        let vacio = c.hoy()
        var vistas = 0
        for r in RangoCaja.allCases {
            let serie = vacio.modulos.caja.series[r] ?? []
            guard let v = VariacionCajaFinanzas(serie), v.desde.fecha < v.hasta.fecha else { continue }
            vistas += 1
            #expect(v.sinMovimientos, "\(r)")
            #expect(v.texto == "Sin dato", "\(r)")
            #expect(v.frase(r) == "Sin dato: falta el extracto de este periodo.", "\(r)")
            #expect(!v.frase(r).contains("no cambia"))
            #expect(ModuloCaja.variacion(serie) == "Sin dato: falta el extracto de este periodo", "\(r)")
        }
        #expect(vistas > 0)
    }

    // MARK: P2 · «rojo» es una sola cosa

    /// Con Ribera sin nada en rojo, Alertas desaparece y Mika dice «nada en rojo»: entonces ningún área ni número puede ir
    /// «En alerta» (✖). Con Ribera tal cual, solo van en rojo las áreas que tienen algo en Alertas.
    @Test("Rojo · «En alerta» solo para lo que está en la sección Alertas de Hoy")
    func rojoEsUnaSolaCosa() async throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let d = c.hoy()
        #expect(d.hayRojo)
        for r in d.panel.ritmoAreas where r.estado == .enAlerta { #expect(d.panel.enAlerta(r.area), "\(r.area)") }
        #expect(d.panel.ritmo(.ventas)?.estado == .enAlerta)
        for k in d.panel.kpis where NumerosDelNucleo.ritmo(k) == .enAlerta { #expect(d.panel.enAlerta(codigo: k.codigo), "\(k.codigo)") }
        try await HoyApoyo.quitarRojos(c)
        let sinRojo = c.hoy()
        #expect(sinRojo.alertas.isEmpty)
        #expect(sinRojo.lineaMika.contains("nada en rojo"))
        #expect(!sinRojo.panel.ritmoAreas.contains { $0.estado == .enAlerta })
        #expect(!sinRojo.panel.kpis.contains { NumerosDelNucleo.ritmo($0) == .enAlerta })
        // Lo que va muy por detrás sigue diciéndose, en ámbar.
        #expect(sinRojo.panel.ritmo(.ventas)?.estado == .atencion)
        #expect(OperacionComun.ritmo(.critico) == .atencion)
    }

    // MARK: P2 · cifras con punto de miles

    @Test("Metas · la meta y la alerta se enseñan como el valor de al lado: «6.000 €», no «6000 €»")
    func umbralesConPuntoDeMiles() {
        #expect(Umbral(texto: "6000 €").textoVisible == "6.000 €")
        #expect(Umbral(texto: "3000 €").textoVisible == "3.000 €")
        #expect(Umbral(texto: "80 %").textoVisible == "80 %")
        #expect(Umbral(texto: "3 meses").textoVisible == "3 meses")
        #expect(Umbral(texto: "1 mes").textoVisible == "1 mes")
        #expect(Umbral(texto: "8").textoVisible == "8")
        // Lo que no es solo una cifra queda como está escrito.
        #expect(Umbral(texto: "Todos").textoVisible == "Todos")
        #expect(Umbral(texto: "3–6").textoVisible == "3–6")
        #expect(Umbral(texto: "Con histórico propio").textoVisible == "Con histórico propio")
        let fila = FilaControl(codigo: "VEN-WON", indicador: "Ventas cobradas del mes", meta: "6000 €", alerta: "3000 €")
        #expect(fila.textoMeta == "6.000 €" && fila.textoAlerta == "3.000 €")
        // Para editar, la celda tal cual.
        #expect(fila.meta == "6000 €")
        // Control: una frase llana para cada número (la fórmula va plegada en «Cómo se calcula»).
        #expect(fila.enPalabras?.isEmpty == false)
    }

    // MARK: P2 · incidencias en el Resumen de Entrega

    /// El módulo de incidencias decía «Sin dato: las incidencias llegan con el portal del cliente» mientras Operación
    /// contaba ENT-INC. Ahora es el mismo número.
    @Test("Entrega · el módulo de incidencias cuenta ENT-INC, como Operación")
    func incidenciasEnElResumen() throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let sin = try #require(c.hoy().modulos.cifras[.incidencias])
        #expect(sin.cifra == nil)
        #expect(sin.vacio?.contains("las incidencias llegan con el portal") != true)
        let carpeta = "3 · Entrega/Proyectos/talleres-martin-trimestrales-2026"
        c.escribir(carpeta + "/Proyecto.md", """
            ---
            tls_type: project
            tls_schema: 1
            id: final-proyecto-talleres
            nombre: Talleres Martín · Trimestrales 2026
            clase: entrega
            estado: En curso
            oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
            inicio: 2026-10-19
            ---
            # Talleres Martín · Trimestrales 2026

            """)
        c.escribir(carpeta + "/Incidencias.md", """
            ---
            tls_type: log
            tls_schema: 1
            id: final-incidencias-talleres
            registro: incidencias
            ---
            # Incidencias

            | ID | Fecha | Quién reporta | Email | Tipo | Severidad | Estado | Descripción | Responsable | Resolución |
            |---|---|---|---|---|---|---|---|---|---|
            | INC-001 | 2026-10-14 12:00 | Jorge Martín |  | Accesos | Grave | Recibida | No puede entrar. | Manu |  |

            """)
        let d = c.hoy()
        let m = try #require(d.modulos.cifras[.incidencias])
        let ent = d.panel.evaluador.evaluar("ENT-INC")
        #expect(ent.medida == .cifra(1))
        #expect(m.cifra == ent.textoValor)
        #expect(m.linea?.contains("1 abierta") == true)
    }

    // MARK: P2 · tus decisiones

    @Test("Decisiones · tus fichas de decisión van en «Por decidir», no en «Propuestas de mejora»")
    func porDecidir() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let d = c.hoy()
        let propias = d.decisiones.filter { $0.tipo == .propuesta }
        #expect(!propias.isEmpty)
        #expect(propias.allSatisfy { $0.tipo.grupo == "Por decidir" })
    }

    // MARK: P2 · la barra lateral

    @Test("Barra lateral · «N para hoy» bajo Tareas y «N quietas» bajo Ventas, como DISENO §6")
    func barraLateral() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        defer { s.close() }
        let almacen = AlmacenHoy.de(s)
        await almacen.actualizar()
        let d = try #require(almacen.datos)
        let quietas = d.panel.foto.oportunidades.filter { $0.abierta && ($0.diasQuieta(hoy: d.hoy) ?? 0) >= 7 }.count
        #expect(quietas > 0)
        #expect(s.barraLateral.datos[.area(.ventas)]?.atencion == (quietas == 1 ? "1 quieta" : "\(quietas) quietas"))
        let paraHoy = ResumenTareas(LectorTareas.filas(foto: try #require(AlmacenRelaciones.de(s).foto)), hoy: d.hoy).paraHoy
        let debajo = s.barraLateral.datos[.tareas]?.debajo
        #expect(debajo == (paraHoy == 0 ? nil : paraHoy == 1 ? "1 para hoy" : "\(paraHoy) para hoy"))
    }

    // MARK: ENT-04 dicho en el aviso

    @Test("ENT-04 · al poner un sábado en una celda de fecha, el aviso dice que pasa al lunes")
    func avisoEnt04() async throws {
        let apoyo = ApoyoAreasB()
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let ruta = VaultPath(HoyApoyo.t1)
        try await sesion.escribir(.cambiarPropiedades(ruta, poner: [Property(key: "planificada", value: .text("2026-10-24"))], quitar: []),
                                  aviso: "«Subir Trimestrales»: Planificada pasa a sáb 24 oct")
        #expect(apoyo.texto(e, HoyApoyo.t1)?.contains("planificada: 2026-10-26") == true)
        #expect(sesion.aviso?.texto.contains("pasa al lunes") == true)
    }
}
