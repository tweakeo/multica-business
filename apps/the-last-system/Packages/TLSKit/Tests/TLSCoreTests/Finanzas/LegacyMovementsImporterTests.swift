import Foundation
import Testing
@testable import TLSCore

@Suite("Finanzas: movimientos heredados en preparación")
struct LegacyMovementsImporterTests {
    typealias A = FinanzasApoyo

    static let importar = "4 · Finanzas/Registros/importar/"

    /// 71 movimientos sintéticos en tres ficheros con formatos distintos (nunca datos reales).
    static func ficherosSinteticos() -> [String: String] {
        // T1: como una exportación de Notion, con «;», coma decimal y el importe sin IVA.
        var t1 = "Concepto;Importe;Tipo;Fecha Cobro/Pago;Fecha Factura;IVA;Retención IRPF;Número Factura;Categoría;Tipo Fiscal;Cobrado/Pagado\n"
        for i in 1...20 {
            let dia = String(format: "%02d", (i % 27) + 1)
            t1 += "Servicio cliente \(i);100,00;Ingreso;2026-02-\(dia);2026-02-\(dia);21,00;;F2600\(String(format: "%02d", i));Servicios;ingreso;Yes\n"
        }
        for i in 1...10 {
            t1 += "Herramienta \(i);10,00;Gasto;2026-03-\(String(format: "%02d", i));2026-03-\(String(format: "%02d", i));2,10;;;Software;estandar;No\n"
        }
        t1 += "Cuota autónomos marzo;294,00;Gasto;2026-03-31;;;;;Seguridad Social;reta;Yes\n"
        // T2: con «,», total con IVA y sin número en los gastos.
        var t2 = "fecha,concepto,tercero,total,tipo,numero_factura,cobrado\n"
        for i in 1...15 {
            t2 += "2026-05-\(String(format: "%02d", i)),Consultoría,Cliente \(i),242.00,ingreso,F2601\(String(format: "%02d", i)),no\n"
        }
        for i in 1...10 {
            t2 += "2026-06-\(String(format: "%02d", i)),Material,Proveedor \(i),-36.30,gasto,,sí\n"
        }
        // T3: con fecha DD/MM/AAAA; dos filas idénticas y un impuesto (sin factura).
        var t3 = "Fecha,Concepto,Proveedor,Importe,Tipo\n"
        for i in 1...12 {
            t3 += "\(String(format: "%02d", i))/08/2026,Alquiler,Inmobiliaria Sintética,-500.00,Gasto\n"
        }
        t3 += "20/07/2026,Pago fraccionado,AEAT,-120.00,Gasto\n"
        t3 += "21/07/2026,Taxi,Taxis Uno,-12.00,Gasto\n"
        t3 += "21/07/2026,Taxi,Taxis Uno,-12.00,Gasto\n"
        return [importar + "2026 T1 movimientos.csv": t1, importar + "2026 T2 movimientos.csv": t2,
                importar + "2026 T3 movimientos.csv": t3]
    }

    @Test func losSetentaYUnoQuedanEnPreparacionSinConfirmar() async throws {
        let env = A.ribera()
        defer { env.limpiar() }
        for (ruta, texto) in Self.ficherosSinteticos() { env.escribir(ruta, texto) }
        // T3 no dice qué es un impuesto: se marca como Impuestos en su categoría para que vaya solo a pagos.
        let t3 = Self.importar + "2026 T3 movimientos.csv"
        env.escribir(t3, env.texto(t3)!.replacingOccurrences(of: "Fecha,Concepto,Proveedor,Importe,Tipo\n",
                                                             with: "Fecha,Concepto,Proveedor,Importe,Tipo,Categoría\n")
            .replacingOccurrences(of: "AEAT,-120.00,Gasto\n", with: "AEAT,-120.00,Gasto,Impuestos\n"))
        let bus = try await env.bus()
        let antes = env.huella()
        let confirmadosAntes = RegistrosFinanzas(snapshot: env.foto()).pagos.filter(\.confirmado).count

        let imp = LegacyMovementsImporter(snapshot: env.foto())
        #expect(imp.ficheros.count == 3)
        let prep = imp.preparar()
        #expect(prep.avisos.isEmpty)
        #expect(prep.filas.count == 71)
        #expect(prep.nuevas.count == 71)
        #expect(prep.resumen == "71 movimientos heredados · 71 nuevos · 0 ya cargados")
        let porDestino = Dictionary(grouping: prep.filas, by: \.destino).mapValues(\.count)
        #expect(porDestino == [.emitida: 35, .recibida: 34, .pago: 2])
        // El importe de Notion es la base: total = 100 + 21.
        let primera = try #require(prep.filas.first { $0.registro["numero_documento"] == "F260001" })
        #expect(primera.registro["id"] == "F260001")
        #expect(primera.registro["total_documento"] == "121.00")
        #expect(primera.pago?["verificacion"] == "")
        #expect(primera.pago?["documento_id"] == "F260001")
        #expect(primera.pago?["evidencia"] == "Registros/importar/2026 T1 movimientos.csv#fila-2")
        // emitidas.csv de Ribera no tiene columnas de base ni IVA: se avisa de lo que no cabe.
        #expect(prep.columnasQueNoCaben.contains("iva"))

        let plan = try #require(prep.plan(autor: A.manu))
        _ = try await bus.ejecutar(plan)
        let regs = A.fin + "/Registros/"
        #expect(A.cambiados(antes, env.huella()) == [regs + "emitidas.csv", regs + "recibidas.csv", regs + "pagos.csv"])
        let r = RegistrosFinanzas(snapshot: env.foto())
        // Ninguna fila nueva confirmada; las facturas, en preparación.
        #expect(r.pagos.filter(\.confirmado).count == confirmadosAntes)
        #expect(r.emitidas.filter(\.sinRevisar).count == 35)
        #expect(r.recibidas.filter(\.sinRevisar).count == 34)
        let heredados = r.pagos.filter { ($0.evidencia ?? "").hasPrefix("Registros/importar/") }
        #expect(heredados.count == 32)
        #expect(r.pagos.allSatisfy { !($0.evidencia ?? "").hasPrefix("Registros/importar/") || $0.verificacion == nil })
        // El banco no se toca: ni movimientos inventados ni conciliaciones.
        #expect(r.movimientos.count == 30)
        // Las dos filas idénticas del taxi son dos gastos.
        #expect(r.recibidas.filter { $0.tercero == "Taxis Uno" }.map(\.id) == ["REC-20260721-001", "REC-20260721-002"])
        // Los ingresos sin revisar no cuentan como cobros pendientes.
        #expect(Tesoreria(registros: r, hoy: A.relojRibera.hoy).cobrosPendientes.map(\.factura.id) == ["F-2026-0007"])

        // Otra vez: nada nuevo.
        let otra = LegacyMovementsImporter(snapshot: env.foto()).preparar()
        #expect(otra.nuevas.isEmpty)
        #expect(otra.resumen == "71 movimientos heredados · 0 nuevos · 71 ya cargados")
        #expect(otra.plan(autor: A.manu) == nil)

        _ = try await bus.deshacer(autor: A.manu)
        #expect(env.huella() == antes)
    }

