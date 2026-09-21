import Foundation

// Libro: cap. 9, §9.2 — tipos que cruzan fronteras de aislamiento.
//
// `nonisolated` en la declaración del tipo NO es decorativo: con Default Actor Isolation = MainActor,
// todo el módulo (incluidos los miembros de una struct de datos) queda aislado al MainActor, y un
// `actor` no puede llamar a su inicializador. `Sendable` dice que el valor puede cruzar la frontera;
// `nonisolated` dice que puedes fabricarlo y leerlo al otro lado. Hacen falta los dos. (H1)
nonisolated public struct Producto: Sendable, Identifiable, Equatable, Hashable, Codable {
    public let id: String
    public let nombre: String
    public let precioCentimos: Int

    public init(id: String, nombre: String, precioCentimos: Int) {
        self.id = id; self.nombre = nombre; self.precioCentimos = precioCentimos
    }

    public static let prueba = Producto(id: "p1", nombre: "Auriculares", precioCentimos: 4999)
}

// Libro: cap. 2, §2.9 y cap. 8, §8.8
nonisolated public struct Articulo: Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var titulo: String
    public var resumen: String
    public var fecha: Date
    public var esDestacado: Bool
    public var oculto: Bool
    /// Contador de visitas del servidor. Cambia con cada ping y **la interfaz no lo muestra**:
    /// es el campo que hace que el payload crudo difiera siempre (cap. 8, §8.8, H10).
    public var vistas: Int

    public init(id: UUID = UUID(), titulo: String, resumen: String = "", fecha: Date = .now,
                esDestacado: Bool = false, oculto: Bool = false, vistas: Int = 0) {
        self.id = id; self.titulo = titulo; self.resumen = resumen; self.fecha = fecha
        self.esDestacado = esDestacado; self.oculto = oculto; self.vistas = vistas
    }
}

// Libro: cap. 8, §8.4 — la proyección que la UI consume. No incluye `vistas` (H10).
nonisolated public struct ArticuloPresentado: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let titulo: String
    public let resumen: String
    public let fechaRelativa: String
    public let destacada: Bool

    /// `ahora` y `formateador` no son decorativos.
    ///
    /// `ahora`: sin una fecha de referencia explícita, el texto depende del reloj del sistema y
    /// dos proyecciones del mismo artículo pueden no ser iguales. El caso de §8.8 compara
    /// proyecciones para decidir si notificar, así que necesita que sean deterministas.
    ///
    /// `formateador`: construir un `RelativeDateTimeFormatter` por elemento es el antipatrón de
    /// §8.4. Se recibe uno ya construido en lugar de compartir un global, porque los formateadores
    /// de Foundation no son `Sendable` y un global compartido sería un *data race* en cuanto la
    /// proyección se hiciera desde `@concurrent` (§8.5). Ver `proyectar(_:ahora:)`.
    public init(_ a: Articulo, ahora: Date, formateador: RelativeDateTimeFormatter) {
        id = a.id
        titulo = a.titulo
        resumen = a.resumen
        destacada = a.esDestacado
        fechaRelativa = formateador.localizedString(for: a.fecha, relativeTo: ahora)
    }

    /// Proyecta una colección con **un solo** formateador y una sola fecha de referencia.
    /// Es la forma que usa `FeedModel` (§8.8): determinista y sin construir un formateador por fila.
    public static func proyectar(_ crudos: [Articulo], ahora: Date = .now) -> [ArticuloPresentado] {
        let formateador = RelativeDateTimeFormatter()
        return crudos.map { ArticuloPresentado($0, ahora: ahora, formateador: formateador) }
    }
}

// Libro: cap. 10, §10.2 — función pura parametrizable
nonisolated public struct Precio: Sendable, Equatable {
    public let centimos: Int
    public init(centimos: Int) { self.centimos = centimos }

    public func texto(locale: Locale) -> String {
        (Decimal(centimos) / 100).formatted(.currency(code: "EUR").locale(locale))
    }
}

nonisolated public extension Locale { static let es = Locale(identifier: "es_ES") }
