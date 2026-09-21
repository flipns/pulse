import Testing
import SwiftUI
import PulseCore
@testable import PulseFeed

// Libro: cap. 2, §2.11 — experimento índice frente a id estable (V2).
// Requiere un host de vista para observar el estado por fila; aquí queda documentado el escenario
// y la aserción que debe cumplirse. Implementación pendiente de V2.
@Suite("Identidad en ForEach", .disabled("Pendiente de host de vista (V2)"))
struct IdentidadTests {
    @Test("Insertar al principio no mueve el estado de despliegue a otra fila")
    @MainActor
    func insertarNoMueveEstado() {
        // 1. Feed con [A, B, C]; desplegar B.
        // 2. Insertar Promoción al principio.
        // 3. Con ForEach(items.indices): la fila desplegada es ahora A (índice 1). BUG.
        //    Con ForEach(items):         la fila desplegada sigue siendo B.       FIX.
    }
}
