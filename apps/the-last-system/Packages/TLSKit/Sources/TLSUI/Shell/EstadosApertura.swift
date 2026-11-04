import SwiftUI
import TLSCore
import TLSDesign

/// «Leyendo tu empresa… 340 de 1.034».
struct AbriendoView: View {
    let entry: VaultEntry
    let progress: IndexProgress?

    var body: some View {
        VStack(spacing: TLSEspacio.e12) {
            HStack(spacing: TLSEspacio.e8) {
                Monograma(nombre: entry.nombre)
                Text(entry.nombre).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                Badge(entry.badge)
            }
            if let total = progress?.total, total > 0 {
                ProgressView(value: Double(min(progress?.processed ?? 0, total)), total: Double(total))
                    .frame(width: 320)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(label)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .monospacedDigit()
        }
        .padding(40)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .background(TLSPaleta.fondo.color)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("empresa.abriendo")
    }

    private var label: String {
        guard let progress, progress.processed > 0 else { return "Leyendo tu empresa…" }
        return "Leyendo tu empresa… \(TLSFormat.progreso(progress.processed, de: progress.total))"
    }
}

/// «Ver sin tocar»: una carpeta privada elegida ya no está. No se abre hasta volver a elegir.
struct PrivadaPerdidaView: View {
    let missing: String
    let onChoose: () -> Void

    var body: some View {
        VacioExplicado(icono: "lock.trianglebadge.exclamationmark", titulo: "No encuentro una carpeta privada",
                       porQue: "«\(missing)» era una de las carpetas privadas que elegiste y ya no está ahí: puede que la hayas movido o le hayas cambiado el nombre. Para no mostrar nada privado por error, vuelve a elegir tus carpetas privadas.",
                       accion: "Elegir las carpetas privadas…", alPulsar: onChoose)
            .padding(40)
            .frame(minWidth: 520, minHeight: 360)
            .accessibilityIdentifier("empresa.privadaPerdida")
    }
}

/// Error al abrir: mensaje llano, detalle técnico plegado y dos salidas.
struct ErrorAlAbrirView: View {
    let message: String
    let onRetry: () -> Void
    let onRebuild: () -> Void

    var body: some View {
        VStack(spacing: TLSEspacio.e16) {
            VacioExplicado(icono: "exclamationmark.triangle", titulo: "No he podido abrir tu empresa",
                           porQue: "Algo ha fallado al leerla. Tu carpeta no ha cambiado. Si vuelve a pasar, léela de nuevo desde cero: tarda un poco más, pero no toca nada de la carpeta.",
                           accion: "Leer de nuevo desde cero", alPulsar: onRebuild,
                           secundaria: "Volver a intentarlo", alPulsarSecundaria: onRetry)
            DisclosureGroup("Detalle técnico") {
                Text(message)
                    .tlsTexto(TLSTipo.codigo)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 440)
        }
        .padding(40)
        .frame(minWidth: 520, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
        .accessibilityIdentifier("empresa.error")
    }
}
