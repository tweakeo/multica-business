import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// PLAN §5.1 y SISTEMAS §6.1: los ocho asistentes de serie, completos y coherentes con el catálogo de `tls-mcp`
/// (PLAN §5.4), con el estándar (funciones, números y sistemas) y con lo que consume el motor.
@Suite("Asistentes de serie · catálogo")
struct CatalogoAsistentesTests {
    let perfiles = PerfilDeAsistente.deSerie

    @Test("Ocho asistentes, en orden: Mika, los de las áreas y los dos del sistema")
    func ocho() {
        #expect(perfiles.map(\.slug) == ["mika", "comercial", "implementador", "contable", "marca", "equipo", "cartero", "ordenador"])
        #expect(Set(perfiles.map(\.slug)).count == 8)
        #expect(perfiles.map(\.nombre) == ["Mika", "Comercial", "Implementador", "Contable", "Marca", "Equipo", "Cartero", "Ordenador"])
        #expect(perfiles.filter(\.coordinador).map(\.slug) == ["mika"])
        let areas = perfiles.compactMap { p in p.area.map { (p.slug, $0) } }
        #expect(areas.map(\.1) == [.direccion, .ventas, .entrega, .finanzas, .marca, .equipo])
        #expect(perfiles.filter(\.esDelSistema).map(\.slug) == ["cartero", "ordenador"])
        #expect(perfiles.filter(\.esDelSistema).allSatisfy { $0.area == nil && $0.clavesDeArea == ["buzon"] })
        for p in perfiles {
            #expect(AgentPaths.isSafeName(p.slug), "\(p.slug)")
            #expect(!p.pregunta.isEmpty && p.pregunta.hasPrefix("¿") && p.pregunta.hasSuffix("?"), "\(p.slug)")
            #expect(!p.mision.isEmpty && !p.nunca.isEmpty && !p.escalado.isEmpty && !p.entrega.isEmpty, "\(p.slug)")
        }
        // Mika y el Ordenador leen todas las áreas; el coordinador es Mika.
        #expect(PerfilDeAsistente.mika.clavesQueLee == ["todas"])
        #expect(PerfilDeAsistente.ordenador.clavesQueLee == ["todas"])
    }

    @Test("Las preguntas fijas son las de los roles del estándar")
    func preguntas() {
        let roles = CatalogoPrograma.deSerie.roles
        for p in perfiles {
            guard let a = p.area, let rol = roles.first(where: { $0.area == a }) else { continue }
            #expect(p.pregunta == rol.pregunta, "\(p.slug)")
        }
    }

    @Test("Herramientas: las 31 de tls-mcp, cada una de un grupo, y las exclusivas solo en su asistente")
    func herramientas() {
        // F5 · mail: 31 con `tls_anotar_correo` (el registro del correo del Buzón, solo el Cartero).
        #expect(HerramientaDeAsistente.allCases.count == 31)
        // El motor enseña en el brief las mismas (BriefBuilder), con su frase.
        #expect(Set(HerramientaDeAsistente.allCases.map(\.rawValue)) == Set(BriefBuilder.herramientas.map(\.nombre)))
        let porGrupo = Dictionary(grouping: HerramientaDeAsistente.allCases, by: \.grupo).mapValues(\.count)
        #expect(porGrupo == [.lectura: 12, .suelo: 11, .dominio: 4, .decision: 3, .sensible: 1])
        for h in HerramientaDeAsistente.allCases {
            #expect(HerramientaDeAsistente(nombre: h.nombreCompleto) == h)
        }
        for p in perfiles {
            #expect(Set(p.herramientas).count == p.herramientas.count, "\(p.slug) repite herramientas")
            #expect(p.herramientas.contains(.finalizar), "\(p.slug) sin tls_finalizar")
            #expect(p.herramientas.contains(.estado) && p.herramientas.contains(.leer), "\(p.slug) no puede leer")
            for h in p.herramientas {
                switch h.exclusivaDe {
                case "coordinador"?: #expect(p.coordinador, "\(p.slug) no es coordinador y tiene \(h.rawValue)")
                case let s?: #expect(p.slug == s, "\(p.slug) tiene \(h.rawValue), que es de \(s)")
                case nil: break
                }
            }
        }
        // Solo Mika registra decisiones; nadie del sistema pide acciones externas; Equipo no saca nada fuera.
        #expect(perfiles.filter { $0.herramientas.contains(.registrarDecision) }.map(\.slug) == ["mika"])
        #expect(!PerfilDeAsistente.equipo.herramientas.contains(.solicitarAccion))
        #expect(!PerfilDeAsistente.ordenador.herramientas.contains(.solicitarAccion))
        #expect(!PerfilDeAsistente.cartero.herramientas.contains(.solicitarAccion))
        // Quien prepara borradores de algo que sale fuera puede pedir la aprobación (y al revés).
        for p in perfiles where p.herramientas.contains(.solicitarAccion) {
            #expect(p.herramientas.contains(.prepararBorrador), "\(p.slug)")
        }
        // Solo el Ordenador mueve desde el Buzón; solo el Contable propone conciliaciones.
        #expect(perfiles.filter { $0.herramientas.contains(.moverArchivo) }.map(\.slug) == ["ordenador"])
        #expect(perfiles.filter { $0.herramientas.contains(.proponerConciliacion) }.map(\.slug) == ["contable"])
    }

