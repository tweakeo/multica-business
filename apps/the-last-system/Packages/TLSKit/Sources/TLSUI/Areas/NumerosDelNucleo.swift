import Foundation
import TLSCore

/// Los números del núcleo (rol de números, F2: `Sources/TLSCore/Metricas`) para el andamio de las áreas: el valor,
/// el ritmo y la fuente de cada código con `KPIEvaluador`, y la etapa con `EtapaCalculador`. Sin la fuente de un
/// número, «Sin dato» con su motivo como fuente; nunca un 0 de relleno.
public struct NumerosDelNucleo: ProveedorNumerosArea {
    public init() {}

    public func numeros(de area: AreaCode, codigos: [String], contexto: ContextoNumeros) -> NumerosDeArea {
        let foto = FotoMetricas(snapshot: contexto.foto, hoy: contexto.hoy)
        let evaluador = KPIEvaluador(foto: foto, metas: MetasDocumento.leer(contexto.foto))
        var lecturas: [String: LecturaNumero] = [:]
        for codigo in codigos {
            let v = evaluador.evaluar(codigo)
            if let n = v.medida.numero, n.isFinite {
                lecturas[codigo] = LecturaNumero(valor: n, texto: v.textoValor, ritmo: Self.ritmo(v), fuente: v.fuente.vacioEsNil)
            } else {
                lecturas[codigo] = LecturaNumero(valor: nil, ritmo: .sinDato, fuente: (v.medida.motivoSinDato ?? v.fuente).vacioEsNil)
            }
        }
        return NumerosDeArea(lecturas: lecturas, etapa: EtapaCalculador(foto: foto).area(area).etapa)
    }

    /// El ritmo del núcleo en las palabras del andamio: adelantado o en ritmo → «En ritmo»; atención → «Atención»;
    /// en riesgo o crítico → «En alerta» solo si el número ha cruzado su alerta (lo que cuenta la sección Alertas de
    /// Hoy); si no, «Atención». Así «rojo» significa una sola cosa en toda la app.
    static func ritmo(_ v: ValorKPI) -> RitmoNumero {
        switch v.ritmo.estado {
        case .adelantado, .enRitmo: .enRitmo
        case .atencion: .atencion
        case .enRiesgo, .critico: v.estado == .mal ? .enAlerta : .atencion
        case .sinMeta: .sinMeta
        case .sinDato: .sinDato
        }
    }
}

private extension String {
    var vacioEsNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
