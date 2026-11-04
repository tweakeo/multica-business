import Foundation
import TLSCore
import TLSDesign

/// Un paso de un recorrido: qué se señala, qué se explica (dos o tres líneas) y qué acción real lo da por hecho.
struct PasoTutorial: Sendable, Hashable, Identifiable {
    /// Botón propio del paso, además de los de siempre.
    enum Accion: String, Sendable, Hashable {
        /// «Mostrar en Finder» (la ficha editada o la del paso).
        case mostrarEnFinder
        /// «Dame un extracto de ejemplo»: lo deja en el Finder para arrastrarlo.
        case extractoDeEjemplo
    }

    let id: String
    let titulo: String
    let texto: String
    /// Lo que se dice cuando ya está hecho.
    let textoHecho: String?
    let ancla: TutorialAnclaID?
    /// Adónde lleva «Llévame».
    let destino: Destino?
    /// Partes que lo dan por hecho (todas). Vacío: paso que solo explica.
    let partes: [String]
    let llegaConLosAsistentes: Bool
    /// Pulsar dentro del sitio señalado cuenta como la acción (el foco de Hoy).
    let porClic: Bool
    /// Sección del manual de «Saber más».
    let manual: String
    let accion: Accion?

    init(id: String, titulo: String, texto: String, textoHecho: String? = nil, ancla: TutorialAnclaID? = nil,
         destino: Destino? = nil, partes: [String] = [], llegaConLosAsistentes: Bool = false, porClic: Bool = false,
         manual: String, accion: Accion? = nil) {
        self.id = id; self.titulo = titulo; self.texto = texto; self.textoHecho = textoHecho; self.ancla = ancla
        self.destino = destino; self.partes = partes; self.llegaConLosAsistentes = llegaConLosAsistentes
        self.porClic = porClic; self.manual = manual; self.accion = accion
    }

    /// Paso con algo que hacer (no solo explica).
    var tieneAccion: Bool { !partes.isEmpty && !llegaConLosAsistentes }

    func hecho(_ partesHechas: Set<String>) -> Bool { tieneAccion && Set(partes).isSubset(of: partesHechas) }

    /// Minutos que suele llevar (para «Quedan ~N min»).
    var minutos: Double { tieneAccion ? 1.5 : 0.5 }
}

/// Lo que el recorrido «con tu empresa» necesita saber de ella.
struct ContextoRecorrido: Sendable, Hashable {
    /// Una ficha para editar (en el ejemplo, un contacto de Ribera).
    var ficha: VaultPath?
    /// El área que frena a las demás (de su diagnóstico o del mapa). `nil` si no se sabe.
    var cuello: AreaCode?

    static let vacio = ContextoRecorrido(ficha: nil, cuello: nil)
}

/// Los pasos de cada recorrido. Textos propios, en español llano, sin nada de ningún curso.
enum Recorridos {
    /// La ficha que se edita en el ejemplo (un contacto de Ribera).
    static let fichaEjemplo = VaultPath("2 · Ventas/Contactos/marta-soler.md")

    static func pasos(_ tipo: TipoRecorrido, contexto: ContextoRecorrido = .vacio) -> [PasoTutorial] {
        switch tipo {
        case .ejemplo: ejemplo(ficha: contexto.ficha ?? fichaEjemplo)
        case .tuEmpresa: tuEmpresa(contexto)
        }
    }

    /// El paso con el que se cumple cada hito del ejemplo.
    static func hito(de paso: PasoTutorial) -> HitoTutorial? { HitoTutorial(rawValue: paso.id) }

