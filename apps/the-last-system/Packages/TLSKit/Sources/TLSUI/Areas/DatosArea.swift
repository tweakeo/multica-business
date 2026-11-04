import Foundation
import TLSCore
import TLSDesign

// Valores de vista del andamio de las áreas (PLAN §6.5, SISTEMAS §2.3 y §4.2). Son puros y `Sendable`: los
// rellena `LectorArea` con la foto de la carpeta, fuera del hilo principal, y los números clave los pone quien
// cumpla `ProveedorNumerosArea` (el rol de números). Sin dato se dice «Sin dato»; sin meta, «Sin meta». Nunca 0.

/// En qué punto está un área (lo dice su `Área.md`).
public enum FaseArea: String, Sendable, Hashable, Codable {
    /// En reposo: solo Resumen, con «Activar».
    case reposo
    /// Preparada: todo se ve, con el aviso «Los asistentes aún no trabajan aquí».
    case preparada
    case activa
    /// `Área.md` no dice su estado (como el ejemplo, que viene de G2): se ve todo y la cabecera dice «Sin estado».
    case sinEstado

    public init(_ estado: AreaStatus) {
        switch estado {
        case .activa: self = .activa
        case .preparada: self = .preparada
        case .reposo: self = .reposo
        case .desconocido: self = .sinEstado
        }
    }

    public var palabra: String {
        switch self {
        case .reposo: "En reposo"
        case .preparada: "Preparada"
        case .activa: "Activa"
        case .sinEstado: "Sin estado"
        }
    }

    public var estado: TLSEstado { self == .activa ? .bien : .sinDato }
}

/// Las cuatro pestañas de un área (el `id` es el nombre visible, como en `Destino.area(_:pestana:)`).
public enum PestanaArea: String, CaseIterable, Sendable, Hashable {
    case resumen = "Resumen"
    case operacion = "Operación"
    case control = "Control"
    case sistemas = "Sistemas y activos"
}

/// Ritmo de un número clave frente a su meta y su alerta (el área toma el de su número más atrasado).
public enum RitmoNumero: String, Sendable, Hashable, Codable, CaseIterable {
    case enRitmo, atencion, enAlerta, sinMeta, sinDato

    public var palabra: String {
        switch self {
        case .enRitmo: "En ritmo"
        case .atencion: "Atención"
        case .enAlerta: "En alerta"
        case .sinMeta: "Sin meta"
        case .sinDato: "Sin dato"
        }
    }

    public var estado: TLSEstado {
        switch self {
        case .enRitmo: .bien
        case .atencion: .atencion
        case .enAlerta: .mal
        case .sinMeta, .sinDato: .sinDato
        }
    }

    /// Cuánto pesa para «el más atrasado»: en alerta > atención > en ritmo > sin meta > sin dato.
    var gravedad: Int {
        switch self {
        case .enAlerta: 4
        case .atencion: 3
        case .enRitmo: 2
        case .sinMeta: 1
        case .sinDato: 0
        }
    }

    /// El ritmo de un área: el de su número más atrasado. Si ninguno tiene dato frente a su meta, «Sin dato»; si
    /// ninguno tiene meta, «Sin meta».
    public static func deArea(_ ritmos: [RitmoNumero]) -> RitmoNumero {
        if let peor = ritmos.filter({ $0.gravedad >= 2 }).max(by: { $0.gravedad < $1.gravedad }) { return peor }
        if !ritmos.isEmpty, ritmos.allSatisfy({ $0 == .sinMeta }) { return .sinMeta }
        return .sinDato
    }
}

/// Lo que el rol de números sabe de un código de `Metas.md`.
public struct LecturaNumero: Sendable, Hashable {
    /// El número (`nil` = sin dato). Nunca un 0 de relleno.
    public var valor: Double?
    /// Ya escrito con su unidad («6,0 meses», «1.000 €»). Si falta y hay valor, se escribe la cifra sola.
    public var texto: String?
    /// Frente a la meta y la alerta de `Metas.md`.
    public var ritmo: RitmoNumero
    /// De dónde sale («Sale de 8 oportunidades»).
    public var fuente: String?
    /// Cifra estimada (se dice).
    public var estimado: Bool

