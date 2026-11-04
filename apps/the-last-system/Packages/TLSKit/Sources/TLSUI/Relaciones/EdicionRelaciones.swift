import Foundation
import TLSCore
import TLSDesign

/// Un cambio de relación que espera tu OK: enseña la línea antes y después (§5.3) y, si toca, ofrece
/// cambiarlo también en lo que cuelga (§5.4).
struct ConfirmacionRelacion: Identifiable {
    let id = UUID()
    let preparada: RelacionPreparada
    /// «Jorge Martín es de Talleres Martín e Hijos SL. ¿Pasarlo a Arquitectura Nexo SLP?».
    let pregunta: String
    /// La ficha en la que se escribe.
    let fichero: VaultPath
    /// Lo que cuelga y se puede cambiar a la vez.
    let colgantes: [VaultPath]
    /// Lo que cuelga y no se cambia (facturas emitidas).
    let fijas: [VaultPath]
    var tambienColgantes: Bool = true
}

/// Qué abre el selector de relación (§5.2).
struct PeticionSelector: Identifiable {
    enum Modo: Hashable {
        /// Esta ficha guarda la propiedad: se elige a qué apunta.
        case directo(dueno: VaultPath, propiedad: String)
        /// «Añadir existente…»: se elige la ficha que guardará la relación apuntando a `destino`.
        case inverso(destino: VaultPath)
    }

    let id = UUID()
    let modo: Modo
    /// «Empresa de Jorge Martín», «Añadir a Jorge Martín a una reunión».
    let titulo: String
    let placeholder: String
    /// Tipos de ficha que se pueden elegir.
    let tipos: Set<NoteKind>
    /// Elegir varias (personas, bloqueada por).
    let varias: Bool
    /// Las del contexto, primero (en una reunión de Arquitectura Nexo, sus personas).
    let contexto: [VaultPath]
    /// Las que ya están enlazadas (marcadas).
    let enlazadas: Set<VaultPath>
    /// Dónde se guarda, en palabras.
    let nota: String
    /// «Quitar la empresa» (solo si se puede quitar).
    let quitar: String?
    /// Tipo y plantilla para «Crear … como … nueva» (nil = no se ofrece).
    let crear: (tipo: NoteKind, plantilla: String, nombre: String)?
    /// Desde dónde se abrió (el selector sale junto a ese control): «chips», «inspector», «panel».
    var origen: String = "chips"
}

/// Lo que hace la interfaz con las relaciones: prepara con `EditorDeRelaciones`, pide confirmación cuando
/// cambia algo que ya existía y escribe con `VaultSession.escribir` (una línea, con «Deshacer»).
@MainActor
enum EdicionRelaciones {
    /// Plantilla con la que se crea al vuelo una ficha de ese tipo desde el selector (solo las que se crean
    /// con su nombre; el resto se crea desde su base o con «Nuevo»).
    static func plantillaAlVuelo(_ tipo: NoteKind) -> (plantilla: String, nombre: String)? {
        switch tipo {
        case .organization: ("empresa", "empresa nueva")
        case .contact: ("contacto", "contacto nuevo")
        case .service: ("servicio", "servicio nuevo")
        case .role: ("rol", "rol nuevo")
        case .connection: ("conexion", "conexión nueva")
        default: nil
        }
    }

    /// Prepara un cambio; si no hace falta confirmar, lo escribe. Si hace falta, devuelve la confirmación.
    @discardableResult
    static func hacer(_ cambio: CambioDeRelacion, sesion: VaultSession, almacen: AlmacenRelaciones,
                      navegar: NavegarAccion? = nil) async -> ConfirmacionRelacion? {
        guard comprobarEscritura(sesion) else { return nil }
        await almacen.actualizar()
        guard let editor = almacen.editor, let grafo = almacen.grafo else { return nil }
        do {
            let p = try editor.preparar(cambio)
            if p.sinCambios { return nil }
            var colgantes: (cambiables: [VaultPath], fijas: [VaultPath]) = ([], [])
            if case .poner = cambio.accion, ["empresa", "contacto"].contains(cambio.propiedad) {
                let viejo = grafo.destinos(de: cambio.dueno, propiedad: cambio.propiedad).first
                colgantes = editor.colgantes(de: cambio.dueno, propiedad: cambio.propiedad, viejo: viejo)
            }
            if p.pideConfirmacion || !colgantes.cambiables.isEmpty {
                return ConfirmacionRelacion(preparada: p, pregunta: pregunta(p, grafo: grafo), fichero: cambio.dueno,
                                            colgantes: colgantes.cambiables, fijas: colgantes.fijas)
            }
            try await sesion.escribir(p.comando, aviso: p.aviso)
            almacen.invalidar()
        } catch let ProblemaDeRelacion.unica(existente, mensaje) {
            sesion.aviso = Aviso(mensaje, estado: .atencion, tituloAccion: "Abrirlo") {
                if let navegar { navegar(.ficha(existente), modo: .entrar) } else { sesion.navegar(a: .ficha(existente), modo: .entrar) }
            }
        } catch let problema as ProblemaDeRelacion {
            sesion.aviso = Aviso(problema.localizedDescription, estado: .atencion)
        } catch {
            // `escribir` ya avisó del error.
        }
        return nil
    }