    static func ejemplo(ficha: VaultPath) -> [PasoTutorial] {
        [
            PasoTutorial(id: "bienvenida", titulo: "Asesoría Ribera, una empresa de ejemplo",
                         texto: "Es inventada y su puesta en marcha ya está hecha. Vas a probar diez cosas con ella: lo que cambies aquí no toca ninguna empresa de verdad.",
                         destino: .hoy, manual: "empezar"),
            PasoTutorial(id: HitoTutorial.focoDeHoy.rawValue, titulo: "Tu foco de hoy",
                         texto: "Cada día, Hoy elige lo más importante y te dice por qué importa y qué pasa si no lo haces. Pulsa su botón o «Ver detalle».",
                         textoHecho: "Así empieza cada día: una cosa clara antes que veinte a medias.",
                         ancla: .hoyFoco, destino: .hoy, partes: ["foco"], porClic: true, manual: "hoy"),
            PasoTutorial(id: HitoTutorial.aprobarOModificar.rawValue, titulo: "Aprueba o cambia una decisión",
                         texto: "Aquí espera lo que necesita tu OK, con tres opciones como mucho y una recomendada. Abre una y apruébala o responde con tus cambios.",
                         textoHecho: "Lo que decidiste queda apuntado en el registro de decisiones, con su porqué.",
                         ancla: .decisionesGrupo, destino: .decisiones, partes: ["decision"], manual: "decidir"),
            PasoTutorial(id: HitoTutorial.moverOportunidad.rawValue, titulo: "Mueve una oportunidad",
                         texto: "En Ventas, cada oportunidad avanza de Prospecto a Ganada. Arrastra una tarjeta a la columna siguiente.",
                         textoHecho: "Ganada solo llega con un cobro confirmado: la app no te deja adelantarte.",
                         ancla: .ventasCRM, destino: .area(.ventas, pestana: PestanaArea.operacion.rawValue),
                         partes: ["oportunidad"], manual: "ventas"),
            PasoTutorial(id: HitoTutorial.crearYAsignarTarea.rawValue, titulo: "Crea una tarea y dásela a alguien",
                         texto: "Pulsa «Nueva tarea» (o ⌘N), escribe qué hay que hacer y elige quién la lleva.",
                         textoHecho: "Cada tarea es una ficha con su historia: quién la lleva, cuándo vence y qué se ha hecho.",
                         ancla: .tareasNueva, destino: .tareas, partes: ["tarea"], manual: "tareas"),
            PasoTutorial(id: HitoTutorial.editarYVerEnFinder.rawValue, titulo: "Edita una ficha y mírala en Finder",
                         texto: "Cambia un dato de esta ficha. Después pulsa «Mostrar en Finder»: es un fichero normal de tu Mac.",
                         textoHecho: "Tu empresa son ficheros tuyos: la app los ordena, pero puedes abrirlos con cualquier programa.",
                         ancla: .ficha, destino: .ficha(ficha), partes: ["editar", "finder"], manual: "carpeta",
                         accion: .mostrarEnFinder),
            PasoTutorial(id: HitoTutorial.registrarDecision.rawValue, titulo: "Apunta una decisión",
                         texto: "«Registrar decisión» deja una línea con la fecha y el porqué. Nada se borra: lo que cambie queda marcado como sustituido.",
                         textoHecho: "El registro es la memoria de la empresa: por qué se hizo cada cosa.",
                         ancla: .direccionRegistrarDecision, destino: .area(.direccion, pestana: PestanaArea.operacion.rawValue),
                         partes: ["registro"], manual: "decidir"),
            PasoTutorial(id: HitoTutorial.importarExtracto.rawValue, titulo: "Importa un extracto del banco",
                         texto: "Pide el extracto de ejemplo y arrástralo a la zona punteada. Antes de escribir nada verás qué movimientos son nuevos.",
                         textoHecho: "Si vuelves a importar el mismo extracto, no se repite ningún movimiento.",
                         ancla: .bancoImportar, destino: .banco(nil), partes: ["extracto"], manual: "banco",
                         accion: .extractoDeEjemplo),
            PasoTutorial(id: HitoTutorial.mapaYCuello.rawValue, titulo: "Mira el mapa y el cuello",
                         texto: "En la Operación de Dirección, abre «Mapa»: cada área en su etapa y, marcada, la que frena a las demás.",
                         textoHecho: "Se trabaja solo el cuello unas semanas y luego se vuelve a mirar el mapa.",
                         ancla: .direccionMapa, destino: .area(.direccion, pestana: PestanaArea.operacion.rawValue),
                         partes: ["mapa"], manual: "etapas"),
            PasoTutorial(id: HitoTutorial.abrirAsistente.rawValue, titulo: "Pregunta al asistente con ⌘J",
                         texto: "Pulsa ⌘J y pregúntale a Mika, por ejemplo, «¿qué tengo hoy?». Sabe en qué pantalla estás.",
                         textoHecho: "Lo que Mika prepare te espera en Decisiones: nada sale sin tu OK.",
                         destino: .hoy, partes: ["asistente"], manual: "asistentes"),
            PasoTutorial(id: HitoTutorial.pausarAsistentes.rawValue, titulo: "Pausa y reanuda los asistentes",
                         texto: "En Asistentes, apaga el interruptor y vuelve a encenderlo. Pausados no hacen nada; lo pendiente espera.",
                         textoHecho: "El interruptor los para a todos a la vez. Nada sale de la app sin tu OK.",
                         destino: .asistentes, partes: ["pausar", "reanudar"], manual: "asistentes"),
            // F5 · integración: las conexiones, en llano (solo explica; en el ejemplo no se conecta nada de verdad).
            PasoTutorial(id: "conexiones", titulo: "Mail, Calendario y otros programas",
                         texto: "En Ajustes › Conexiones verás qué usa la app de tu Mac. Mail solo lee y enviar es tuyo; el Calendario no invita a nadie; en el ejemplo, todo es de mentira.",
                         destino: .ajustes, manual: "conexiones"),
            PasoTutorial(id: "final", titulo: "Ya conoces lo principal",
                         texto: "Puedes repasar la puesta en marcha de Ribera paso a paso o reiniciar el ejemplo para empezar de cero.",
                         manual: "empezar"),
        ]
    }

