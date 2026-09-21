import Testing
import SwiftUI
import PulseCore
@testable import PulseCheckout

// Libro: cap. 10, §10.2 — exit test (Swift 6.2+).
//
// H9: DESHABILITADO. Dos problemas encontrados al verificar, ninguno resuelto todavía:
//
// 1. Tal como está escrito, este test nunca ejercería el camino que dice probar: `CheckoutHost`
//    inyecta `flags` con `.environment(flags)` incondicionalmente, así que `CheckoutView` recibe
//    siempre el objeto, en `PULSE_BUG` y fuera de él. Haría falta una vista mínima que NO reciba
//    la inyección, construida aparte de `CheckoutHost`.
// 2. Incluso arreglando (1), la ejecución real de `#expect(processExitsWith:)` contra el
//    `fatalError` de SwiftUI no contuvo el fallo: el bundle de tests completo murió con SIGTRAP
//    y se perdieron los resultados de las suites vecinas en esa ejecución. No sabemos si falta
//    una condición de esta configuración o si `ImageRenderer` es el mecanismo equivocado para
//    forzar la evaluación del `body` dentro del proceso hijo.
//
// El capítulo 10 (§10.2) refleja este estado como pendiente de verificar, no como resuelto.
// No reactivar sin: (a) una vista de prueba que de verdad omita la inyección, y (b) confirmar en
// una suite AISLADA (no junto a otros tests) que el exit test contiene el fallo sin tumbar el
// proceso.
@Suite("FeatureFlags en el entorno", .disabled("H9: exit test no verificado, ver comentario"))
struct FeatureFlagsTests {

    struct SinInyeccion: View {
        var body: some View { CheckoutView(orderID: UUID(), carrito: .prueba(importe: 20)) }
    }

    @Test("Leer FeatureFlags no opcional sin inyección aborta")
    func sinInyeccionAborta() async {
        #if PULSE_BUG
        await #expect(processExitsWith: .failure) {
            _ = await MainActor.run { ImageRenderer(content: SinInyeccion()).cgImage }
        }
        #endif
    }
}
