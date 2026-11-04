import Foundation
import Testing
@testable import TLSCore

@Suite("Dominio · invariantes (VEN-07, ENT-01, precio, DIR-03, ENT-04)")
struct InvariantesTests {
    typealias A = DominioApoyo

    // MARK: VEN-07

    @Test("Soltar en Ganada sin cobro se bloquea con un mensaje en castellano y se ofrece Aceptada")
    func ganadaSinCobroSeBloquea() throws {
        let inv = Invariantes(snapshot: VaultSnapshot.read(root: A.ribera))
        let r = inv.comprobar(.propiedades(A.opoJorge, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []))
        #expect(r.veredicto == .bloqueado)
        #expect(!r.puedeGuardar)
        let aviso = try #require(r.bloqueos.first)
        #expect(aviso.codigo == "VEN-07")
        #expect(aviso.mensaje.hasPrefix("Ganada necesita un cobro confirmado por una persona."))
        #expect(aviso.mensaje.contains("La factura F-2026-0007 está emitida y su cobro aún no se ha confirmado"))
        #expect(A.conJerga(aviso.mensaje).isEmpty)
        let alt = try #require(aviso.alternativas.first)
        #expect(alt.titulo == "Dejarla en Aceptada" && alt.recomendada)
        #expect(alt.accion == .poner(A.opoJorge, [Property(key: "estado", value: .text("Aceptada"))]))
        // Sin factura, el motivo lo dice.
        let s = inv.comprobar(.propiedades(A.opoSergio, poner: [Property(key: "estado", value: .text("ganado"))], quitar: []))
        #expect(s.veredicto == .bloqueado)
        #expect(s.mensaje?.contains("«Sergio Nexo · Trimestrales» aún no tiene ningún cobro confirmado") == true)
    }

