import Foundation

// F5 · corrector (revisión de experiencia, P1-2 y P2-5): las herramientas de otros programas llegan con nombres en
// inglés y técnicos (`send_sms`, `contacts_list`, `contactId`). Para una persona no técnica se dicen en llano, por su
// verbo y su objeto («Mandar un SMS», «Ver contactos»); el nombre original queda solo en «Detalle técnico».

/// Nombres en llano para herramientas y datos de otros programas.
public enum NombresLlanos {
    /// Palabras de un nombre técnico: `send_sms` / `createContact` / `contacts-list` → `["send", "sms"]`…
    public static func palabras(_ s: String) -> [String] {
        var out: [String] = []
        var actual = ""
        for ch in s {
            if ch == "_" || ch == "-" || ch == " " || ch == "." || ch == "/" {
                if !actual.isEmpty { out.append(actual); actual = "" }
            } else if ch.isUppercase, let u = actual.last, u.isLowercase || u.isNumber {
                out.append(actual); actual = String(ch)
            } else {
                actual.append(ch)
            }
        }
        if !actual.isEmpty { out.append(actual) }
        return out.map { $0.lowercased() }
    }

    /// Verbos: lo que hace, en infinitivo.
    static let verbos: [String: String] = [
        "send": "Mandar", "post": "Mandar", "reply": "Responder", "forward": "Reenviar",
        "create": "Crear", "add": "Añadir", "new": "Crear", "insert": "Añadir", "upsert": "Crear o cambiar",
        "update": "Cambiar", "edit": "Cambiar", "patch": "Cambiar", "set": "Cambiar", "modify": "Cambiar", "tag": "Etiquetar",
        "delete": "Borrar", "remove": "Quitar", "archive": "Archivar", "cancel": "Cancelar",
        "list": "Ver", "get": "Ver", "read": "Ver", "fetch": "Ver", "retrieve": "Ver", "show": "Ver",
        "search": "Buscar", "find": "Buscar", "lookup": "Buscar", "query": "Buscar",
        "publish": "Publicar", "schedule": "Programar", "book": "Reservar",
        "pay": "Pagar", "charge": "Cobrar", "refund": "Devolver", "invoice": "Facturar", "transfer": "Transferir",
        "email": "Mandar", "sms": "Mandar", "message": "Mandar",
    ]

    /// Objetos: (singular con artículo, plural).
    static let objetos: [String: (uno: String, varios: String)] = [
        "sms": ("un SMS", "SMS"), "email": ("un correo", "correos"), "emails": ("un correo", "correos"),
        "mail": ("un correo", "correos"), "message": ("un mensaje", "mensajes"), "messages": ("un mensaje", "mensajes"),
        "contact": ("un contacto", "contactos"), "contacts": ("un contacto", "contactos"),
        "lead": ("un interesado", "interesados"), "leads": ("un interesado", "interesados"),
        "customer": ("un cliente", "clientes"), "customers": ("un cliente", "clientes"),
        "client": ("un cliente", "clientes"), "clients": ("un cliente", "clientes"),
        "opportunity": ("una oportunidad", "oportunidades"), "opportunities": ("una oportunidad", "oportunidades"),
        "deal": ("una oportunidad", "oportunidades"), "deals": ("una oportunidad", "oportunidades"),
        "appointment": ("una cita", "citas"), "appointments": ("una cita", "citas"),
        "booking": ("una reserva", "reservas"), "bookings": ("una reserva", "reservas"),
        "event": ("un evento", "eventos"), "events": ("un evento", "eventos"),
        "invoice": ("una factura", "facturas"), "invoices": ("una factura", "facturas"),
        "payment": ("un pago", "pagos"), "payments": ("un pago", "pagos"), "charge": ("un cobro", "cobros"),
        "charges": ("un cobro", "cobros"), "refund": ("una devolución", "devoluciones"),
        "subscription": ("una suscripción", "suscripciones"), "subscriptions": ("una suscripción", "suscripciones"),
        "order": ("un pedido", "pedidos"), "orders": ("un pedido", "pedidos"),
        "product": ("un producto", "productos"), "products": ("un producto", "productos"),
        "note": ("una nota", "notas"), "notes": ("una nota", "notas"), "task": ("una tarea", "tareas"),
        "tasks": ("una tarea", "tareas"), "tag": ("una etiqueta", "etiquetas"), "tags": ("una etiqueta", "etiquetas"),
        "conversation": ("una conversación", "conversaciones"), "conversations": ("una conversación", "conversaciones"),
        "form": ("un formulario", "formularios"), "forms": ("un formulario", "formularios"),
        "submission": ("una respuesta de formulario", "respuestas de formularios"),
        "submissions": ("una respuesta de formulario", "respuestas de formularios"),
        "post": ("una publicación", "publicaciones"), "posts": ("una publicación", "publicaciones"),
        "calendar": ("un calendario", "calendarios"), "calendars": ("un calendario", "calendarios"),
        "metrics": ("las métricas", "métricas"), "stats": ("las estadísticas", "estadísticas"),
        "balance": ("el saldo", "saldos"), "user": ("un usuario", "usuarios"), "users": ("un usuario", "usuarios"),
    ]