    public init(valor: Double?, texto: String? = nil, ritmo: RitmoNumero, fuente: String? = nil, estimado: Bool = false) {
        self.valor = valor; self.texto = texto; self.ritmo = ritmo; self.fuente = fuente; self.estimado = estimado
    }

    public static let sinDato = LecturaNumero(valor: nil, ritmo: .sinDato)

    /// El valor para enseñar, o `nil` si no hay dato.
    public var textoValor: String? {
        if let texto, !texto.isEmpty { return texto }
        guard let valor, valor.isFinite else { return nil }
        return FormatoBase.cifra(valor)
    }
}

/// Una fila de `Metas.md` del área, con su lectura (pestaña Control y cifra protagonista).
public struct FilaControl: Sendable, Hashable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    public let indicador: String
    /// Celda Meta tal cual (`nil` = vacía: aún no se fijó).
    public let meta: String?
    /// Celda Alerta tal cual (`nil` = vacía).
    public let alerta: String?
    public let porQue: String?
    /// La línea de «## Cómo se mide» de ese código, sin el código.
    public let comoSeMide: String?
    /// Qué cuenta, en una frase llana (el catálogo de números). La fórmula de «Cómo se mide» va aparte, plegada.
    public var enPalabras: String? { CatalogoPrograma.deSerie.kpi(codigo)?.calculo }
    public var lectura: LecturaNumero

    public init(codigo: String, indicador: String, meta: String?, alerta: String?, porQue: String? = nil,
                comoSeMide: String? = nil, lectura: LecturaNumero = .sinDato) {
        self.codigo = codigo; self.indicador = indicador; self.meta = meta; self.alerta = alerta
        self.porQue = porQue; self.comoSeMide = comoSeMide; self.lectura = lectura
    }

    /// Lo que se escribe en la celda Meta al elegir «Sin meta».
    public static let textoSinMeta = "Sin meta"

    /// Se eligió no tener meta (está escrito «Sin meta» o «—»).
    public var sinMetaElegida: Bool {
        guard let meta else { return false }
        return ["sin meta", "—", "-", "–"].contains(TextFolding.fold(meta))
    }

    /// La meta ya se decidió (un valor o «Sin meta»): desde entonces se ve el dato (PLAN §6.5 y §6.7, paso 6:
    /// meta y alerta antes de ver el dato).
    public var metaDecidida: Bool { meta != nil }

    /// Hay una meta con valor (no «Sin meta»).
    public var tieneMeta: Bool { metaDecidida && !sinMetaElegida }

    public var valorVisible: Bool { metaDecidida }

    /// «Sin dato», el valor, o «Oculto hasta fijar la meta» la primera vez.
    public var textoValor: String {
        guard valorVisible else { return "Oculto hasta fijar la meta" }
        return lectura.textoValor ?? "Sin dato"
    }

    /// Meta y alerta para enseñar, con el formato de la app («6.000 €»); para editar, `meta` y `alerta` tal cual.
    public var textoMeta: String { tieneMeta ? Umbral(texto: meta ?? "").textoVisible : "Sin meta" }
    public var textoAlerta: String { alerta.flatMap { $0.isEmpty ? nil : Umbral(texto: $0).textoVisible } ?? "Sin alerta" }

    /// Ritmo para enseñar: sin meta decidida, «Sin meta»; si no, el de la lectura.
    public var ritmo: RitmoNumero {
        guard tieneMeta else { return .sinMeta }
        return lectura.ritmo
    }

    /// Texto para VoiceOver de toda la fila.
    public var etiquetaAccesible: String {
        "\(codigo), \(indicador). Valor: \(textoValor). Meta: \(textoMeta). Alerta: \(textoAlerta). Ritmo: \(ritmo.palabra)."
            + (lectura.fuente.map { " \($0)." } ?? "")
    }
}

/// Estado de un sistema del área (la propiedad `estado` de su ficha, SISTEMAS §2.2).
public enum EstadoSistema: String, Sendable, Hashable, CaseIterable {
    case falta, aMedias, montado, funcionaSinTi

    public init?(leyendo texto: String) {
        switch TextFolding.fold(texto).trimmingCharacters(in: .whitespaces) {
        case "falta": self = .falta
        case "a medias", "amedias": self = .aMedias
        case "montado", "montada": self = .montado
        case "funciona sin ti": self = .funcionaSinTi
        default: return nil
        }
    }

