import Foundation

// Corrector final de F3. Las respuestas de la puesta en marcha de Asesoría Ribera (la empresa de ejemplo, inventada)
// que su carpeta no trae escritas: así, al repasarla, se ve completa (PLAN §6.8) y no casi en blanco. Son datos de
// ejemplo, coherentes con lo que hay en la carpeta (asesoría fiscal y contable de Valencia, dos personas). No se
// escriben en ninguna carpeta: solo llenan `onboarding.json` del ejemplo.

enum RespuestasDelEjemplo {
    /// Identificador de la pregunta → respuesta.
    static let ribera: [String: ValorRespuesta] = {
        var r: [String: ValorRespuesta] = [
            // Conocer tu negocio.
            PreguntaID.camino.rawValue: .opcion("crecer"),
            PreguntaID.metaGeneral.rawValue: .opcion("tiempo"),
            PreguntaID.fraseCliente.rawValue: .texto("autónomos y pequeños negocios de Valencia"),
            PreguntaID.fraseResultado.rawValue: .texto("tener sus impuestos al día y sin sustos"),
            PreguntaID.frasePlazo.rawValue: .texto("cada trimestre"),
            PreguntaID.fraseMetodo.rawValue: .texto("un calendario fiscal y una revisión al mes"),
            PreguntaID.fraseDolor.rawValue: .texto("recargos ni papeles perdidos"),
            PreguntaID.destino.rawValue: .texto("Llevar 120 clientes de trimestrales en 2028 sin pasar de 40 horas a la semana"),
            PreguntaID.logo.rawValue: .opcion("aun-no"),
        ]
        // Cómo va cada área (1 a 5) y cuánto depende de la persona.
        let funciona: [AreaCode: Int] = [.direccion: 3, .ventas: 2, .entrega: 4, .finanzas: 3, .marca: 2, .equipo: 2]
        let depende: [AreaCode: Int] = [.direccion: 5, .ventas: 4, .entrega: 3, .finanzas: 4, .marca: 3, .equipo: 4]
        let estado: [AreaCode: String] = [.direccion: "activa", .ventas: "activa", .entrega: "activa", .finanzas: "activa",
                                          .marca: "preparada", .equipo: "preparada"]
        let lleva: [AreaCode: String] = [.direccion: "Tú", .ventas: "Tú", .entrega: "Nuria", .finanzas: "Tú",
                                         .marca: "Nuria", .equipo: "Tú"]
        for a in AreaCode.allCases {
            r[PreguntaID.funciona(a).rawValue] = .escala(funciona[a] ?? 3)
            r[PreguntaID.depende(a).rawValue] = .escala(depende[a] ?? 3)
            r[PreguntaID.estadoArea(a).rawValue] = .opcion(estado[a] ?? "activa")
            r[PreguntaID.ocupante(a).rawValue] = .texto(lleva[a] ?? "Tú")
        }
        // Sus sistemas (los mismos en Organizar y en «Qué funciona sin ti»).
        let sistemas: [String: String] = [
            "CO1": "a medias", "DI1": "montado", "DI2": "a medias", "DI3": "montado",
            "VE1": "montado", "VE2": "montado", "VE3": "falta",
            "EN1": "a medias", "EN2": "montado", "EN3": "falta",
            "FI1": "montado", "FI2": "a medias", "FI3": "a medias",
            "MA1": "a medias", "MA2": "montado", "MA3": "a medias",
            "EQ1": "montado", "EQ2": "falta", "EQ3": "falta",
        ]
        for (c, e) in sistemas { r[PreguntaID.sistema(c).rawValue] = .opcion(e) }
        // Qué funciona sin ti: lo montado; el embudo, a un asistente (como dice su tarea de Equipo).
        let sinTi: [String: (Bool, Bool)] = [
            "DI1": (false, false), "DI3": (false, false), "VE1": (true, false), "VE2": (false, true),
            "EN2": (true, false), "FI1": (false, false), "MA2": (false, false), "EQ1": (true, false),
        ]
        for (c, v) in sinTi {
            r[PreguntaID.sinTi(c).rawValue] = .siNo(v.0)
            r[PreguntaID.automatizar(c).rawValue] = .siNo(v.1)
        }
        // Dirección: decisiones sin tomar a los 14 días (cuanto menos, mejor).
        r[PreguntaID.meta(.direccion).rawValue] = .numero(1)
        r[PreguntaID.alerta(.direccion).rawValue] = .numero(3)
        return r
    }()

    static let origen = OrigenRespuesta.propuesta("Respuesta del ejemplo")
}