    @Test func registrosQueNoExistenSeCreanConSuCabecera() async throws {
        let env = A.empresa([
            Self.importar + "viejo.csv": "fecha,concepto,tercero,total,tipo\n2026-01-05,Venta,Cliente,50.00,ingreso\n2026-01-06,,,,\nmal,x,y,1.00,gasto\n",
        ])
        defer { env.limpiar() }
        let bus = try await env.bus()
        let prep = LegacyMovementsImporter(snapshot: env.foto()).preparar()
        #expect(prep.nuevas.count == 1)
        #expect(prep.avisos.count == 2)
        _ = try await bus.ejecutar(try #require(prep.plan(autor: .sistema)))
        let texto = try #require(env.texto("4 · Finanzas/Registros/emitidas.csv"))
        #expect(texto == A.cabEmitidas + "EMI-20260105-001,2026-01-05,Cliente,,,50.00,,,,pendiente,importacion\n")
        #expect(env.texto("4 · Finanzas/Registros/pagos.csv") == nil)
    }

    @Test func soloLoDeLaCarpetaYNadaPrivado() {
        let env = A.empresa([
            ".tls/config.yaml": "version: 1\nclase: copia\nprivado:\n  - \"4 · Finanzas/Registros/importar/privado.csv\"\n",
            Self.importar + "privado.csv": "fecha,total,tipo\n2026-01-05,50.00,ingreso\n",
            Self.importar + "notas.md": "# no es un csv\n",
        ])
        defer { env.limpiar() }
        let imp = LegacyMovementsImporter(snapshot: env.foto())
        #expect(imp.ficheros.isEmpty)
        #expect(imp.preparar().filas.isEmpty)
    }
    @Test("En un registro de antes (G3: id, fecha, cliente, concepto, importe), lo cargado no vuelve a salir como nuevo")
    func registroDeAntesNoDuplica() async throws {
        // La fixture con formato G3 (F3 · «Movimientos del banco» de la copia de G3: nunca duplicar los heredados).
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima, nombre: "G3")
        defer { env.limpiar() }
        var csv = "fecha,concepto,tercero,total,tipo,numero_factura,cobrado\n"
        for i in 1...5 { csv += "2026-05-0\(i),Consultoría,Cliente \(i),242.00,ingreso,F26010\(i),no\n" }
        env.escribir("4 · Finanzas/Registros/importar/2026 T2 movimientos.csv", csv)
        let bus = try await env.bus()
        // Las dos facturas de antes se leen con sus columnas de antes (fecha, cliente, importe).
        let antes = RegistrosFinanzas(snapshot: env.foto())
        #expect(antes.emitidas.map(\.total) == [120_000, 9_000])
        #expect(antes.emitidas.first?.tercero == "Ferretería Ejemplo, S.L.")
        #expect(antes.emitidas.first?.fecha == LocalDate(parsing: "2026-09-15"))

        let prep = LegacyMovementsImporter(snapshot: env.foto()).preparar()
        #expect(prep.resumen == "5 movimientos heredados · 5 nuevos · 0 ya cargados")
        // Lo que el registro de antes no puede guardar se dice antes de cargar.
        #expect(prep.columnasQueNoCaben.contains("estado_revision"))
        #expect(!prep.columnasQueNoCaben.contains("tercero"))
        _ = try await bus.ejecutar(try #require(prep.plan(autor: A.manu)))

        let filas = A.filas(env, A.fin + "/Registros/emitidas.csv")
        #expect(filas.count == 7)
        #expect(filas.last?["cliente"] == "Cliente 5")
        #expect(filas.last?["importe"] == "242.00")
        #expect(filas.last?["fecha"] == "2026-05-05")
        // La segunda vez: nada nuevo (antes se ofrecían otra vez los cinco).
        let otra = LegacyMovementsImporter(snapshot: env.foto()).preparar()
        #expect(otra.resumen == "5 movimientos heredados · 0 nuevos · 5 ya cargados")
        #expect(otra.plan(autor: A.manu) == nil)
    }
}