    public var palabra: String {
        switch self {
        case .falta: "Falta"
        case .aMedias: "A medias"
        case .montado: "Montado"
        case .funcionaSinTi: "Funciona sin ti"
        }
    }

    public var estado: TLSEstado {
        switch self {
        case .falta: .sinDato
        case .aMedias: .atencion
        case .montado, .funcionaSinTi: .bien
        }
    }

    /// Cuenta como sistema en uso (para «Más de 3 sistemas suele ser burocracia»).
    public var enUso: Bool { self != .falta }
}

/// Quién hace un paso, en lenguaje llano (SISTEMAS §6.3, la escalera por paso).
public enum ModoFuncion: String, Sendable, Hashable, CaseIterable {
    case loHacesTu, teAyuda, loHaceYRevisas, loHaceSolo, automatico
    /// Lo externo (enviar, publicar, emitir, pagar, escribir a clientes): nunca sube de aquí.
    case siempreConTuOK
    case sinDecidir

    public var palabra: String {
        switch self {
        case .loHacesTu: "Lo haces tú"
        case .teAyuda: "Te ayuda"
        case .loHaceYRevisas: "Lo hace y revisas"
        case .loHaceSolo: "Lo hace solo"
        case .automatico: "Automático"
        case .siempreConTuOK: "Siempre con tu OK"
        case .sinDecidir: "Sin decidir"
        }
    }

    public var simbolo: String {
        switch self {
        case .loHacesTu: "person"
        case .teAyuda: "person.2"
        case .loHaceYRevisas: "eye"
        case .loHaceSolo: "sparkle"
        case .automatico: "gearshape.2"
        case .siempreConTuOK: "lock"
        case .sinDecidir: "questionmark.circle"
        }
    }

    /// Lee la columna Modo de la ficha (texto llano) o el modo de `config.yaml` (manual, asistido…).
    public init(leyendo texto: String) {
        switch TextFolding.fold(texto).trimmingCharacters(in: .whitespaces) {
        case "lo haces tu", "manual": self = .loHacesTu
        case "te ayuda", "asistido": self = .teAyuda
        case "lo hace y revisas", "supervisado": self = .loHaceYRevisas
        case "lo hace solo", "autonomo": self = .loHaceSolo
        case "automatico", "regla", "script": self = .automatico
        case "siempre con tu ok", "con tu ok": self = .siempreConTuOK
        default: self = .sinDecidir
        }
    }
}

/// Un paso (función) de un sistema, en lenguaje llano.
public struct FuncionDeSistema: Sendable, Hashable, Identifiable {
    public var id: String { "\(numero)·\(paso)" }
    public let numero: Int
    public let paso: String
    public let quien: String?
    /// El modo que se enseña (lo sensible, siempre «Siempre con tu OK»).
    public let modo: ModoFuncion
    /// Lo externo: bloqueado en «Siempre con tu OK» en cualquier modo (SISTEMAS §6.2, regla 4).
    public let sensible: Bool
    public let dejaHecho: String?

    public init(numero: Int, paso: String, quien: String?, modo: ModoFuncion, sensible: Bool, dejaHecho: String?) {
        self.numero = numero; self.paso = paso; self.quien = quien
        self.modo = sensible ? .siempreConTuOK : modo
        self.sensible = sensible; self.dejaHecho = dejaHecho
    }

    /// ¿Saca algo fuera? Enviar, publicar, emitir o facturar, pagar y escribir a clientes (SISTEMAS §6.2).
    public static func esSensible(_ texto: String) -> Bool {
        let t = " " + TextFolding.fold(texto) + " "
        return palabrasSensibles.contains { t.contains($0) }
    }

    static let palabrasSensibles = [
        " enviar", " envia ", " envio ", " publicar", " publica ", " emitir", " emite ", " facturar", " pagar",
        " paga ", " transferencia", " escribir al cliente", " escribir a clientes", " escribe al cliente",
        " responder al cliente", " confirmar el cobro", " confirma el cobro",
    ]
}

/// Un activo del área («pieza terminada que sigue produciendo»), ligado a su sistema si lo dice.
public struct ActivoDeArea: Sendable, Hashable, Identifiable {
    public var id: VaultPath { ruta }
    public let ruta: VaultPath
    public let nombre: String
    /// En uso · A revisar · Retirado (texto de la ficha).
    public let estado: String?
    /// Nombre del sistema al que pertenece (`sistema:` de la ficha), si lo dice.
    public let sistema: String?
    public let ejemploBueno: Bool

