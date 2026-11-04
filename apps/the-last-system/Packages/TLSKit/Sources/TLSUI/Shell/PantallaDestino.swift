import SwiftUI
import TLSCore
import TLSDesign

/// Enrutador: la pantalla de cada `Destino`. Cada rol rellena la suya en su carpeta; aquí solo se elige
/// (los `init` son el contrato de `docs/F1-INTERFAZ-CONTRATOS.md` y, desde F2, de `docs/F2-CONTRATOS.md`).
struct PantallaDestino: View {
    let destino: Destino
    let sesion: VaultSession

    var body: some View {
        VStack(spacing: 0) {
            EncimaDePantalla(sesion: sesion)
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(TLSPaleta.fondo.color)
        .tlsPantalla(destino.identidad)
    }

    @ViewBuilder
    private var contenido: some View {
        switch destino {
        case .hoy:
            HoyPantalla(sesion: sesion)
        case .decisiones:
            DecisionesPantalla(sesion: sesion)
        case .tareas:
            TareasPantalla(sesion: sesion)
        case .revisar:
            RevisarPantalla(sesion: sesion)
        case .area(let code, let pestana):
            AreaScaffold(area: code, pestana: pestana, sesion: sesion)
        case .todasLasBases:
            TodasLasBasesPantalla(sesion: sesion)
        case .base(let id, let vista, let contexto):
            BasePantalla(id: id, vista: vista, contexto: contexto, sesion: sesion)
        case .ficha(let ruta, let pestana):
            FichaPantalla(ruta: ruta, pestana: pestana, sesion: sesion)
        case .nota(let ruta):
            NotaEditorPantalla(ruta: ruta, sesion: sesion)
        case .fichero(let ruta):
            VisorFicheroPantalla(ruta: ruta, sesion: sesion)
        case .carpeta(let ruta):
            // F5 · buzon-relevo: Carpeta › Buzón es la vista del correo, los informes y lo que está por ordenar.
            if BuzonPantalla.es(ruta, sesion) {
                BuzonPantalla(sesion: sesion)
            } else {
                CarpetaPantalla(carpeta: ruta, sesion: sesion)
            }
        case .busqueda(let texto):
            ResultadosBusquedaPantalla(consulta: texto, sesion: sesion)
        case .asistentes:
            AsistentesPantalla(sesion: sesion)
        case .asistente(let slug):
            AsistenteFichaPantalla(slug: slug, sesion: sesion)
        case .ajustes:
            AjustesPantalla(sesion: sesion)
        case .tarea(let ruta):
            TareaDetalle(ruta: ruta, sesion: sesion)
        case .decision(let id):
            DecisionDetalle(id: id, sesion: sesion)
        case .banco(let cuenta):
            BancoPantalla(cuenta: cuenta, sesion: sesion)
        }
    }
}
