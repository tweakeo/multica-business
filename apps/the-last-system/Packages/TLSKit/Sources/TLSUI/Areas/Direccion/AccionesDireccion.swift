import Foundation
import TLSCore
import TLSDesign

/// Lo que escribe la Operación de Dirección, siempre como la persona de la sesión, por el dominio (invariantes,
/// eventos y reglas) y con Deshacer. Cada función devuelve el texto del error (o `nil` si se escribió).
@MainActor
enum AccionesDireccion {
    /// La foto de la carpeta al día (para preparar un plan).
    static func fotoActual(_ sesion: VaultSession) async -> VaultSnapshot? {
        let almacen = AlmacenRelaciones.de(sesion)
        await almacen.actualizar()
        return almacen.foto
    }

    /// El texto de un error de escritura (el aviso de la sesión ya lo enseña también).
    static func texto(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    /// Mueve un proyecto (solo `inicio` y `fin`); si cae en fin de semana, el dominio lo corre al lunes (ENT-04).
    static func mover(_ b: BarraCronograma, inicio: LocalDate, fin: LocalDate, sesion: VaultSession,
                      deshacer: UndoManager?) async -> String? {
        let hoy = sesion.hoy
        let aviso = "«\(b.nombre)» va del \(OperacionComun.fecha(inicio, hoy: hoy)) al \(OperacionComun.fecha(fin, hoy: hoy))"
        do {
            let r = try await sesion.escribirConDominio(Cronograma.comando(b, inicio: inicio, fin: fin), aviso: aviso, deshacer: deshacer)
            return conflicto(r.escritura, b.nombre)
        } catch {
            return texto(error)
        }
    }

    /// DIR-03 · «Colgar de un objetivo»: escribe el enlace al objetivo (y quita «Seguir sin objetivo» si estaba).
    static func colgar(_ b: BarraCronograma, de objetivo: VaultPath, sesion: VaultSession, deshacer: UndoManager?) async -> String? {
        guard let foto = await fotoActual(sesion) else { return "No pude leer la carpeta." }
        let (poner, quitar) = Invariantes(snapshot: foto).colgar(b.ruta, de: objetivo)
        let nombre = foto.frontmatter(objetivo).text("titulo") ?? objetivo.stem
        do {
            let r = try await sesion.escribirConDominio(.cambiarPropiedades(b.ruta, poner: poner, quitar: quitar),
                                                        aviso: "«\(b.nombre)» cuelga de «\(nombre)»", deshacer: deshacer)
            return conflicto(r.escritura, b.nombre)
        } catch {
            return texto(error)
        }
    }

    /// DIR-03 · «Seguir sin objetivo»: `sin_objetivo: true` en el proyecto (deja de avisar).
    static func seguirSinObjetivo(_ b: BarraCronograma, sesion: VaultSession, deshacer: UndoManager?) async -> String? {
        do {
            let r = try await sesion.escribirConDominio(
                .cambiarPropiedades(b.ruta, poner: [Property(key: Invariantes.sinObjetivo, value: .bool(true))], quitar: []),
                aviso: "«\(b.nombre)» sigue sin objetivo", deshacer: deshacer)
            return conflicto(r.escritura, b.nombre)
        } catch {
            return texto(error)
        }
    }

    /// «Registrar decisión»: una línea nueva en `Decisiones.md` (lo de antes no se toca).
    static func registrar(_ d: NuevaDecision, sesion: VaultSession, deshacer: UndoManager?) async -> String? {
        guard let foto = await fotoActual(sesion) else { return "No pude leer la carpeta." }
        do {
            let (plan, _) = try RegistroDecisiones.anadir(d, en: foto, autor: sesion.autor)
            let r = try await sesion.escribirConDominio(plan: plan, aviso: "Registraste «\(d.decision)»", deshacer: deshacer)
            return conflicto(r.escritura, "Decisiones.md")
        } catch {
            return texto(error)
        }
    }

    /// «Plan de 4 semanas para el cuello»: con tu OK, las tareas de las semanas elegidas en un solo paso.
    static func crearPlan(_ plan: PlanCuello, semanas: Set<Int>, sesion: VaultSession, deshacer: UndoManager?) async -> String? {
        guard let foto = await fotoActual(sesion) else { return "No pude leer la carpeta." }
        let nuevas = plan.tareas(semanas, persona: sesion.persona, autor: sesion.autor)
        do {
            guard let lote = try LoteDeTareas.preparar(nuevas, snapshot: foto, autor: sesion.autor,
                                                       descripcion: "Plan de 4 semanas para el cuello") else { return nil }
            let n = lote.rutas.count
            let r = try await sesion.escribir(plan: lote.plan,
                                              aviso: "Creé \(n == 1 ? "1 tarea" : "\(n) tareas") del plan para \(plan.area.etiquetaNumerada)",
                                              deshacer: deshacer)
            return conflicto(r, plan.area.etiquetaNumerada)
        } catch {
            return texto(error)
        }
    }

    static func conflicto(_ r: WriteResult, _ que: String) -> String? {
        if case .conflicto = r.estado { return "«\(que)» cambió fuera a la vez. Revísalo en Revisar." }
        return nil
    }
}
