import SwiftUI
import PulseCore

// Libro: cap. 2, §2.9 — el estado de producto vive fuera de la fila, indexado por id
@Observable @MainActor
public final class EstadoFeed {
    public var desplegadas: Set<Articulo.ID> = []
    public init() {}

    public func binding(desplegada id: Articulo.ID) -> Binding<Bool> {
        Binding(
            get: { self.desplegadas.contains(id) },
            set: { desplegada in
                if desplegada { self.desplegadas.insert(id) } else { self.desplegadas.remove(id) }
            }
        )
    }
}
