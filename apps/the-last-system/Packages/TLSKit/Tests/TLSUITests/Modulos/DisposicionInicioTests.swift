import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Módulos de inicio (DISENO §6, M2-Hoy): se mueven, se ocultan y se recuperan, cambian de tamaño, 8 como mucho, y se
/// guardan por empresa fuera de la carpeta.
@Suite("Módulos de inicio · mover, ocultar, recuperar y guardar")
@MainActor
struct DisposicionInicioTests {
    @Test("Hoy sale como en M2-Hoy: caja y ritmo grandes, tu semana ancha, lo que cabe hoy mediano y dos pequeños")
    func deSerieHoy() {
        let d = CatalogoModulos.deSerie(.hoy)
        #expect(d.visibles.map(\.modulo) == [.caja, .ritmo, .semana, .cabe, .cobros, .quietas])
        #expect(d.visibles.map(\.tamano) == [.grande, .grande, .ancho, .mediano, .pequeno, .pequeno])
        #expect(d.ocultos.isEmpty)
        // Caben en la rejilla de 4 columnas sin solaparse.
        let celdas = MosaicoLayout.colocar(d.visibles.map(\.tamano), columnas: 4)
        #expect(celdas.count == 6)
        #expect(celdas.map(\.fila).max() == 3)
    }

    @Test("Cada inicio de área sale con lo de SISTEMAS §4.2, 8 como mucho y solo módulos que su galería ofrece")
    func deSerieAreas() {
        for a in AreaCode.allCases {
            let d = CatalogoModulos.deSerie(.area(a))
            #expect(!d.visibles.isEmpty)
            #expect(d.visibles.count <= DisposicionInicio.maximo)
            let ofrecidos = Set(CatalogoModulos.disponibles(en: .area(a)))
            for c in d.visibles {
                #expect(ofrecidos.contains(c.modulo), "\(c.modulo) no está en la galería de \(a)")
                #expect(CatalogoModulos.definicion(c.modulo).tamanos.contains(c.tamano))
            }
        }
        #expect(CatalogoModulos.deSerie(.area(.finanzas)).visibles.first?.modulo == .caja)
        #expect(CatalogoModulos.deSerie(.area(.direccion)).visibles.map(\.modulo).contains(.cuello))
    }

    @Test("Ocultar conserva tamaño y sitio; «Mostrar» lo devuelve donde estaba")
    func ocultarYMostrar() {
        var d = CatalogoModulos.deSerie(.hoy)
        #expect(d.siguienteTamano(.ritmo) == .mediano)
        #expect(d.ocultar(.ritmo) == true)
        #expect(!d.visibles.contains { $0.modulo == .ritmo })
        #expect(d.ocultos.map(\.modulo) == [.ritmo])
        #expect(d.ocultos.first?.tamano == .mediano)
        #expect(d.ocultar(.ritmo) == false, "Ya estaba oculto")
        #expect(d.mostrar(.ritmo) == true)
        #expect(d.indice(.ritmo) == 1)
        #expect(d.visibles[1].tamano == .mediano)
        #expect(d.ocultos.isEmpty)
        // «Añadir» un módulo oculto es mostrarlo.
        d.ocultar(.cobros)
        #expect(d.anadir(.cobros) == true)
        #expect(d.indice(.cobros) == 4)
    }

    @Test("Como mucho 8 a la vista: el noveno no entra y «Mostrar» espera a que ocultes otro")
    func maximoOcho() {
        var d = CatalogoModulos.deSerie(.hoy)
        #expect(d.ocultar(.quietas) == true)
        #expect(d.anadir(.sesiones) == true)
        #expect(d.anadir(.trimestre) == true)
        #expect(d.anadir(.embudo) == true)
        #expect(d.visibles.count == 8)
        #expect(d.lleno)
        #expect(d.anadir(.pendientes) == false)
        #expect(d.mostrar(.quietas) == false)
        #expect(d.ocultar(.embudo) == true)
        #expect(d.mostrar(.quietas) == true)
        #expect(d.visibles.count == 8)
        #expect(d.anadir(.caja) == false, "Ya está a la vista")
    }