    public init(ruta: VaultPath, nombre: String, estado: String?, sistema: String?, ejemploBueno: Bool) {
        self.ruta = ruta; self.nombre = nombre; self.estado = estado; self.sistema = sistema; self.ejemploBueno = ejemploBueno
    }
}

/// Un sistema del área: los del catálogo que tocan a esta área (aunque falten) y los que tenga escritos.
public struct SistemaDeArea: Sendable, Hashable, Identifiable {
    public var id: String { codigo ?? nombre }
    public let codigo: String?
    public let nombre: String
    public let estado: EstadoSistema
    public let ficha: VaultPath?
    public let numeroClave: String?
    /// Etapa en la que se instala (catálogo o ficha).
    public let etapa: Int?
    /// Viene de serie en cualquier empresa.
    public let deSerie: Bool
    public let funciones: [FuncionDeSistema]
    public let activos: [ActivoDeArea]
    /// Plantillas de la biblioteca que cuelgan de este sistema.
    public let plantillas: [String]
    public let revisado: LocalDate?

    public init(codigo: String?, nombre: String, estado: EstadoSistema, ficha: VaultPath?, numeroClave: String?,
                etapa: Int?, deSerie: Bool, funciones: [FuncionDeSistema], activos: [ActivoDeArea],
                plantillas: [String], revisado: LocalDate?) {
        self.codigo = codigo; self.nombre = nombre; self.estado = estado; self.ficha = ficha
        self.numeroClave = numeroClave; self.etapa = etapa; self.deSerie = deSerie; self.funciones = funciones
        self.activos = activos; self.plantillas = plantillas; self.revisado = revisado
    }

    /// «3 de 4 sin ti»: pasos que no haces tú, sobre los que tienen modo.
    public var sinTi: (hechos: Int, total: Int)? {
        let conModo = funciones.filter { $0.modo != .sinDecidir }
        guard !conModo.isEmpty else { return nil }
        return (conModo.filter { [.loHaceYRevisas, .loHaceSolo, .automatico].contains($0.modo) }.count, conModo.count)
    }
}

/// Otra área activada hace poco (para avisar al activar: como mucho un área nueva cada 30 días).
public struct ActivacionReciente: Sendable, Hashable {
    public let area: AreaCode
    public let titulo: String
    public let dia: LocalDate
    public let haceDias: Int
}

/// Todo lo que pinta el andamio de un área.
public struct DatosArea: Sendable, Hashable {
    public let area: AreaCode
    public let carpeta: VaultPath
    /// `Área.md` (si existe).
    public let ficha: VaultPath?
    /// «1 · Dirección».
    public let titulo: String
    /// «Ruido en decisiones» (lo que convierte).
    public let convierte: String?
    public let rol: String?
    public let rutaRol: VaultPath?
    /// Quien ocupa el rol: una persona o «Comercial (asistente)». `nil` = sin ocupante.
    public let ocupante: String?
    public let pregunta: String?
    public let fase: FaseArea
    public let etapa: Int?
    /// El asistente del área («Mika», «Contable»…), para «Pedir a …».
    public let asistente: String
    /// Código del número clave (`numero_clave` del área, el primero del rol o el primero de `Metas.md`).
    public let numeroClave: String?
    public let control: [FilaControl]
    /// `1 · Dirección/Metas.md` (si existe).
    public let metas: VaultPath?
    public let sistemas: [SistemaDeArea]
    /// Activos que no dicen su sistema (o uno que el área no tiene).
    public let activosSueltos: [ActivoDeArea]
    public let activadaEl: LocalDate?
    /// La última otra área activada hace menos de 30 días.
    public let activacionReciente: ActivacionReciente?
    public let hoy: LocalDate

