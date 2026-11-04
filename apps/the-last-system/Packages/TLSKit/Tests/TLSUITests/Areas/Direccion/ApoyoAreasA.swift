import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Apoyo de las pruebas del rol areas-a (Operación de Dirección, Ventas y Entrega): copia de Ribera en una carpeta
/// temporal propia y, solo en esa copia, proyectos internos de varias áreas, dos expedientes de cliente (uno con su
/// portal, sus incidencias, sus tareas y sus materiales) y lo privado con nombres neutros. Nunca toca el ejemplo del
/// repositorio.
@MainActor
enum ApoyoAreasA {
    static let hoy = LocalDate(year: 2026, month: 10, day: 19)!   // lunes (el `hoy:` de Ribera)
    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    static let talleres = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md")
    static let portalTalleres = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Portal.md")
    static let incidenciasTalleres = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Incidencias.md")
    static let clinica = VaultPath("3 · Entrega/Proyectos/clinica-dental-sonrisa-trimestrales/Proyecto.md")
    static let manual = VaultPath("6 · Equipo/Proyectos/manual-del-implementador/Proyecto.md")
    static let guion = VaultPath("2 · Ventas/Proyectos/guion-de-seguimiento/Proyecto.md")
    static let privadoInterno = VaultPath("4 · Finanzas/Trámites/Expediente privado/Proyecto.md")
    static let privadoEntrega = VaultPath("3 · Entrega/Proyectos/expediente-reservado/Proyecto.md")