    /// «Cambiar» en la confirmación.
    static func confirmar(_ c: ConfirmacionRelacion, sesion: VaultSession, almacen: AlmacenRelaciones) async {
        guard comprobarEscritura(sesion), let editor = almacen.editor else { return }
        do {
            if c.tambienColgantes, !c.colgantes.isEmpty {
                let plan = try editor.enCadena(c.preparada, colgantes: c.colgantes, autor: sesion.autor)
                try await sesion.escribir(plan: plan, aviso: plan.descripcion)
            } else {
                try await sesion.escribir(c.preparada.comando, aviso: c.preparada.aviso)
            }
            almacen.invalidar()
        } catch let problema as ProblemaDeRelacion {
            sesion.aviso = Aviso(problema.localizedDescription, estado: .atencion)
        } catch {}
    }

    /// Crea la ficha con su plantilla y la enlaza, en un solo paso de deshacer (§5.2, §7.6).
    static func crearYEnlazar(nombre: String, tipo: NoteKind, dueno: VaultPath, propiedad: String,
                              sesion: VaultSession, almacen: AlmacenRelaciones) async {
        guard comprobarEscritura(sesion) else { return }
        let limpio = nombre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty, let plantilla = plantillaAlVuelo(tipo)?.plantilla else { return }
        await almacen.actualizar()
        guard let foto = almacen.foto, let editor = almacen.editor else { return }
        do {
            let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: sesion.persona))
            let nota = try motor.preparar(PlantillaMotor.Peticion(plantilla: plantilla, valores: ["titulo": limpio], autor: sesion.autor))
            let plan = try editor.crearYEnlazar(nota, nombre: limpio, dueno: dueno, propiedad: propiedad, autor: sesion.autor)
            let destino = almacen.grafo?.ficha(dueno)?.nombre ?? dueno.stem
            try await sesion.escribir(plan: plan, aviso: "Creé «\(limpio)» y la enlacé a \(destino)")
            almacen.invalidar()
        } catch let e as PlantillaError {
            sesion.aviso = Aviso(e.localizedDescription, estado: .atencion)
        } catch let problema as ProblemaDeRelacion {
            sesion.aviso = Aviso(problema.localizedDescription, estado: .atencion)
        } catch {}
    }

    /// En solo lectura no se escribe: se avisa con el motivo.
    static func comprobarEscritura(_ sesion: VaultSession) -> Bool {
        if sesion.puedeEscribir { return true }
        sesion.aviso = Aviso("No se puede cambiar: \(motivoSoloLectura(sesion) ?? "esta carpeta está en solo lectura").",
                             estado: .atencion)
        return false
    }

    /// Por qué no se puede escribir ahora (para enseñarlo al lado de los controles desactivados).
    static func motivoSoloLectura(_ sesion: VaultSession) -> String? {
        switch sesion.modoEscritura {
        case .escribe: nil
        case .abriendo: "aún se está abriendo"
        case .soloLectura(let m): m.texto
        }
    }

    static func pregunta(_ p: RelacionPreparada, grafo: GrafoRelaciones) -> String {
        let dueno = grafo.ficha(p.cambio.dueno)?.nombre ?? p.cambio.dueno.stem
        let actual = grafo.destinos(de: p.cambio.dueno, propiedad: p.cambio.propiedad).first.flatMap { grafo.ficha($0)?.nombre }
        let def = grafo.ficha(p.cambio.dueno).flatMap { EsquemaRelaciones.definicion(tipo: $0.tipo, propiedad: p.cambio.propiedad) }
        let etiqueta = (def?.etiqueta ?? p.cambio.propiedad).lowercased()
        switch p.cambio.accion {
        case .poner(let d), .anadir(let d):
            let nuevo = grafo.ficha(d)?.nombre ?? d.stem
            if let actual { return "\(FormatoFicha.capital(etiqueta)) de \(dueno): \(actual). ¿Pasarlo a \(nuevo)?" }
            return "¿Enlazar \(dueno) a \(nuevo)?"
        case .quitar:
            return "¿Quitar \(etiqueta) de \(dueno)?"
        case .reordenar:
            return "¿Cambiar el orden de \(etiqueta) en \(dueno)?"
        }
    }

    /// Texto de contexto de una ficha en el selector y las listas («Cliente · Activo», «Aceptada · 150 €»).
    static func contexto(_ f: FichaGrafo, grafo: GrafoRelaciones, hoy: LocalDate) -> String {
        var partes: [String] = []
        switch f.tipo {
        case .organization:
            if let r = f.texto("relacion") { partes.append(FormatoFicha.capital(r)) }
        case .contact:
            if let e = grafo.destinos(de: f.ruta, propiedad: "empresa").first.flatMap(grafo.ficha) { partes.append(e.nombre) }
            else { partes.append("Particular") }
        case .opportunity:
            if let v = FormatoFicha.euros(f.texto("valor")) { partes.append(v) }
        case .project, .task:
            if let e = grafo.destinos(de: f.ruta, propiedad: "empresa").first.flatMap(grafo.ficha) { partes.append(e.nombre) }
            if let n = f.numero { partes.insert(n, at: 0) }
        case .meeting:
            if let d = f.texto("fecha").flatMap({ LocalDate(parsing: $0) }) { partes.append(FormatoFicha.fechaConDia(d, hoy: hoy)) }
        case .invoice:
            if let n = f.numero { partes.append(n) }
            if let t = FormatoFicha.euros(f.texto("total")) { partes.append(t) }
        case .service:
            if let p = FormatoFicha.euros(f.texto("precio")) { partes.append(p) }
        default:
            break
        }
        if let e = f.estado { partes.append(FormatoFicha.capital(e)) }
        return partes.joined(separator: " · ")
    }
}