    @Test("Mover antes y después, y soltar en el sitio de otro (arrastrar)")
    func mover() {
        var d = CatalogoModulos.deSerie(.hoy)
        #expect(d.mover(.caja, -1) == false, "Ya es el primero")
        #expect(d.mover(.quietas, 1) == false, "Ya es el último")
        #expect(d.mover(.caja, 1) == true)
        #expect(d.visibles.map(\.modulo).prefix(2) == [.ritmo, .caja])
        #expect(d.mover(.quietas, aLaPosicionDe: .ritmo) == true)
        #expect(d.visibles.map(\.modulo) == [.quietas, .ritmo, .caja, .semana, .cabe, .cobros])
        #expect(d.mover(.quietas, aLaPosicionDe: .cobros) == true)
        #expect(d.visibles.map(\.modulo) == [.ritmo, .caja, .semana, .cabe, .cobros, .quietas])
        #expect(d.mover(.caja, aLaPosicionDe: .caja) == false)
        #expect(d.mover(.sesiones, aLaPosicionDe: .caja) == false, "No está a la vista")
    }

    @Test("Los tamaños dan la vuelta por los que admite cada módulo")
    func tamanos() {
        var d = CatalogoModulos.deSerie(.hoy)
        #expect(d.siguienteTamano(.caja) == .mediano)
        #expect(d.siguienteTamano(.caja) == .ancho)
        #expect(d.siguienteTamano(.caja) == .grande)
        #expect(d.siguienteTamano(.semana) == .grande)
        #expect(d.siguienteTamano(.semana) == .ancho)
        #expect(d.siguienteTamano(.cobros) == .mediano)
        #expect(d.siguienteTamano(.cobros) == .pequeno)
        #expect(d.siguienteTamano(.sesiones) == nil, "No está a la vista")
    }

    @Test("La galería ofrece lo que no está ni a la vista ni oculto")
    func galeria() {
        var d = CatalogoModulos.deSerie(.hoy)
        let antes = d.paraAnadir(.hoy)
        #expect(!antes.contains(.caja))
        #expect(antes.contains(.sesiones))
        d.ocultar(.caja)
        #expect(!d.paraAnadir(.hoy).contains(.caja), "Oculto: se recupera con «Mostrar»")
        #expect(d.anadir(.sesiones) == true)
        #expect(!d.paraAnadir(.hoy).contains(.sesiones))
    }

    @Test("Se guarda en «inicios.json» del estado; lo que ya no existe se quita y un tamaño que no vale se corrige")
    func guardar() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tls-inicios-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let archivo = dir.appendingPathComponent("inicios.json")
        let a = AlmacenInicios(archivo: archivo)
        #expect(a.disposicion(.hoy) == CatalogoModulos.deSerie(.hoy))
        #expect(a.cambiar(.hoy) { $0.ocultar(.caja) })
        #expect(a.cambiar(.area(.ventas)) { $0.mover(.embudo, -1) })
        #expect(!a.cambiar(.hoy) { $0.ocultar(.caja) }, "Sin cambio no se guarda")
        let b = AlmacenInicios(archivo: archivo)
        #expect(b.disposicion(.hoy) == a.disposicion(.hoy))
        #expect(b.disposicion(.area(.ventas)).visibles.first?.modulo == .embudo)
        #expect(b.disposicion(.hoy).ocultos.map(\.modulo) == [.caja])

        // Un módulo que ya no existe y un tamaño que el módulo no admite.
        let json = """
        {"version":1,"inicios":{"hoy":{"visibles":[{"id":"modulo-retirado","tamano":"grande"},{"id":"cobros","tamano":"ancho"},{"id":"caja","tamano":"grande"}],"ocultos":[]}}}
        """
        try Data(json.utf8).write(to: archivo)
        let c = AlmacenInicios(archivo: archivo)
        #expect(c.disposicion(.hoy).visibles == [ModuloColocado(.cobros, .pequeno), ModuloColocado(.caja, .grande)])
        // Un fichero roto: lo de serie.
        try Data("{roto".utf8).write(to: archivo)
        #expect(AlmacenInicios(archivo: archivo).disposicion(.hoy) == CatalogoModulos.deSerie(.hoy))
    }

    @Test("Los textos de los módulos y la galería no usan jerga")
    func glosario() {
        for m in ModuloID.allCases {
            let d = CatalogoModulos.definicion(m)
            #expect(GlosarioTests.jerga(d.titulo + " " + d.descripcion).isEmpty, "\(m)")
        }
    }
}
