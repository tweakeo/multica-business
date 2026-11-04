import AppKit
import Foundation
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes. Escribir la configuración de los asistentes desde la interfaz (PLAN §4.5): el interruptor
// general, la pausa por área y lo que cambia la ficha de un asistente. Siempre como la persona, por `CommandBus`, con
// el aviso «… · Deshacer» y ⌘Z. Lo que la app escribe en `config.yaml` queda confirmado (lo hace el bus); al deshacerlo
// se vuelve a confirmar lo que queda, para que no parezca un cambio hecho fuera de la app (ver «Cambios pedidos ›
// asistentes» en docs/F4-CONTRATOS.md).

@MainActor
enum EscrituraAsistentes {
    nonisolated static let ruta = EditorConfigAgentes.ruta

    /// El texto y los bytes de la configuración (sin descargar de iCloud ni seguir enlaces). `nil` si no existe.
    nonisolated static func leerConfig(_ root: URL) -> (texto: String, datos: Data)? {
        guard let texto = AjustesBases.leerTexto(ruta, root: root),
              let datos = try? Data(contentsOf: ruta.url(in: root), options: [.uncached]) else { return nil }
        return (texto.hasPrefix("\u{FEFF}") ? String(texto.dropFirst()) : texto, datos)
    }

    /// ¿Hay cambios de permisos hechos fuera de la app sin confirmar? Mientras los haya, la ficha no escribe: el
    /// gobierno no sabría qué confirmar.
    static func cambiosDeFuera(_ sesion: VaultSession) -> Bool {
        sesion.bus?.autorizador?.estadoDeConfig().cambiadaFuera ?? false
    }

    // MARK: Interruptor y pausa por área

    /// Enciende o apaga a todos los asistentes (DIR-11). Con el gobierno: `EditorConfigAgentes.aplicar`, que confirma
    /// solo este cambio aunque haya otros de fuera esperando.
    static func ponerInterruptor(_ encendido: Bool, sesion: VaultSession) async throws {
        let bus = try sesion.busParaEscribir()
        let reconfirmar = !cambiosDeFuera(sesion)
        let r = try await EditorConfigAgentes.aplicar(.interruptor(encendido ? .encendido : .apagado), bus: bus, autor: sesion.autor)
        let aviso = encendido ? "Asistentes encendidos: vuelven a trabajar" : "Asistentes en pausa: no harán nada hasta que los enciendas"
        registrar(r, sesion: sesion, descripcion: encendido ? "Encender los asistentes" : "Apagar los asistentes",
                  aviso: aviso, reconfirmar: reconfirmar)
        TutorialEventos.registrar(encendido ? .asistentesReanudados : .asistentesPausados, empresa: sesion.entry.id)
        await RegistroDeAsistentes.compartido.conexion(de: sesion)?.ajustesCambiaron(interruptorApagado: !encendido)
    }

    /// Pone o quita un área de `pausa_areas`.
    static func pausar(_ area: AreaCode, _ enPausa: Bool, actuales: Set<AreaCode>, sesion: VaultSession) async throws {
        let bus = try sesion.busParaEscribir()
        var nuevas = actuales
        if enPausa { nuevas.insert(area) } else { nuevas.remove(area) }
        let orden = AreaCode.allCases.filter { nuevas.contains($0) }
        let reconfirmar = !cambiosDeFuera(sesion)
        let r = try await EditorConfigAgentes.aplicar(.pausaAreas(orden), bus: bus, autor: sesion.autor)
        let aviso = enPausa ? "\(area.etiquetaNumerada) en pausa para los asistentes" : "Los asistentes vuelven a trabajar en \(area.etiquetaNumerada)"
        registrar(r, sesion: sesion, descripcion: "Pausar áreas para los asistentes",
                  aviso: aviso, reconfirmar: reconfirmar)
        await RegistroDeAsistentes.compartido.conexion(de: sesion)?.ajustesCambiaron(interruptorApagado: false)
    }