    /// Un instante en Madrid.
    static func instante(_ d: Int, _ h: Int, _ m: Int = 0, mes: Int = 10) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = mes; c.day = d; c.hour = h; c.minute = m
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        return cal.date(from: c)!
    }

    static func ribera() throws -> (base: URL, carpeta: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-areas-a-\(UUID().uuidString)", isDirectory: true)
        let carpeta = base.appendingPathComponent("Ribera", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: SesionEscrituraTests.ribera, to: carpeta)
        return (base, carpeta)
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

    static func foto(_ carpeta: URL) -> VaultSnapshot {
        VaultSnapshot.read(root: carpeta, layout: VaultLayout.load(root: carpeta).layout)
    }

    static func texto(_ ruta: VaultPath, en carpeta: URL) throws -> String {
        try String(contentsOf: ruta.url(in: carpeta), encoding: .utf8)
    }

    /// Las líneas que cambian entre dos textos con el mismo número de líneas.
    static func lineasCambiadas(_ antes: String, _ despues: String) -> [String] {
        let a = antes.components(separatedBy: "\n"), d = despues.components(separatedBy: "\n")
        guard a.count == d.count else { return ["(cambia el número de líneas: \(a.count) → \(d.count))"] }
        return zip(a, d).filter { $0 != $1 }.map(\.1)
    }

    static func proyecto(_ nombre: String, clase: String, estado: String, extra: String = "") -> String {
        """
        ---
        tls_type: project
        tls_schema: 1
        id: \(UUID().uuidString.lowercased())
        nombre: \(nombre)
        clase: \(clase)
        estado: \(estado)
        \(extra)---
        # \(nombre)
        > \(estado)

        ## Resultado prometido

        """
    }

    /// Prepara la copia: proyectos internos, expedientes, portal, incidencias, materiales, lo privado y una propuesta
    /// enviada hace 7 días (para que toque un seguimiento hoy).
    static func preparar(_ carpeta: URL) throws {
        try cambiar(".tls/config.yaml", en: carpeta, "privado: []",
                    por: "privado: [\"4 · Finanzas/Trámites/Expediente privado\", \"3 · Entrega/Proyectos/expediente-reservado\"]")
        // Internos.
        try escribir(proyecto("Guion de seguimiento", clase: "interno", estado: "En curso",
                              extra: "objetivo: \"[[6-000-de-ventas-cobradas-al-mes|6.000 € de ventas cobradas al mes]]\"\ninicio: 2026-10-12\nfin: 2026-11-06\n"),
                     guion.raw, en: carpeta)
        try escribir(proyecto("Casos de éxito", clase: "interno", estado: "En curso",
                              extra: "objetivo: \"[[8-conversaciones-cualificadas-al-mes|8 conversaciones cualificadas al mes]]\"\ninicio: 2026-10-19\nfin: 2026-11-27\n"),
                     "5 · Marca/Proyectos/casos-de-exito/Proyecto.md", en: carpeta)
        try escribir(proyecto("Manual del implementador", clase: "interno", estado: "En curso",
                              extra: "inicio: 2026-10-05\nfin: 2026-10-30\n"),
                     manual.raw, en: carpeta)
        try escribir(proyecto("Cierre trimestral T3", clase: "interno", estado: "Sin empezar",
                              extra: "objetivo: \"[[trimestrales-t3-de-todos-los-clientes-presentados-antes-del|Trimestrales T3]]\"\ninicio: 2026-10-26\nfin: 2026-11-13\n"),
                     "4 · Finanzas/Proyectos/cierre-trimestral-t3/Proyecto.md", en: carpeta)
        try escribir(proyecto("Rumbo 2027", clase: "interno", estado: "Sin empezar"), "1 · Dirección/Proyectos/rumbo-2027/Proyecto.md", en: carpeta)
        try escribir(proyecto("Proyecto reservado", clase: "interno", estado: "En curso", extra: "inicio: 2026-10-19\nfin: 2026-10-30\n"),
                     privadoInterno.raw, en: carpeta)
        // Expedientes de cliente.
        try escribir(proyecto("Talleres Martín · Trimestrales 2026", clase: "entrega", estado: "En curso", extra: """
            fase: Recogida
            empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
            contacto: "[[jorge-martin|Jorge Martín]]"
            oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
            responsable: Manu
            inicio: 2026-10-19
            fin: 2027-01-29
            sesiones_incluidas: 4

            """), talleres.raw, en: carpeta)
        try escribir("""
            ---
            tls_type: portal
            tls_schema: 1
            id: 5b0c8f6e-6a43-4d55-9d0e-1f5d8c1a0a01
            proyecto: "[[3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto|Talleres Martín · Trimestrales 2026]]"
            empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
            estado: Publicado
            ---
            # Portal de Talleres Martín e Hijos SL
            > Publicado · 1 de 4 sesiones · Trimestrales 2026

            ## Viaje
            | Sesión | Estado | Fecha | Resumen para el cliente | Nota interna |
            |---|---|---|---|---|
            | S1 · Arranque | Hecha | 2026-10-19 | Repasamos qué documentos necesitamos y cómo nos los envías. | Jorge prefiere que le escribamos a jorge@talleresmartin.example por la tarde. |
            | S2 · Revisión de gastos | Kit listo | 2026-10-23 | Revisaremos juntos los gastos del trimestre. Kit preparado en Materiales. | Ojo con las dietas de julio: faltan dos tiques. |
            | S3 · Modelos del trimestre | Programada | 2026-11-04 | Te enseñamos los borradores del 303 y el 111. | Preparar el resumen del banco antes. |
            | S4 · Cierre del año | Pendiente | | | |
            | S5 · Renta | No incluida | | | No contratada este año. |

            > Guía: una fila por sesión del plan. El cliente nunca ve la columna «Nota interna».

            ## Tareas del cliente
            - [x] Enviar las facturas emitidas de julio a septiembre · S1 · vence 2026-10-16
            - [ ] Enviar los extractos del banco del trimestre · S2 · vence 2026-10-22
            - [ ] Firmar la autorización para presentar en tu nombre · S3 · vence 2026-11-03

            ## Documentos
            - [Guía para enviar facturas](Materiales/guia-para-enviar-facturas.md)
            - [Kit de la sesión 2](Materiales/kit-s2-gastos.md)

            ## Dudas y problemas
            - 2026-10-19 · ¿Las dietas de julio entran en este trimestre?

            """, portalTalleres.raw, en: carpeta)
        try escribir("""
            ---
            tls_type: log
            tls_schema: 1
            id: 0e7b6f7c-2f8a-4b1e-a3f6-0d2c9a1b7e11
            registro: incidencias
            proyecto: "[[3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto|Talleres Martín · Trimestrales 2026]]"
            ---
            # Incidencias · Talleres Martín · Trimestrales 2026
            > Plazo de respuesta: grave, 24 h hábiles · media, 48 h · leve, 72 h. Solo se añaden filas.

            | ID | Fecha | Quién reporta | Email | Tipo | Severidad | Estado | Descripción | Responsable | Resolución |
            |---|---|---|---|---|---|---|---|---|---|
            | INC-001 | 2026-10-16 10:00 | Jorge Martín | jorge@talleresmartin.example | Accesos | Grave | Recibida | No puede entrar en la carpeta compartida de facturas. | Manu | Revisar los permisos de la carpeta con soporte. |
            | INC-002 | 2026-10-13 09:00 | Jorge Martín | jorge@talleresmartin.example | Negocio | Leve | Resuelta | Duda sobre el calendario de pagos. | Manu | Explicado por teléfono el mismo día. |

            """, incidenciasTalleres.raw, en: carpeta)
        try escribir("# Guía para enviar facturas\n\nUna carpeta por trimestre.\n",
                     "3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Materiales/guia-para-enviar-facturas.md", en: carpeta)
        try escribir("# Kit de la sesión 2\n\n- Resumen de gastos\n",
                     "3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Materiales/kit-s2-gastos.md", en: carpeta)
        try escribir("documento;estado\nfacturas julio;recibido\n",
                     "3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Materiales/inventario.csv", en: carpeta)
        try escribir("""
            ---
            tls_type: task
            tls_schema: 1
            id: 9a1c2b3d-0000-4000-8000-000000000101
            numero: T-0101
            titulo: Solicitar facturas y extractos del trimestre
            estado: En curso
            responsable: Manu
            planificada: 2026-10-20
            vence: 2026-10-22
            estimacion_h: 2
            proyecto: "[[3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto|Talleres Martín · Trimestrales 2026]]"
            creada: 2026-10-19
            ---
            # Solicitar facturas y extractos del trimestre

            ## Descripción

            ## Actividad

            """, "3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Tareas/t-0101-solicitar-facturas-y-extractos.md", en: carpeta)
        try escribir(proyecto("Clínica Dental Sonrisa · Trimestrales", clase: "entrega", estado: "Sin empezar", extra: """
            empresa: "[[clinica-dental-sonrisa|Clínica Dental Sonrisa SLP]]"
            contacto: "[[dra-ana-pons|Dra. Ana Pons]]"
            oportunidad: "[[dra-ana-pons-trimestrales|Dra. Ana Pons · Trimestrales]]"
            inicio: 2026-10-26
            fin: 2027-01-29

            """), clinica.raw, en: carpeta)
        try escribir(proyecto("Expediente reservado", clase: "entrega", estado: "En curso", extra: "inicio: 2026-10-19\nfin: 2026-12-18\n"),
                     privadoEntrega.raw, en: carpeta)
        // Una propuesta enviada hace 7 días: hoy toca el seguimiento del día 7. Desde F4 ya viene así en Ribera
        // (la de Javier Ortega salió el 12/10: el Comercial le prepara ese seguimiento en el ejemplo).
    }
}