    public init(area: AreaCode, carpeta: VaultPath, ficha: VaultPath?, titulo: String, convierte: String?, rol: String?,
                rutaRol: VaultPath?, ocupante: String?, pregunta: String?, fase: FaseArea, etapa: Int?, asistente: String,
                numeroClave: String?, control: [FilaControl], metas: VaultPath?, sistemas: [SistemaDeArea],
                activosSueltos: [ActivoDeArea], activadaEl: LocalDate?, activacionReciente: ActivacionReciente?,
                hoy: LocalDate) {
        self.area = area; self.carpeta = carpeta; self.ficha = ficha; self.titulo = titulo; self.convierte = convierte
        self.rol = rol; self.rutaRol = rutaRol; self.ocupante = ocupante; self.pregunta = pregunta; self.fase = fase
        self.etapa = etapa; self.asistente = asistente; self.numeroClave = numeroClave; self.control = control
        self.metas = metas; self.sistemas = sistemas; self.activosSueltos = activosSueltos
        self.activadaEl = activadaEl; self.activacionReciente = activacionReciente; self.hoy = hoy
    }

    /// La fila del número clave (si está en `Metas.md`).
    public var filaClave: FilaControl? {
        guard let numeroClave else { return nil }
        return control.first { $0.codigo == numeroClave }
    }

    /// Alguna fila del área tiene meta decidida.
    public var hayMetas: Bool { control.contains { $0.metaDecidida } }

    /// El ritmo del área: el de su número más atrasado.
    public var ritmo: RitmoNumero { RitmoNumero.deArea(control.map(\.ritmo)) }

    /// En las etapas 1 y 2, Control se sustituye por «Medir esto llega en la etapa 3», salvo que ya haya metas.
    public var controlSustituido: Bool {
        guard let etapa else { return false }
        return etapa <= 2 && !hayMetas
    }

    /// Pestañas que se enseñan: en reposo, solo Resumen.
    public var pestanas: [PestanaArea] { fase == .reposo ? [.resumen] : PestanaArea.allCases }

    /// «Convierte ruido en decisiones».
    public var fraseConvierte: String? {
        guard let c = convierte?.trimmingCharacters(in: .whitespaces), !c.isEmpty else { return nil }
        let primera = c.prefix(1).lowercased() + c.dropFirst()
        return TextFolding.fold(c).hasPrefix("convierte") ? c : "Convierte \(primera)"
    }

    /// Sistemas en uso (montados, a medias o que funcionan sin ti).
    public var sistemasEnUso: Int { sistemas.filter { $0.estado.enUso }.count }

    /// Lo que ve el andamio en las pantallas de Operación y Resumen (sin los números).
    public var contexto: ContextoArea {
        ContextoArea(area: area, carpeta: carpeta, titulo: titulo, fase: fase, etapa: etapa, rol: rol, ocupante: ocupante,
                     soloRol: false, hoy: hoy, control: control)
    }
}

/// Lo que reciben las pantallas de Operación y el Resumen de un área (huecos de la fase de pantallas).
public struct ContextoArea: Sendable, Hashable {
    public let area: AreaCode
    public let carpeta: VaultPath
    public let titulo: String
    public let fase: FaseArea
    public let etapa: Int?
    public let rol: String?
    public let ocupante: String?
    /// «Ver solo lo de este rol» encendido: enseñar solo lo que lleva `rol` (o su ocupante).
    public var soloRol: Bool
    /// El día de la carpeta (en el ejemplo, su día fijo).
    public let hoy: LocalDate
    /// Los números del área, con su lectura (para las cifras de cada pantalla).
    public let control: [FilaControl]

    public init(area: AreaCode, carpeta: VaultPath, titulo: String, fase: FaseArea, etapa: Int?, rol: String?,
                ocupante: String?, soloRol: Bool, hoy: LocalDate, control: [FilaControl]) {
        self.area = area; self.carpeta = carpeta; self.titulo = titulo; self.fase = fase; self.etapa = etapa
        self.rol = rol; self.ocupante = ocupante; self.soloRol = soloRol; self.hoy = hoy; self.control = control
    }

    /// Contexto mínimo de un área sin leer (mientras carga).
    public static func vacio(_ area: AreaCode, carpeta: VaultPath, hoy: LocalDate) -> ContextoArea {
        ContextoArea(area: area, carpeta: carpeta, titulo: area.etiquetaNumerada, fase: .sinEstado, etapa: nil, rol: nil,
                     ocupante: nil, soloRol: false, hoy: hoy, control: [])
    }

    /// La lectura de un código del área.
    public func numero(_ codigo: String) -> FilaControl? { control.first { $0.codigo == codigo } }
}