    // MARK: La ficha de un asistente

    /// El texto que quedaría con estos cambios (para la vista previa). Lanza si no se puede sin tocar lo demás.
    static func vistaPrevia(_ cambios: [CambioDeAsistente], slug: String, perfil: PerfilDeAsistente?, root: URL) throws -> (antes: String, despues: String) {
        let antes = leerConfig(root)?.texto ?? ""
        return (antes, try EdicionConfigAsistentes.texto(cambios, slug: slug, perfil: perfil, en: antes))
    }

    /// Guarda los cambios de un asistente en un solo paso que se deshace.
    @discardableResult
    static func guardar(_ cambios: [CambioDeAsistente], slug: String, nombre: String, perfil: PerfilDeAsistente?,
                        sesion: VaultSession) async throws -> WriteResult {
        let bus = try sesion.busParaEscribir()
        guard let root = sesion.root else { throw WriteError.soloLectura }
        guard !cambiosDeFuera(sesion) else {
            throw ErrorDeGobierno.sinPermiso("Cambiaron los permisos de los asistentes fuera de la app. Confírmalos o vuelve a los de antes en Decisiones antes de cambiar nada aquí.")
        }
        let actual = leerConfig(root)
        let nuevo = try EdicionConfigAsistentes.texto(cambios, slug: slug, perfil: perfil, en: actual?.texto ?? "")
        let op: WriteOp
        if let actual {
            guard let o = WriteOp.replaceText(ruta, base: actual.datos, text: nuevo) else { throw ErrorEdicionConfig.noCuadra }
            op = o
        } else {
            op = .create(ruta, text: nuevo)
        }
        let descripcion = "Ajustes de \(nombre) (asistente)"
        let r = try await bus.ejecutar(WritePlan(autor: sesion.autor, descripcion: descripcion, ops: [op]))
        registrar(r, sesion: sesion, descripcion: descripcion, aviso: "Guardé los ajustes de \(nombre)", reconfirmar: true)
        let apaga = cambios.contains { if case .activo(false) = $0 { true } else { false } }
        await RegistroDeAsistentes.compartido.conexion(de: sesion)?.ajustesCambiaron(interruptorApagado: apaga)
        return r
    }

    // MARK: Deshacer

    /// Deja el cambio en Deshacer (⌘Z de la pestaña con el foco y el botón del aviso).
    static func registrar(_ r: WriteResult, sesion: VaultSession, descripcion: String, aviso: String, reconfirmar: Bool) {
        guard case .hecho = r.estado else {
            sesion.despuesDeEscribir(r, descripcion: descripcion, aviso: aviso, deshacer: nil)
            return
        }
        let plan = r.planID
        let hacer: @MainActor () -> Void = { [weak sesion] in
            guard let sesion else { return }
            Task { @MainActor in await deshacer(plan: plan, sesion: sesion, reconfirmar: reconfirmar) }
        }
        if let manager = sesion.undoManagerActivo {
            manager.registerUndo(withTarget: sesion) { _ in MainActor.assumeIsolated { hacer() } }
            manager.setActionName(descripcion)
        }
        sesion.aviso = Aviso(aviso) { hacer() }
    }

    /// Deshace un cambio de la configuración y, si era el último, vuelve a confirmar lo que queda.
    static func deshacer(plan: UUID, sesion: VaultSession, reconfirmar: Bool) async {
        let esElUltimo = await sesion.bus?.ultimoDeshacible()?.planID == plan
        await sesion.deshacer(plan: plan)
        guard esElUltimo, let bus = sesion.bus, await bus.ultimoDeshacible()?.planID != plan else { return }
        if reconfirmar, let g = bus.autorizador { _ = try? g.config.confirmar(por: sesion.autor) }
        let apagado = !((bus.autorizador?.estadoDeConfig().efectiva.encendido) ?? true)
        await RegistroDeAsistentes.compartido.conexion(de: sesion)?.ajustesCambiaron(interruptorApagado: apagado)
    }
}
