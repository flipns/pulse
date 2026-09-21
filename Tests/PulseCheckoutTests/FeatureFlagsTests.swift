import Testing
import SwiftUI
import PulseCore
@testable import PulseCheckout

// Libro: cap. 5, §5.6 y cap. 10, §10.2 — exit tests (Swift 6.2+). H9, cerrado.
//
// Vista mínima que NO recibe FeatureFlags del entorno. No usar CheckoutHost aquí: inyecta
// siempre `.environment(flags)` y nunca ejercería el camino sin inyección.
struct VistaSinInyeccion: View {
    var body: some View { CheckoutView(orderID: UUID(), carrito: .prueba(importe: 20)) }
}

@Suite("FeatureFlags en el entorno", .tags(.bug))
struct FeatureFlagsTests {

    // Caso discriminante del capítulo 5:
    //   cap5-fix: `@Environment(FeatureFlags.self) var x: FeatureFlags?` + `.porDefecto`
    //             → sin inyección, la vista se evalúa y el hijo termina bien → PASA.
    //   cap5-bug: `@Environment(FeatureFlags.self) var flags` (no opcional)
    //             → sin inyección, SwiftUI llama a fatalError → el hijo aborta → FALLA.
    // El fallo queda contenido en el proceso hijo: el resto de suites sigue ejecutándose.
    @Test("Sin inyección, la vista no aborta")
    func sinInyeccionNoAborta() async {
        await #expect(processExitsWith: .success) {
            _ = await MainActor.run { ImageRenderer(content: VistaSinInyeccion()).cgImage }
        }
    }

    // Control del aparato de medida (§10.3): la misma vista CON inyección termina bien en las
    // dos variantes. Si este test fallara, el problema sería ImageRenderer en el proceso hijo,
    // no @Environment, y el test anterior no demostraría nada.
    @Test("Con inyección, la vista no aborta (control)")
    func conInyeccionNoAborta() async {
        await #expect(processExitsWith: .success) {
            _ = await MainActor.run {
                ImageRenderer(content: VistaSinInyeccion().environment(FeatureFlags.porDefecto)).cgImage
            }
        }
    }
}