    @Test("Con el cobro confirmado por una persona en pagos.csv, Ganada se permite; un asistente nunca")
    func ganadaConCobro() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        // Andrés Vidal tiene F-2026-0006 cobrada (PAG-20260918-001, confirmado). La dejamos en Aceptada.
        try c.escribir(A.opoAndres, c.texto(A.opoAndres).replacingOccurrences(of: "estado: Ganada", with: "estado: Aceptada"))
        let inv = Invariantes(lectura: c.lectura())
        #expect(inv.lectura.cobrosConfirmados(de: A.opoAndres).map(\.id) == ["PAG-20260918-001"])
        let ganada = [Property(key: "estado", value: .text("Ganada"))]
        #expect(inv.comprobar(.propiedades(A.opoAndres, poner: ganada, quitar: [])).veredicto == .permitido)
        // Un asistente no la pasa a Ganada ni con cobro.
        let agente = inv.comprobar(.propiedades(A.opoAndres, poner: ganada, quitar: []), autor: .agente("comercial"))
        #expect(agente.veredicto == .bloqueado)
        #expect(agente.mensaje == "Un asistente nunca pasa una oportunidad a Ganada: llega sola cuando una persona confirma el cobro.")
        // Una persona que confirma el cobro en el mismo plan sí puede; si la fila la escribe un asistente, no cuenta.
        let plan = { (autor: Autor) in
            WritePlan(autor: autor, descripcion: "x", ops: [
                .upsertCSVRow(A.pagos, row: A.filaCobroJorge(), key: "id"),
                .mergeFrontmatter(A.opoJorge, set: ganada, unset: []),
            ])
        }
        #expect(inv.comprobar(.plan(plan(.persona("Manu")))).veredicto == .permitido)
        #expect(inv.comprobar(.plan(plan(.sistema)), autor: .sistema).veredicto == .bloqueado)
        // Ya Ganada: no se vuelve a mirar.
        let ribera = Invariantes(snapshot: VaultSnapshot.read(root: A.ribera))
        #expect(ribera.comprobar(.propiedades(VaultPath("2 · Ventas/Oportunidades/lucia-ferrer-renta.md"), poner: ganada, quitar: [])).veredicto == .permitido)
    }

    @Test("El motor no escribe nada si VEN-07 bloquea (ni un byte)")
    func motorNoEscribeLoBloqueado() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        let antes = c.huella()
        await #expect(throws: DominioError.self) {
            try await motor.ejecutar(.cambiarPropiedades(A.opoJorge, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []),
                                     autor: .persona("Manu"))
        }
        do {
            _ = try await motor.ejecutar(.cambiarPropiedades(A.opoJorge, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []),
                                         autor: .persona("Manu"))
        } catch let e as DominioError {
            #expect(e.localizedDescription.hasPrefix("Ganada necesita un cobro confirmado por una persona."))
            #expect(e.resultado.bloqueos.first?.alternativas.first?.titulo == "Dejarla en Aceptada")
        }
        #expect(c.huella() == antes)
    }

    // MARK: ENT-01

    @Test("ENT-01: un proyecto de entrega necesita su oportunidad y una oportunidad tiene uno solo")
    func proyectoDeEntregaUnico() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let primero = VaultPath("3 · Entrega/Proyectos/talleres-martin-e-hijos-trimestrales/Proyecto.md")
        try c.escribir(primero, """
        ---
        tls_type: project
        tls_schema: 1
        id: 11111111-0000-4000-8000-000000000001
        nombre: Talleres Martín · Trimestrales
        clase: entrega
        estado: En curso
        oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
        ---
        # Talleres Martín · Trimestrales

        """)
        let inv = Invariantes(lectura: c.lectura())
        let segundo = VaultPath("3 · Entrega/Proyectos/otro/Proyecto.md")
        let repetido = inv.comprobar(.crear(segundo, texto: """
        ---
        tls_type: project
        nombre: Otro
        clase: entrega
        estado: Sin empezar
        oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
        ---
        # Otro
        """))
        #expect(repetido.veredicto == .bloqueado)
        #expect(repetido.mensaje == "«Jorge Martín · Trimestrales» ya tiene su proyecto de entrega, «Talleres Martín · Trimestrales». Cada oportunidad tiene uno solo.")
        #expect(repetido.bloqueos.first?.alternativas.first?.accion == .abrir(primero))
        let sinOportunidad = inv.comprobar(.crear(segundo, texto: "---\ntls_type: project\nnombre: Suelto\nclase: entrega\n---\n# Suelto\n"))
        #expect(sinOportunidad.veredicto == .bloqueado)
        #expect(sinOportunidad.mensaje == "Un proyecto de entrega nace de una oportunidad: elige de cuál sale «Suelto».")
        // Quitarle la oportunidad al que ya existe también se bloquea; cambiar otra cosa, no.
        #expect(inv.comprobar(.propiedades(primero, poner: [], quitar: ["oportunidad"])).veredicto == .bloqueado)
        #expect(inv.comprobar(.propiedades(primero, poner: [Property(key: "fase", value: .text("Modelos"))], quitar: [])).veredicto == .permitido)
        // Uno nuevo para una oportunidad sin cobro: se guarda, con atención.
        let sergio = inv.comprobar(.crear(segundo, texto: """
        ---
        tls_type: project
        nombre: Nexo
        clase: entrega
        oportunidad: "[[sergio-nexo-trimestrales|Sergio Nexo · Trimestrales]]"
        ---
        # Nexo
        """))
        #expect(sergio.veredicto == .atencion)
        #expect(sergio.puedeGuardar)
    }

    // MARK: Precio

    @Test("El precio se copia de la Oferta: otro precio se bloquea y se ofrece el de la Oferta")
    func precioDeLaOferta() throws {
        let inv = Invariantes(snapshot: VaultSnapshot.read(root: A.ribera))
        let p = try #require(inv.precioDeOferta(para: A.opoSergio))
        #expect(p.centimos == 15000 && p.texto == "150,00 €")
        let mal = inv.comprobar(.propiedades(A.opoSergio, poner: [Property(key: "precio_congelado", value: .number("120.00"))], quitar: []))
        #expect(mal.veredicto == .bloqueado)
        #expect(mal.mensaje == "El precio sale de la Oferta: «Trimestrales v1» cuesta 150,00 €, no 120,00 €. Se baja de alcance, no de precio.")
        let alt = try #require(mal.bloqueos.first?.alternativas.first)
        #expect(alt.titulo == "Usar 150,00 € de la Oferta")
        #expect(alt.accion == .poner(A.opoSergio, [Property(key: "precio_congelado", value: .number("150.00"))]))
        #expect(inv.comprobar(.propiedades(A.opoSergio, poner: [Property(key: "precio_congelado", value: .number("150"))], quitar: [])).veredicto == .permitido)
        // Cambiar la versión de la oferta obliga a que el precio copiado cuadre con la nueva (Renta v1 = 80 €, v2 = 90 €).
        let andres = inv.comprobar(.propiedades(A.opoAndres, poner: [Property(key: "oferta_version", value: .text("[[renta-v1|Renta v1]]"))], quitar: []))
        #expect(andres.veredicto == .bloqueado)
        #expect(andres.mensaje?.contains("cuesta 80,00 €, no 90,00 €") == true)
    }

    @Test("Un servicio a medida admite cualquier precio dentro de su rango")
    func precioAMedida() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        try c.escribir(VaultPath("2 · Ventas/Productos/auditoria.md"), """
        ---
        tls_type: service
        id: 22222222-0000-4000-8000-000000000001
        nombre: Auditoría
        modelo_precio: a medida
        precio_min: 300.00
        precio_max: 900.00
        ---
        # Auditoría
        """)
        try c.escribir(VaultPath("2 · Ventas/Oportunidades/x-auditoria.md"), """
        ---
        tls_type: opportunity
        nombre: X · Auditoría
        estado: Propuesta
        servicio: "[[auditoria|Auditoría]]"
        ---
        # X · Auditoría
        """)
        let inv = Invariantes(lectura: c.lectura())
        let ruta = VaultPath("2 · Ventas/Oportunidades/x-auditoria.md")
        #expect(inv.comprobar(.propiedades(ruta, poner: [Property(key: "precio_congelado", value: .number("450"))], quitar: [])).veredicto == .permitido)
        let fuera = inv.comprobar(.propiedades(ruta, poner: [Property(key: "precio_congelado", value: .number("1000"))], quitar: []))
        #expect(fuera.veredicto == .bloqueado)
        #expect(fuera.mensaje == "El precio de «Auditoría» va de 300,00 € a 900,00 €: 1.000,00 € se sale de lo que dice la Oferta.")
    }

    // MARK: DIR-03

    static let interno = VaultPath("1 · Dirección/Proyectos/plan-de-4-semanas/Proyecto.md")
    static let textoInterno = """
    ---
    tls_type: project
    tls_schema: 1
    id: 33333333-0000-4000-8000-000000000001
    nombre: Plan de 4 semanas
    clase: interno
    estado: Sin empezar
    ---
    # Plan de 4 semanas

    """

    @Test("DIR-03: un proyecto en curso sin objetivo se guarda y queda en atención con «Colgar de un objetivo / Seguir sin objetivo»")
    func proyectoSinObjetivo() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        try c.escribir(Self.interno, Self.textoInterno)
        let motor = try await c.motor()
        let r = try await motor.ejecutar(.cambiarPropiedades(Self.interno, poner: [Property(key: "estado", value: .text("En curso"))], quitar: []),
                                         autor: .persona("Manu"))
        #expect(r.escritura.hecho)
        #expect(c.texto(Self.interno).contains("estado: En curso"))
        #expect(r.invariantes.veredicto == .atencion)
        let aviso = try #require(r.invariantes.atenciones.first)
        #expect(aviso.codigo == "DIR-03")
        #expect(aviso.mensaje == "«Plan de 4 semanas» está en curso sin objetivo. Se guarda igual; si lo cuelgas de un objetivo, cuenta en su ritmo.")
        #expect(aviso.alternativas.map(\.titulo) == ["Colgar de un objetivo", "Seguir sin objetivo"])
        guard case .elegirObjetivo(let p, let opciones) = aviso.alternativas[0].accion else { Issue.record("Falta elegir objetivo"); return }
        #expect(p == Self.interno && opciones.count == 6)
        // Sigue en atención en la carpeta (Hoy y los chequeos).
        let inv = Invariantes(lectura: c.lectura())
        #expect(inv.atenciones().contains { $0.codigo == "DIR-03" && $0.ruta == Self.interno })
        // Colgarlo de un objetivo quita la atención.
        let objetivo = VaultPath("1 · Dirección/Objetivos/mantener-al-menos-3-meses-de-caja.md")
        let (poner, quitar) = inv.colgar(Self.interno, de: objetivo)
        #expect(poner == [Property(key: "objetivo", value: .text("[[mantener-al-menos-3-meses-de-caja|Mantener al menos 3 meses de caja]]"))])
        let colgado = try await motor.ejecutar(.cambiarPropiedades(Self.interno, poner: poner, quitar: quitar), autor: .persona("Manu"))
        #expect(colgado.invariantes.veredicto == .permitido)
        #expect(!Invariantes(lectura: c.lectura()).atenciones().contains { $0.codigo == "DIR-03" })
    }

    @Test("«Seguir sin objetivo» se queda escrito y no vuelve a avisar; sin objetivos en la carpeta no hay aviso")
    func seguirSinObjetivo() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        try c.escribir(Self.interno, Self.textoInterno.replacingOccurrences(of: "Sin empezar", with: "En curso"))
        let inv = Invariantes(lectura: c.lectura())
        let aviso = try #require(inv.atenciones().first { $0.codigo == "DIR-03" })
        guard case .poner(_, let props) = aviso.alternativas[1].accion else { Issue.record("Falta seguir sin objetivo"); return }
        #expect(props == [Property(key: "sin_objetivo", value: .bool(true))])
        try c.escribir(Self.interno, Self.textoInterno.replacingOccurrences(of: "Sin empezar", with: "En curso\nsin_objetivo: true"))
        #expect(!Invariantes(lectura: c.lectura()).atenciones().contains { $0.codigo == "DIR-03" })
        // Una carpeta sin objetivos (The Last: «sin objetivos», decisión A) no avisa.
        try c.escribir(Self.interno, Self.textoInterno.replacingOccurrences(of: "Sin empezar", with: "En curso"))
        try FileManager.default.removeItem(at: VaultPath("1 · Dirección/Objetivos").url(in: c.root))
        #expect(!Invariantes(lectura: c.lectura()).atenciones().contains { $0.codigo == "DIR-03" })
    }

    // MARK: ENT-04

    @Test("ENT-04: una fecha planificada en fin de semana se corre al lunes (vence no se toca)")
    func finDeSemanaAlLunes() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let tarea = VaultPath("1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md")
        let inv = Invariantes(lectura: c.lectura())
        let r = inv.comprobar(.propiedades(tarea, poner: [Property(key: "planificada", value: .text("2026-10-24")),
                                                          Property(key: "vence", value: .text("2026-10-25"))], quitar: []))
        #expect(r.veredicto == .permitido)
        #expect(r.ajustes == [AjusteInvariante(ruta: tarea, propiedad: Property(key: "planificada", value: .text("2026-10-26")))])
        #expect(r.avisos.first?.mensaje == "El 24 oct es sábado: «Planificada» pasa al lunes 26 oct.")
        #expect(r.corregir([Property(key: "planificada", value: .text("2026-10-24"))], en: tarea)
                == [Property(key: "planificada", value: .text("2026-10-26"))])
        let motor = try await c.motor()
        _ = try await motor.ejecutar(.cambiarPropiedades(tarea, poner: [Property(key: "planificada", value: .text("2026-10-25")),
                                                                         Property(key: "vence", value: .text("2026-10-25"))], quitar: []),
                                     autor: .persona("Manu"))
        let texto = c.texto(tarea)
        #expect(texto.contains("planificada: 2026-10-26"))
        #expect(texto.contains("vence: 2026-10-25"))
        // Al crear una tarea también.
        let nueva = VaultPath("1 · Dirección/Tareas/t-0003-x.md")
        let creada = inv.comprobar(.crear(nueva, texto: "---\ntls_type: task\ntitulo: X\nplanificada: 2026-11-01\n---\n# X\n"))
        let plan = creada.corregir(WritePlan(autor: .persona("Manu"), descripcion: "x", ops: [.create(nueva, text: "---\ntls_type: task\ntitulo: X\nplanificada: 2026-11-01\n---\n# X\n")]))
        guard case .create(_, let data) = plan.ops[0] else { Issue.record("No es una creación"); return }
        #expect(String(decoding: data, as: UTF8.self) == "---\ntls_type: task\ntitulo: X\nplanificada: 2026-11-02\n---\n# X\n")
    }

    @Test("Los mensajes de las invariantes no usan jerga")
    func sinJerga() throws {
        let inv = Invariantes(snapshot: VaultSnapshot.read(root: A.ribera))
        var textos: [String] = []
        for r in [
            inv.comprobar(.propiedades(A.opoJorge, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: [])),
            inv.comprobar(.propiedades(A.opoSergio, poner: [Property(key: "precio_congelado", value: .number("1"))], quitar: [])),
            inv.comprobar(.crear(VaultPath("3 · Entrega/Proyectos/x/Proyecto.md"), texto: "---\ntls_type: project\nclase: entrega\n---\n")),
            inv.comprobar(.propiedades(A.opoJorge, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []), autor: .agente("comercial")),
        ] {
            textos += r.avisos.flatMap { [$0.mensaje] + $0.alternativas.map(\.titulo) }
        }
        textos += [DominioError.bloqueado(.permitido).localizedDescription]
        #expect(textos.count >= 6)
        for t in textos { #expect(A.conJerga(t).isEmpty, "«\(t)»") }
    }
}