    static func tuEmpresa(_ c: ContextoRecorrido) -> [PasoTutorial] {
        let cuello: PasoTutorial
        if let a = c.cuello {
            cuello = PasoTutorial(id: "area-del-cuello", titulo: "Entra en \(a.etiquetaNumerada), tu cuello",
                                  texto: "Es el área que frena a las demás según lo que contaste. Estas semanas se trabaja solo esa.",
                                  textoHecho: "Cuando el cuello mejore, el mapa te dirá cuál es el siguiente.",
                                  ancla: .areaPestanas, destino: .area(a), partes: [TutorialEvent.areaVista(a).parte], manual: "etapas")
        } else {
            cuello = PasoTutorial(id: "area-del-cuello", titulo: "Busca tu cuello en el mapa",
                                  texto: "En la Operación de Dirección, abre «Mapa»: verás qué área frena a las demás.",
                                  textoHecho: "Estas semanas se trabaja solo esa área.",
                                  ancla: .direccionMapa, destino: .area(.direccion, pestana: PestanaArea.operacion.rawValue),
                                  partes: ["mapa"], manual: "etapas")
        }
        return [
            PasoTutorial(id: "hoy", titulo: "Mira Hoy",
                         texto: "Hoy elige cada día lo más importante de tu empresa. Pulsa en tu foco para ver por qué importa.",
                         textoHecho: "Vuelve aquí cada mañana: es la puerta de entrada.",
                         ancla: .hoyFoco, destino: .hoy, partes: ["foco"], porClic: true, manual: "hoy"),
            cuello,
            PasoTutorial(id: "aprobar-propuesta", titulo: "Aprueba la primera propuesta de Mika",
                         texto: "Mika, el asistente de Dirección, te propone cosas en Decisiones y espera tu OK. Elige la opción que prefieras.",
                         textoHecho: "Lo que apruebas lo aplica la app, como tú, y se puede deshacer.",
                         ancla: .decisionesGrupo, destino: .decisiones, partes: ["propuesta"], manual: "asistentes"),
            PasoTutorial(id: "editar-ficha", titulo: "Edita una ficha",
                         texto: "Cambia un dato de esta ficha: se guarda solo y se deshace con ⌘Z.",
                         textoHecho: "Cada cambio queda guardado en el fichero, y se puede deshacer.",
                         ancla: .ficha, destino: c.ficha.map { .ficha($0) }, partes: ["editar"], manual: "carpeta"),
            PasoTutorial(id: "ver-en-finder", titulo: "Mírala en Finder",
                         texto: "Pulsa «Mostrar en Finder»: tu empresa son ficheros normales de tu Mac.",
                         textoHecho: "Puedes abrirlos con cualquier programa: son tuyos.",
                         partes: ["finder"], manual: "carpeta", accion: .mostrarEnFinder),
            PasoTutorial(id: "conexiones", titulo: "Conecta lo que quieras",
                         texto: "Mail, Calendario y otros programas se conectan en Ajustes › Conexiones. Antes de cada permiso verás para qué es y qué no hará nunca.",
                         destino: .ajustes, manual: "conexiones"),
            PasoTutorial(id: "final", titulo: "Primer recorrido hecho",
                         texto: "Ya sabes moverte por tu empresa. Lo demás lo irás viendo en Hoy, día a día.",
                         manual: "empezar"),
        ]
    }
}
