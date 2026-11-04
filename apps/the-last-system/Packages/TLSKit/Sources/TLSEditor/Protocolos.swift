import AppKit
import SwiftUI

// Lo que el editor necesita de fuera. TLSEditor no conoce TLSCore ni los visores: quien lo usa (TLSUI) le
// da estos proveedores, que buscan en el índice, resuelven enlaces con la regla de Obsidian del núcleo y
// piden a TLSVisores las vistas de las incrustaciones.

/// Qué se ha escrito para abrir el autocompletado.
public enum DisparadorEnlace: Sendable, Hashable {
    /// `[[`: se busca una nota y se escribe el enlace en el estilo de la carpeta.
    case wiki
    /// `](`: se busca una nota y se escribe su ruta relativa (enlace Markdown).
    case markdown
}

/// Una nota para enlazar.
public struct SugerenciaEnlace: Sendable, Hashable, Identifiable {
    /// Identificador estable (la ruta en la carpeta).
    public let id: String
    public let titulo: String
    /// Dónde está o qué es («Contacto · 2 · Ventas»).
    public let detalle: String?
    /// SF Symbol del tipo.
    public let simbolo: String
    /// El otro nombre que ha coincidido, si no fue el título.
    public let porOtroNombre: String?

    public init(id: String, titulo: String, detalle: String? = nil, simbolo: String = "doc.text", porOtroNombre: String? = nil) {
        self.id = id; self.titulo = titulo; self.detalle = detalle; self.simbolo = simbolo; self.porOtroNombre = porOtroNombre
    }
}

/// Autocompletado de enlaces (`[[` y `](`).
@MainActor
public protocol AutocompletarEnlaces: AnyObject {
    /// Notas que coinciden con lo escrito (por nombre y por otros nombres), lo mejor primero.
    func sugerencias(_ consulta: String, disparador: DisparadorEnlace) async -> [SugerenciaEnlace]
    /// Texto que sustituye lo escrito desde el disparador hasta el cursor:
    /// - `.wiki`: todo el enlace (`[[jorge-martin|Jorge Martín]]` o `[Jorge Martín](../Contactos/jorge-martin.md)`).
    /// - `.markdown`: solo el destino y el paréntesis de cierre (`../Contactos/jorge-martin.md)`).
    func insercion(para sugerencia: SugerenciaEnlace, disparador: DisparadorEnlace, textoVisible: String?) -> String
}

/// Cómo abrir un enlace.
public enum AperturaEnlace: Sendable, Hashable {
    /// En la misma pestaña (entra un nivel).
    case aqui
    /// En una pestaña nueva, detrás.
    case pestanaNueva
    /// En una ventana nueva.
    case ventanaNueva
}

/// Resuelve y abre los enlaces del texto.
@MainActor
public protocol ResolutorEnlaces: AnyObject {
    /// Abre el enlace (⌘clic en edición, clic en Lectura).
    func abrir(_ enlace: EnlaceMarkdown, apertura: AperturaEnlace)
    /// Si lleva a algo (para pintar en gris los que aún no existen). Debe ser instantáneo.
    func estado(de enlace: EnlaceMarkdown) -> EstadoEnlace
}

/// Un bloque incrustado ya preparado por el proveedor.
public struct BloqueIncrustado {
    /// Lo que se pinta dentro del marco (PDF, imagen, reproductor…).
    public let contenido: AnyView
    /// Alto del contenido normal y ampliado (sin la franja del título).
    public let alto: CGFloat
    public let altoAmpliado: CGFloat
    /// Nombre que se ve en la franja y que lee VoiceOver.
    public let titulo: String
    /// SF Symbol del tipo.
    public let simbolo: String
    /// «Abrir» en la franja (`nil` = sin botón).
    public let abrir: (@MainActor () -> Void)?

    public init<V: View>(alto: CGFloat, altoAmpliado: CGFloat, titulo: String, simbolo: String,
                         abrir: (@MainActor () -> Void)? = nil, @ViewBuilder contenido: () -> V) {
        self.contenido = AnyView(contenido())
        self.alto = alto
        self.altoAmpliado = max(alto, altoAmpliado)
        self.titulo = titulo
        self.simbolo = simbolo
        self.abrir = abrir
    }
}

/// Pinta las incrustaciones (`![[x.pdf#page=3]]`, `![[imagen.png]]`, `![](Materiales/acta.pdf)`, audio, vídeo).
@MainActor
public protocol ProveedorIncrustaciones: AnyObject {
    /// El bloque de una incrustación, o `nil` si no se puede pintar (se ve como un enlace normal).
    func bloque(para incrustacion: Incrustacion) -> BloqueIncrustado?
}

/// Un título de la nota (para el índice del inspector).
public struct TituloNota: Sendable, Hashable, Identifiable {
    public var id: Int { posicion }
    public let nivel: Int
    public let texto: String
    /// Posición UTF-16 en el texto del editor.
    public let posicion: Int
}
