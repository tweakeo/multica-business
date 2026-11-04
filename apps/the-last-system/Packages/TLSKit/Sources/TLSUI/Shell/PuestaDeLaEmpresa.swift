import AppKit
import SwiftUI
import TLSCore
import TLSDesign

// F3 · integración. Por dónde se llega a la puesta en marcha sin que TLSUI dependa de TLSOnboarding: la ventana se
// abre por su identificador (`PuertaPuestaEnMarcha.ventanaID`) con una `PeticionPuestaEnMarcha`. Aquí, lo que la
// enseña en el arranque («Seguir con la puesta en marcha» por cada una a medias), en Hoy (la línea «Seguir con la puesta
// en marcha · paso N de 9» mientras no esté terminada) y en Ajustes › Esta empresa (seguir, empezar o repasar; traer lo
// nuevo de la carpeta real; importar de Multica).

/// Qué puesta en marcha tiene una empresa abierta y cómo se abre.
@MainActor
public enum PuestaDeLaEmpresa {
    /// Lo guardado para esta empresa (`nil`: aún no hay puesta en marcha).
    public static func progreso(_ sesion: VaultSession) -> ProgresoPuestaEnMarcha? {
        ProgresoPuestaEnMarcha.leer(vaultID: sesion.entry.id, appSupport: sesion.appSupportDeLaSesion)
    }

    /// Repasar si está terminada; seguir si está a medias; empezar si no hay ninguna.
    public static func peticion(_ sesion: VaultSession) -> PeticionPuestaEnMarcha {
        let modo: PeticionPuestaEnMarcha.Modo
        switch progreso(sesion) {
        case .some(let p) where p.terminada: modo = .repasar
        case .some: modo = .retomar
        case .none: modo = .empezar
        }
        return PeticionPuestaEnMarcha(modo: modo, vaultID: sesion.entry.id)
    }

    /// El texto del botón o del menú.
    public static func tituloMenu(_ sesion: VaultSession?) -> String {
        guard let sesion else { return "Puesta en marcha…" }
        switch peticion(sesion).modo {
        case .repasar: return "Repasar la puesta en marcha…"
        case .retomar: return "Seguir con la puesta en marcha…"
        case .empezar: return "Empezar la puesta en marcha…"
        }
    }

    /// «Actualizar la copia desde la real» solo tiene sentido en una copia que sabe de qué carpeta real salió.
    public static func sePuedeActualizarCopia(_ sesion: VaultSession) -> Bool {
        sesion.entry.clase == .copia && sesion.entry.origen != nil && sesion.puedeEscribir
    }

    /// Lo que se enseña en el arranque por cada puesta en marcha a medias (también las de «Empiezo de cero» que aún no
    /// tienen carpeta). El nombre: el de la carpeta registrada o el que se contestó.
    public static func pendientes(_ model: AppModel) -> [PendientePuesta] {
        AlmacenPuesta.pendientes(appSupport: model.appSupport).compactMap { e in
            let entrada = model.entry(id: e.vaultID)
            // La de una carpeta que ya no está en la lista (se quitó) no se puede seguir.
            if entrada == nil, e.ruta?.conCarpeta == true { return nil }
            let nombre = entrada?.nombre
                ?? e.respuesta(.nombreEmpresa)?.valor.texto?.nilSiVacioPuesta
                ?? (e.respuesta(.como)?.valor.opcion == "carpeta" ? "Tu carpeta, aún sin copiar" : "Empresa nueva")
            return PendientePuesta(id: e.vaultID, nombre: nombre, progreso: ProgresoPuestaEnMarcha.de(e))
        }
    }
}

/// Una puesta en marcha a medias (arranque).
public struct PendientePuesta: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let nombre: String
    public let progreso: ProgresoPuestaEnMarcha
}

private extension String {
    var nilSiVacioPuesta: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public extension VaultSession {
    /// El Application Support de esta sesión (el de la app o, en pruebas, el de su estado aparte): ahí están su
    /// `onboarding.json` y su `tutorial.json`.
    var appSupportDeLaSesion: URL { directorioEstado.deletingLastPathComponent() }
}

// MARK: - Hoy

/// La línea de Hoy «Seguir con la puesta en marcha · paso 4 de 9» con «Quedan ~N min» y «Seguir». No sale si no hay
/// puesta en marcha empezada o si ya está terminada. Lo lee Hoy (`progreso(de:)`) al abrir, tras cada cambio y al
/// volver a la ventana (la puesta en marcha va en la suya).
struct AvisoPuestaEnMarcha: View {
    let sesion: VaultSession
    let progreso: ProgresoPuestaEnMarcha?
    @Environment(\.openWindow) private var openWindow

    /// Lo que enseña Hoy de esta empresa (`nil`: nada que seguir).
    static func progreso(de sesion: VaultSession) -> ProgresoPuestaEnMarcha? {
        PuertaPuestaEnMarcha.avisoDeHoy(vaultID: sesion.entry.id, appSupport: sesion.appSupportDeLaSesion)
    }