    /// «Mandar un SMS», «Ver contactos», «Cambiar un contacto». Si no se reconoce, el nombre tal cual entre comillas.
    public static func accion(_ nombre: String) -> String {
        let p = palabras(nombre)
        guard !p.isEmpty else { return "«\(nombre)»" }
        let verboIdx = p.firstIndex { verbos[$0] != nil && objetos[$0] == nil } ?? p.firstIndex { verbos[$0] != nil }
        let objetoIdx = p.indices.last { i in objetos[p[i]] != nil && i != verboIdx }
        switch (verboIdx, objetoIdx) {
        case let (v?, o?):
            let verbo = verbos[p[v]]!
            let obj = objetos[p[o]]!
            let ver = verbo == "Ver" || verbo == "Buscar"
            let plural = ver && ((p[o].hasSuffix("s") && p[o] != "sms") || p[v] == "list" || p[v] == "search")
            return verbo + " " + (plural ? obj.varios : obj.uno)
        case let (v?, nil):
            // `send_sms`, `email`: el verbo ya dice el objeto.
            if let o = objetos[p[v]], verbos[p[v]] == "Mandar" { return "Mandar " + o.uno }
            return verbos[p[v]]! + (p.count > 1 ? " «\(p.filter { $0 != p[v] }.joined(separator: " "))»" : "")
        case let (nil, o?):
            // `contacts` a secas: leer.
            return "Ver " + objetos[p[o]]!.varios
        default:
            return "«\(nombre)»"
        }
    }

    /// «Mandar un SMS desde GoHighLevel».
    public static func accion(_ nombre: String, programa: String?) -> String {
        guard let programa, !programa.isEmpty else { return accion(nombre) }
        return accion(nombre) + " desde " + programa
    }

    /// Datos: `contactId` → «Contacto»; `message` → «Mensaje»; si no se reconoce, sus palabras («Custom field»).
    public static func dato(_ clave: String) -> String {
        let p = palabras(clave).filter { $0 != "id" || palabras(clave).count == 1 }
        let conocidas: [String: String] = [
            "id": "Identificador", "contact": "Contacto", "lead": "Interesado", "customer": "Cliente", "client": "Cliente",
            "to": "Para", "from": "De", "phone": "Teléfono", "mobile": "Móvil", "email": "Correo", "mail": "Correo",
            "message": "Mensaje", "body": "Mensaje", "text": "Texto", "content": "Contenido", "subject": "Asunto",
            "name": "Nombre", "first": "Nombre", "last": "Apellidos", "company": "Empresa", "amount": "Importe",
            "currency": "Moneda", "date": "Fecha", "time": "Hora", "start": "Empieza", "end": "Acaba", "tag": "Etiqueta",
            "tags": "Etiquetas", "note": "Nota", "status": "Estado", "stage": "Etapa", "value": "Valor", "url": "Dirección",
            "description": "Descripción", "title": "Título", "type": "Tipo", "channel": "Canal", "source": "Origen",
            "opportunity": "Oportunidad", "invoice": "Factura", "quantity": "Cantidad", "price": "Precio",
            "calendar": "Calendario", "appointment": "Cita", "location": "Lugar", "conversation": "Conversación",
            // Claves que ya vienen en español (sin tildes): con su tilde.
            "telefono": "Teléfono", "movil": "Móvil", "direccion": "Dirección", "descripcion": "Descripción",
            "titulo": "Título", "mensaje": "Mensaje", "importe": "Importe", "nombre": "Nombre", "correo": "Correo",
        ]
        guard !p.isEmpty else { return clave }
        if p.count == 1, let c = conocidas[p[0]] { return c }
        if let ultima = p.last, let c = conocidas[ultima], p.count == 2, let primera = conocidas[p[0]] {
            // `first_name` → «Nombre»; `contact_email` → «Correo del contacto».
            if p[0] == "first" || p[0] == "last" { return conocidas[p[0]]! }
            return c + " de " + primera.lowercased()
        }
        let t = p.map { conocidas[$0]?.lowercased() ?? $0 }.joined(separator: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}