    @Test("Funciones, números y sistemas existen en el estándar y son de su área")
    func estandar() {
        let cat = CatalogoPrograma.deSerie
        for p in perfiles {
            for c in p.capacidades {
                let std = cat.capacidades.first { $0.codigo == c }
                #expect(std != nil, "\(p.slug): no existe la función \(c)")
                if let a = p.area { #expect(std?.area == a, "\(p.slug): \(c) no es de \(a.nombre)") }
            }
            for n in p.numeros { #expect(cat.kpi(n) != nil, "\(p.slug): no existe el número \(n)") }
            for s in p.sistemas {
                let sis = SistemaCatalogo.codigo(s)
                #expect(sis != nil, "\(p.slug): no existe el sistema \(s)")
                #expect(sis?.area == p.area, "\(p.slug): \(s) es de otra área")
            }
        }
        // Las funciones que gobiernan sus herramientas de dominio (las de serie de `TipoDeAccion`).
        #expect(PerfilDeAsistente.comercial.capacidades.contains(TipoDeAccion.oportunidadRegistrar.capacidadPorDefecto!))
        #expect(PerfilDeAsistente.comercial.capacidades.contains(TipoDeAccion.contactoRegistrar.capacidadPorDefecto!))
        #expect(PerfilDeAsistente.marca.capacidades.contains(TipoDeAccion.metricasRegistrar.capacidadPorDefecto!))
        #expect(PerfilDeAsistente.contable.capacidades.contains(TipoDeAccion.cobroExternoRegistrar.capacidadPorDefecto!))
        #expect(PerfilDeAsistente.contable.capacidades.contains(TipoDeAccion.conciliacionProponer.capacidadPorDefecto!))
        #expect(PerfilDeAsistente.mika.capacidades.contains(TipoDeAccion.decisionRegistrar.capacidadPorDefecto!))
        // Marca nunca cualifica contactos (MAR-07) ni publica (MAR-04).
        #expect(!PerfilDeAsistente.marca.capacidades.contains("MAR-07") && !PerfilDeAsistente.marca.capacidades.contains("MAR-04"))
    }

    @Test("Rutinas de serie (PLAN §5.1)")
    func rutinas() throws {
        func r(_ p: PerfilDeAsistente, _ id: String) throws -> TLSAgents.RutinaDeAsistente { try #require(p.rutinas.first { $0.id == id }) }
        let rojo = try r(.mika, "algo-rojo")
        #expect(rojo.nombre == "¿Algo rojo?" && rojo.dias == DiaSemana.laborables && rojo.horaTexto == "08:45" && rojo.soloSiHayRojo)
        let resumen = try r(.mika, "resumen-semana")
        #expect(resumen.dias == [.lunes] && resumen.horaTexto == "08:00" && !resumen.soloSiHayRojo)
        let embudo = try r(.comercial, "repaso-embudo")
        #expect(embudo.dias == [.lunes] && embudo.horaTexto == "10:00")
        let clientes = try r(.implementador, "estado-clientes")
        #expect(clientes.dias == [.viernes] && clientes.horaTexto == "09:00")
        let cobros = try r(.contable, "cobros-pendientes")
        #expect(cobros.diaDelMes == 5 && cobros.horaTexto == "09:00" && cobros.meses.isEmpty)
        let gestoria = try r(.contable, "paquete-gestoria")
        #expect(gestoria.diaDelMes == 1 && gestoria.meses == [1, 4, 7, 10])
        #expect(try r(.marca, "repaso-calendario").dias.count == 1)
        let mes = try r(.equipo, "revision-mensual")
        #expect(mes.diaDelMes == 1 && mes.meses.isEmpty)
        let barrido = try r(.ordenador, "barrido")
        #expect(barrido.dias == DiaSemana.laborables && barrido.horaTexto == "09:00")
        let triaje = try r(.cartero, "triaje")
        #expect(triaje.dias == DiaSemana.laborables && triaje.horaTexto == "08:30")
        // Cada rutina lleva qué hacer (el motor la pone en el primer mensaje) y un id que sirve de nombre de fichero.
        for p in perfiles {
            for x in p.rutinas {
                #expect(!(x.instruccion ?? "").isEmpty, "\(p.slug).\(x.id)")
                #expect(AgentPaths.isSafeName(x.id), "\(p.slug).\(x.id)")
                if let d = x.diaDelMes { #expect((1...28).contains(d)) }
            }
        }
        // El 19/10/2026 (lunes) tocan «¿Algo rojo?», el resumen, el repaso del embudo y el barrido; el viernes 23, el
        // estado de los clientes; el 1 de enero, la gestoría.
        let lunes = try #require(LocalDate(parsing: "2026-10-19"))
        #expect(rojo.toca(lunes) && resumen.toca(lunes) && embudo.toca(lunes) && barrido.toca(lunes))
        let viernes = try #require(LocalDate(parsing: "2026-10-23"))
        let enero = try #require(LocalDate(parsing: "2027-01-01"))
        let noviembre = try #require(LocalDate(parsing: "2026-11-01"))
        #expect(!clientes.toca(lunes) && clientes.toca(viernes))
        #expect(gestoria.toca(enero) && !gestoria.toca(noviembre))
    }

    @Test("Disparadores: seguimientos 7/14/21 y pérdida a los 30, kit 24 h antes y los eventos del dominio")
    func disparadores() {
        let c = PerfilDeAsistente.comercial
        #expect(c.disparadores.filter { $0.tipo == .plazo }.compactMap(\.plazoHoras) == [7 * 24, 14 * 24, 21 * 24, 30 * 24])
        #expect(c.eventos == ["contacto.creado"])
        #expect(PerfilDeAsistente.implementador.disparadores.first { $0.clave == "kit-sesion" }?.plazoHoras == -24)
        #expect(PerfilDeAsistente.implementador.eventos == ["proyecto.creado"])
        #expect(PerfilDeAsistente.contable.eventos == ["extracto.importado"])
        #expect(PerfilDeAsistente.marca.eventos == ["proyecto.cerrado"])
        for p in perfiles {
            for e in p.eventos { #expect(TipoEvento(rawValue: e) != nil, "\(p.slug): evento desconocido \(e)") }
        }
        // Equipo: CRITERIO tras tres aprobaciones iguales.
        #expect(PerfilDeAsistente.equipo.disparadores.contains { $0.clave == "criterio-3" })
    }

    @Test("Activación de serie y topes por defecto")
    func activacionYTopes() {
        #expect(perfiles.map(\.activacion) == [.siempre, .siSuAreaEstaActiva, .siSuAreaEstaActiva, .siSuAreaEstaActiva,
                                               .enReposo, .enReposo, .alConectarMail, .siempre])
        for p in perfiles {
            #expect(p.ajustes.presupuestoEjecucionUSD == 0.5 && p.ajustes.presupuestoMesUSD == 15
                && p.ajustes.maxTareasPorEjecucion == 10, "\(p.slug)")
            #expect(["sonnet", "haiku", "opus"].contains(p.ajustes.modelo) && ["low", "medium", "high"].contains(p.ajustes.esfuerzo))
        }
    }

    @Test("Lo que nunca hacen: la línea roja de la decisión 6, dicha en cada uno")
    func nunca() {
        func dice(_ p: PerfilDeAsistente, _ palabras: String...) -> Bool {
            let t = TextFolding.fold(p.nunca.joined(separator: " "))
            return palabras.allSatisfy { t.contains(TextFolding.fold($0)) }
        }
        #expect(dice(.mika, "decidir", "metas", "fecha límite", "hecha"))
        #expect(dice(.comercial, "enviar", "precio", "ganada"))
        #expect(dice(.implementador, "escribir a un cliente", "publicar", "cerrar un proyecto", "facturar"))
        #expect(dice(.contable, "mover dinero", "emitir", "cobrado", "precios"))
        #expect(dice(.marca, "publicar", "mensajes directos", "inventar cifras"))
        #expect(dice(.equipo, "permisos", "contratar", "evaluar"))
        #expect(dice(.cartero, "responder", "reenviar", "borrar"))
        #expect(dice(.ordenador, "borrar", "privado"))
    }

    @Test("Los textos que se enseñan no usan jerga")
    func glosario() {
        for p in perfiles {
            var textos = [p.nombre, p.descripcion, p.pregunta, p.mision, p.escalado, p.entrega, p.activacion.explicacion]
            textos += p.nunca + p.puedeSolo + p.puedeConTuOK + p.decideSolo + p.alertas.map(\.cuando)
            textos += p.rutinas.map(\.nombre) + p.rutinas.compactMap(\.instruccion) + p.disparadores.flatMap { [$0.instruccion, $0.resumen] }
            textos += p.accionesRapidas.flatMap { [$0.titulo, $0.peticion] }
            for t in textos { #expect(ApoyoRoles.palabrasDeJerga(t).isEmpty, "\(p.slug): «\(t)»") }
        }
    }

    @Test("Lo que consume el motor: CatalogoDeAsistentes con sus instrucciones y menciones")
    func motor() throws {
        let cat = CatalogoAsistentesTLS(carpetaInstrucciones: ApoyoRoles.instrucciones)
        #expect(cat.avisos.isEmpty, "\(cat.avisos)")
        #expect(cat.roles.count == 8)
        let mika = try #require(cat.rol("mika"))
        #expect(mika.coordinador && mika.area == .direccion && mika.preguntaFija == PerfilDeAsistente.mika.pregunta)
        #expect(mika.rutinasDeSerie.map(\.id) == ["algo-rojo", "resumen-semana"])
        #expect(mika.instrucciones.contains("## Qué haces"))
        #expect(mika.identidad?.hasPrefix("Eres Mika") == true)
        #expect(cat.slug(deMencion: "@Comercial") == "comercial")
        #expect(cat.slug(deMencion: "@agente:contable") == "contable")
        #expect(cat.atienden(evento: "extracto.importado").map(\.slug) == ["contable"])
        #expect(cat.rol("contable")?.instruccionesPorEvento["extracto.importado"]?.isEmpty == false)
        #expect(cat.nombreVisible("comercial") == "Comercial (asistente)")
        #expect(cat.perfil("agente:marca")?.slug == "marca")
        #expect(cat.perfiles(de: .finanzas).map(\.slug) == ["contable"])
        // Sin carpeta, las de reserva tienen las cuatro secciones (nunca se lanza un asistente sin instrucciones).
        let reserva = CatalogoAsistentesTLS.soloPerfiles
        #expect(reserva.avisos.count == 8)
        for r in reserva.roles {
            for s in CatalogoAsistentesTLS.secciones { #expect(r.instrucciones.contains("## \(s)"), "\(r.slug)") }
        }
    }

    @Test("El brief del motor lleva las instrucciones de rol, la pregunta fija y lo que nunca hace")
    func brief() throws {
        let cat = CatalogoAsistentesTLS(carpetaInstrucciones: ApoyoRoles.instrucciones)
        let rol = try #require(cat.rol("comercial"))
        let ajustes = AjustesDeAsistente(slug: "comercial", activo: true, areas: [.ventas], leeAreas: [.marca, .finanzas])
        let b = BriefBuilder(empresa: "Asesoría Ribera").construir(rol: rol, ajustes: ajustes, sistemas: ["Embudo"])
        #expect(b.texto.contains(PerfilDeAsistente.comercial.pregunta))
        #expect(b.texto.contains("## Qué no haces nunca"))
        #expect(b.texto.contains("tls_solicitar_accion"))
        for n in PerfilDeAsistente.comercial.nunca { #expect(b.texto.contains(n)) }
    }
}