    var body: some View {
        if let p = progreso, !p.terminada {
            fila(p)
        }
    }

    private func fila(_ p: ProgresoPuestaEnMarcha) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TLSPaleta.texto.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.texto).tlsTexto(TLSTipo.tituloModulo).foregroundStyle(TLSPaleta.texto.color)
                Text("\(p.textoMinutos) · lo que ya contestaste está guardado")
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("Seguir") {
                openWindow(id: PuertaPuestaEnMarcha.ventanaID,
                           value: PeticionPuestaEnMarcha(modo: .retomar, vaultID: sesion.entry.id))
            }
            .tlsBoton(.secundario)
            .help("Abre la puesta en marcha donde la dejaste")
            .accessibilityIdentifier("hoy.puestaEnMarcha.seguir")
        }
        .padding(TLSEspacio.e16)
        .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, radio: TLSRadio.mosaico)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(p.texto). \(p.textoMinutos.replacingOccurrences(of: "~", with: "unos "))")
        .accessibilityIdentifier("hoy.puestaEnMarcha")
    }
}

// MARK: - Ajustes › Esta empresa

/// «Puesta en marcha», «Carpeta real» (actualizar la copia) e «Importar de Multica» en Ajustes › Esta empresa.
struct FilasPuestaEnAjustes: View {
    let sesion: VaultSession
    @Environment(\.openWindow) private var openWindow
    @State private var multica = false
    @State private var progreso: ProgresoPuestaEnMarcha?

    var body: some View {
        LabeledContent("Puesta en marcha") {
            HStack(spacing: TLSEspacio.e8) {
                Text(estado)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                Button(PuestaDeLaEmpresa.tituloMenu(sesion)) {
                    openWindow(id: PuertaPuestaEnMarcha.ventanaID, value: PuestaDeLaEmpresa.peticion(sesion))
                }
                .help("Te guía paso a paso. Nada se escribe hasta que pulsas «Aplicar» y todo se puede deshacer.")
                .accessibilityIdentifier("ajustes.puestaEnMarcha")
            }
        }
        .task(id: sesion.revision) { progreso = PuestaDeLaEmpresa.progreso(sesion) }
        FilaActualizarCopia(sesion: sesion)
        LabeledContent("Multica") {
            Button("Importar tareas de Multica…") { multica = true }
                .disabled(!sesion.puedeEscribir)
                .help("Trae tus tareas abiertas de Multica como tareas de la app. Ves cada una antes de importarla.")
                .accessibilityIdentifier("ajustes.importarMultica")
        }
        .sheet(isPresented: $multica) { ImportarMulticaHoja(sesion: sesion) }
    }

    private var estado: String {
        guard let p = progreso else { return "Sin empezar" }
        return p.terminada ? "Terminada" : "Paso \(p.numero) de \(p.total)"
    }
}

// MARK: - Arranque

/// «Seguir con la puesta en marcha» en el selector de empresa: una fila por cada una a medias (como mucho tres).
struct PuestasPendientesArranque: View {
    let pendientes: [PendientePuesta]
    let seguir: (UUID) -> Void

    var body: some View {
        if !pendientes.isEmpty {
            let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                ForEach(pendientes.prefix(3)) { p in
                    HStack(spacing: TLSEspacio.e12) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(TLSPaleta.texto.color)
                            .frame(width: 36)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.progreso.texto)
                                .tlsTexto(TLSTipo.interfazFuerte)
                                .foregroundStyle(TLSPaleta.texto.color)
                            Text("\(p.nombre) · \(p.progreso.textoMinutos)")
                                .tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                                .lineLimit(1)
                        }
                        Spacer(minLength: TLSEspacio.e8)
                        Button("Seguir") { seguir(p.id) }
                            .tlsBoton(.secundario)
                            .help("Sigue donde lo dejaste, con todo lo que contestaste")
                            .accessibilityIdentifier("selector.seguirPuesta.\(p.id.uuidString)")
                    }
                    .frame(minHeight: 48)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Seguir") { seguir(p.id) }
                }
            }
            .padding(.horizontal, TLSEspacio.e16)
            .padding(.vertical, TLSEspacio.e8)
            .background(forma.fill(TLSPaleta.superficie.color))
            .tlsSombra(.uno, forma: forma)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("selector.puestasPendientes")
        }
    }
}

// MARK: - El ejemplo

public extension AppModel {
    /// «Ver un ejemplo» desde la puesta en marcha: instala Asesoría Ribera (o la reutiliza) y devuelve su carpeta. Por
    /// omisión, la que trae la app en `~/The Last System/Empresas`; las pruebas pasan sus carpetas temporales.
    func instalarEjemplo(origen: URL? = nil, empresas: URL = AppLocations.empresas) async throws -> VaultEntry {
        try await InstaladorEjemplo(origen: origen ?? InstaladorEjemplo.origenEnLaApp, empresas: empresas)
            .instalarOAbrir(en: self).entrada
    }
}
