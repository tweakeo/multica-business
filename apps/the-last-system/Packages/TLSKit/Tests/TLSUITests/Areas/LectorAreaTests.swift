import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// El andamio de las áreas con Ribera (PLAN §6.5): cabecera, cifra protagonista, Control, Sistemas y activos y los
/// estados reposo / preparada / etapas 1–2. Sin dato se dice; nunca un 0 inventado; lo privado no aparece.
@Suite("Andamio de las áreas · lectura", .serialized)
@MainActor
struct LectorAreaTests {
    /// Copia de Ribera en una carpeta temporal propia.
    static func ribera() throws -> (base: URL, carpeta: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-andamio-\(UUID().uuidString)", isDirectory: true)
        let carpeta = base.appendingPathComponent("Ribera", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: SesionEscrituraTests.ribera, to: carpeta)
        return (base, carpeta)
    }

    static func lector(_ carpeta: URL, proveedor: any ProveedorNumerosArea = SinNumeros()) -> LectorArea {
        let layout = VaultLayout.load(root: carpeta).layout
        let foto = VaultSnapshot.read(root: carpeta, layout: layout)
        return LectorArea(foto: foto, hoy: LocalDate(year: 2026, month: 10, day: 19)!, proveedor: proveedor)
    }

    static func escribir(_ texto: String, _ ruta: String, en carpeta: URL) throws {
        let u = carpeta.appendingPathComponent(ruta)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: u)
    }

    static func cambiar(_ ruta: String, en carpeta: URL, _ de: String, por: String) throws {
        let u = carpeta.appendingPathComponent(ruta)
        let t = try String(contentsOf: u, encoding: .utf8)
        #expect(t.contains(de), "«\(de)» no está en \(ruta)")
        try Data(t.replacingOccurrences(of: de, with: por).utf8).write(to: u)
    }

    /// Un proveedor de números de prueba (el de verdad es del rol de números).
    struct NumerosDePrueba: ProveedorNumerosArea {
        func numeros(de area: AreaCode, codigos: [String], contexto: ContextoNumeros) -> NumerosDeArea {
            var out: [String: LecturaNumero] = [:]
            if codigos.contains("FIN-RUNWAY") {
                out["FIN-RUNWAY"] = LecturaNumero(valor: 6, texto: "6,0 meses", ritmo: .enRitmo, fuente: "Sale de 2 cuentas")
            }
            if codigos.contains("FIN-AR") { out["FIN-AR"] = LecturaNumero(valor: 1_200, texto: "1.200 €", ritmo: .enAlerta) }
            return NumerosDeArea(lecturas: out, etapa: area == .finanzas ? 2 : nil)
        }
    }

    @Test("Dirección de Ribera: cabecera, número clave del rol y Control sin datos inventados")
    func direccion() throws {
        let (base, carpeta) = try Self.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        let d = Self.lector(carpeta).leer(.direccion)
        #expect(d.titulo == "1 · Dirección")
        #expect(d.fraseConvierte == "Convierte ruido en decisiones")
        #expect(d.rol == "Director")
        #expect(d.rutaRol == VaultPath("6 · Equipo/Roles/director.md"))
        #expect(d.ocupante == nil, "Ribera no dice quién ocupa el rol: «Sin ocupante», no un nombre inventado")
        #expect(d.pregunta == nil)
        #expect(d.fase == .activa)                       // desde F4, cada área de Ribera dice su estado
        #expect(d.asistente == "Mika")
        // El número clave es el primero de los números del rol (DIR-OBJ, DIR-DEC).
        #expect(d.numeroClave == "DIR-OBJ")
        #expect(d.control.map(\.codigo) == ["DIR-APR", "DIR-DEC", "DIR-OBJ"])
        let obj = try #require(d.filaClave)
        #expect(obj.meta == "80 %" && obj.alerta == "50 %")
        #expect(obj.comoSeMide == "objetivos en trayectoria / objetivos activos · cada trimestre · más es mejor")
        // Sin el proveedor de números, todo «Sin dato»: nunca un 0.
        #expect(d.control.allSatisfy { $0.textoValor == "Sin dato" })
        #expect(d.control.allSatisfy { $0.ritmo == .sinDato })
        #expect(d.ritmo == .sinDato)
        #expect(d.pestanas == PestanaArea.allCases)
        #expect(!d.controlSustituido)
        // Sistemas del catálogo: los tres de serie, sin ficha en Ribera → «Falta».
        #expect(d.sistemas.map(\.codigo) == ["DI1", "DI2", "DI3"])
        #expect(d.sistemas.allSatisfy { $0.estado == .falta && $0.ficha == nil && $0.deSerie })
        #expect(d.sistemas.first?.plantillas.isEmpty == false, "las plantillas de la biblioteca de DI1")
        // El número del catálogo (DIR-DEC14) es el de Metas.md de Ribera (DIR-DEC); los que no mide, ninguno.
        #expect(d.sistemas.map(\.numeroClave) == ["DIR-DEC", nil, nil])
        #expect(d.metas == VaultPath("1 · Dirección/Metas.md"))
    }

    @Test("Finanzas de Ribera: la pregunta, FIN-RUNWAY como número clave y la caja oculta hasta fijar su meta")
    func finanzas() throws {
        let (base, carpeta) = try Self.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        let d = Self.lector(carpeta).leer(.finanzas)
        #expect(d.titulo == "4 · Finanzas")
        #expect(d.pregunta == "¿Hay caja y hay margen?")
        #expect(d.rol == "Financiero")
        #expect(d.asistente == "Contable")
        #expect(d.numeroClave == "FIN-RUNWAY")
        #expect(d.control.map(\.codigo) == ["FIN-AR", "FIN-CASH", "FIN-MARGIN", "FIN-RUNWAY", "FIN-UNREC"])
        let caja = try #require(d.control.first { $0.codigo == "FIN-CASH" })
        #expect(caja.meta == nil && !caja.valorVisible)
        #expect(caja.textoValor == "Oculto hasta fijar la meta")
        #expect(caja.textoMeta == "Sin meta" && caja.ritmo == .sinMeta)
        #expect(d.sistemas.map(\.codigo) == ["FI1", "FI3", "FI2"])
        #expect(d.sistemas.map(\.numeroClave) == ["FIN-AR", nil, "FIN-RUNWAY"])
        // Una meta sin decidir y el resto sin dato: el área va «Sin dato» (no «Sin meta»).
        #expect(d.ritmo == .sinDato)
    }

    @Test("Con el proveedor de números: valor, fuente y el ritmo del área es el del número más atrasado")
    func conNumeros() throws {
        let (base, carpeta) = try Self.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        let d = Self.lector(carpeta, proveedor: NumerosDePrueba()).leer(.finanzas)
        let runway = try #require(d.filaClave)
        #expect(runway.textoValor == "6,0 meses")
        #expect(runway.ritmo == .enRitmo)
        #expect(runway.lectura.fuente == "Sale de 2 cuentas")
        #expect(d.ritmo == .enAlerta, "FIN-AR va en alerta")
        #expect(d.etapa == 2)
        #expect(HeroNumber(fila: runway).contexto == "Meta 3 meses · alerta 2 meses · Sale de 2 cuentas")
    }

    @Test("Ventas: su activo sin sistema sale aparte; Marca, Entrega y Equipo leen su pregunta")
    func activosYPreguntas() throws {
        let (base, carpeta) = try Self.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        let lector = Self.lector(carpeta)
        let v = lector.leer(.ventas)
        #expect(v.activosSueltos.map(\.nombre) == ["Guion de diagnóstico v1"])
        #expect(v.pregunta == "¿De dónde sale el próximo cliente?")
        #expect(lector.leer(.marca).pregunta == "¿Nos conocen los que importan?")
        #expect(lector.leer(.equipo).pregunta == "¿Quién hace esto cuando yo no esté?")
        #expect(lector.leer(.entrega).sistemas.map(\.codigo) == ["EN1", "EN2", "EN3"])
    }

    @Test("Un sistema con ficha: su estado, sus pasos en lenguaje llano, lo sensible bloqueado y sus activos")
    func sistemaConFicha() throws {
        let (base, carpeta) = try Self.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.escribir("""
            ---
            tls_type: system
            codigo: FI1
            area: finanzas
            estado: montado
            numero_clave: FIN-AR
            revisado: 2026-10-01
            ---
            # Facturación y cobros

            ## Pasos
            | # | Paso | Quién | Modo | Deja hecho |
            |---|---|---|---|---|
            | 1 | Preparar el borrador de la factura | Contable | Te ayuda | Borrador en Fiscal |
            | 2 | Enviar la factura al cliente | Contable | Lo hace solo | Correo enviado |
            | 3 | Proponer conciliaciones | Contable | supervisado | Propuestas |
            | 4 | Revisar cobros vencidos | Financiero | Lo haces tú | Lista |
            """, "4 · Finanzas/Sistemas/Facturación y cobros.md", en: carpeta)
        try Self.escribir("""
            ---
            tls_type: asset
            nombre: Plantilla de recordatorio
            sistema: "[[Facturación y cobros]]"
            estado: En uso
            ejemplo_bueno: true
            ---
            # Plantilla de recordatorio
            """, "4 · Finanzas/Activos/plantilla-de-recordatorio.md", en: carpeta)
        let d = Self.lector(carpeta).leer(.finanzas)
        let fi1 = try #require(d.sistemas.first { $0.codigo == "FI1" })
        #expect(fi1.estado == .montado)
        #expect(fi1.ficha == VaultPath("4 · Finanzas/Sistemas/Facturación y cobros.md"))
        #expect(fi1.funciones.map(\.modo) == [.teAyuda, .siempreConTuOK, .loHaceYRevisas, .loHacesTu])
        #expect(fi1.funciones[1].sensible, "enviar al cliente sale fuera: siempre con tu OK aunque diga «Lo hace solo»")
        #expect(fi1.sinTi.map { "\($0.hechos) de \($0.total)" } == "1 de 4")
        #expect(fi1.activos.map(\.nombre) == ["Plantilla de recordatorio"])
        #expect(fi1.activos.first?.ejemploBueno == true)
        #expect(fi1.revisado == LocalDate(year: 2026, month: 10, day: 1))
        #expect(d.sistemasEnUso == 1)
        #expect(d.activosSueltos.isEmpty)
    }

    @Test("Lo privado no aparece: ni sistemas ni activos de una carpeta privada")
    func privado() throws {
        let (base, carpeta) = try Self.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        try Self.cambiar(".tls/config.yaml", en: carpeta, "privado: []", por: "privado: [\"4 · Finanzas/Trámites/Expediente privado\"]")
        try Self.escribir("---\ntls_type: system\ncodigo: FI2\nestado: montado\n---\n# Tesorería secreta\n",
                          "4 · Finanzas/Trámites/Expediente privado/tesoreria.md", en: carpeta)
        try Self.escribir("---\ntls_type: asset\nnombre: Activo reservado\n---\n# Activo reservado\n",
                          "4 · Finanzas/Trámites/Expediente privado/activo.md", en: carpeta)
        let d = Self.lector(carpeta).leer(.finanzas)
        #expect(d.sistemas.first { $0.codigo == "FI2" }?.estado == .falta)
        #expect(!d.sistemas.contains { $0.nombre.contains("secreta") })
        #expect(!d.activosSueltos.contains { $0.nombre == "Activo reservado" })
    }

    @Test("Estados: en reposo solo Resumen y aviso si otra área se activó hace menos de 30 días; etapa 1–2 sin metas")
    func estados() throws {
        let (base, carpeta) = try Self.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        // Desde F4 Ribera trae `estado:` en cada área (Marca preparada; Ventas y Entrega activas): se cambian.
        try Self.cambiar("5 · Marca/Área.md", en: carpeta, "estado: preparada", por: "estado: en reposo")
        try Self.cambiar("2 · Ventas/Área.md", en: carpeta, "estado: activa", por: "estado: activa\nactivada: 2026-10-07")
        try Self.cambiar("3 · Entrega/Área.md", en: carpeta, "estado: activa", por: "estado: preparada")
        try Self.cambiar("3 · Entrega/Área.md", en: carpeta, "convierte: Promesas en resultados",
                         por: "convierte: Promesas en resultados\netapa: 1\nocupante: agente:implementador")
        let lector = Self.lector(carpeta)
        let marca = lector.leer(.marca)
        #expect(marca.fase == .reposo)
        #expect(marca.pestanas == [.resumen])
        let r = try #require(marca.activacionReciente)
        #expect(r.area == .ventas && r.haceDias == 12)
        #expect(AreaScaffold.avisoActivacion(r) == "Activaste 2 · Ventas hace 12 días. Lo recomendable es un área nueva cada 30 días.")
        #expect(AreaScaffold.pestanaElegida("Control", datos: marca) == .resumen)
        let entrega = lector.leer(.entrega)
        #expect(entrega.fase == .preparada)
        #expect(entrega.ocupante == "Implementador (asistente)")
        #expect(entrega.etapa == 1)
        // Entrega tiene metas en Ribera (ENT-ONTIME, ENT-OVERDUE): Control se ve aunque esté en la etapa 1.
        #expect(entrega.hayMetas && !entrega.controlSustituido)
        // Sin ninguna meta decidida, en la etapa 1 se sustituye.
        try Self.cambiar("1 · Dirección/Metas.md", en: carpeta, "| ENT-ONTIME | Tareas de entrega a tiempo | 90 % | 75 % |",
                         por: "| ENT-ONTIME | Tareas de entrega a tiempo |  |  |")
        try Self.cambiar("1 · Dirección/Metas.md", en: carpeta, "| ENT-OVERDUE | Tareas vencidas | 0 | 5 |",
                         por: "| ENT-OVERDUE | Tareas vencidas |  |  |")
        #expect(Self.lector(carpeta).leer(.entrega).controlSustituido)
        // Ventas, activa desde hace 12 días: no se avisa de sí misma.
        #expect(lector.leer(.ventas).activacionReciente == nil)
        #expect(lector.leer(.ventas).fase == .activa)
    }

    @Test("Textos llanos: ocupantes, modos, lo sensible y «Sin meta»")
    func textos() {
        #expect(LectorArea.nombreOcupante("agente:comercial") == "Comercial (asistente)")
        #expect(LectorArea.nombreOcupante("[[elena|Elena]]") == "Elena")
        #expect(LectorArea.nombreOcupante("  ") == nil)
        #expect(ModoFuncion(leyendo: "asistido") == .teAyuda)
        #expect(ModoFuncion(leyendo: "Lo hace y revisas") == .loHaceYRevisas)
        #expect(ModoFuncion(leyendo: "autonomo") == .loHaceSolo)
        #expect(ModoFuncion(leyendo: "¿?") == .sinDecidir)
        #expect(FuncionDeSistema.esSensible("Publicar la pieza en LinkedIn"))
        #expect(FuncionDeSistema.esSensible("Emitir la factura"))
        #expect(!FuncionDeSistema.esSensible("Preparar el borrador del correo"))
        let sinMeta = FilaControl(codigo: "FIN-CASH", indicador: "Caja", meta: "Sin meta", alerta: nil)
        #expect(sinMeta.metaDecidida && !sinMeta.tieneMeta && sinMeta.valorVisible)
        #expect(sinMeta.textoValor == "Sin dato" && sinMeta.ritmo == .sinMeta)
        #expect(RitmoNumero.deArea([.enRitmo, .atencion, .sinDato]) == .atencion)
        #expect(RitmoNumero.deArea([]) == .sinDato)
        #expect(RitmoNumero.deArea([.sinMeta, .sinDato]) == .sinDato)
        #expect(RitmoNumero.deArea([.sinMeta, .sinMeta]) == .sinMeta)
        #expect(RitmoNumero.deArea([.sinMeta, .enRitmo]) == .enRitmo)
        #expect(LectorArea.codigoEnMetas("VEN-STALE7", codigos: ["VEN-STALE", "VEN-WON"]) == "VEN-STALE")
        #expect(LectorArea.codigoEnMetas("ENT-INC", codigos: ["ENT-ONTIME"]) == nil)
        for r in RitmoNumero.allCases { #expect(!r.palabra.isEmpty) }
        for e in EstadoSistema.allCases { #expect(EstadoSistema(leyendo: e.palabra) == e) }
    }
}
