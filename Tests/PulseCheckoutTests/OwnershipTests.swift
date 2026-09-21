import Testing
import SwiftUI
import Foundation
import PulseCore
import PulseCart
@testable import PulseCheckout
#if canImport(ViewInspector)
import ViewInspector
#endif

extension Tag { @Tag static var bug: Self }

// Libro: cap. 10, §10.6.
//
// H6: comparar identidades con `inspect().actualView()` sin `ViewHosting` NO funciona: cada
// inspección construye la struct de cero y lee el `@State` fuera de cualquier pase de render.
// H11: contar instancias tampoco sirve como criterio, porque con `@State` asignado en el `init`
// el inicializador se ejecuta en cada reconstrucción de la struct aunque el estado se conserve
// (capítulo 3, §3.3). Lo que distingue `fix` de `bug` es QUÉ INSTANCIA usa la vista, registrada
// desde el propio `body` (ver `RegistroCheckout` en CheckoutModel.swift / CheckoutView.swift).
@Suite("Ownership del modelo de checkout", .tags(.bug), .serialized)
@MainActor
struct OwnershipTests {

    #if canImport(ViewInspector)
    @Test("La vista sigue usando el mismo modelo cuando el padre se actualiza")
    func mismoModeloEnUso() async throws {
        RegistroCheckout.reiniciar()

        let flags = FeatureFlags(bannerPromo: false)
        // CheckoutHost lee flags.bannerPromo en su propio body: es lo que hace que cambiar el flag
        // reconstruya su struct y, con ella, la de CheckoutView. Sin esa lectura real, el bug no
        // se dispara (ver el comentario en CheckoutHost).
        ViewHosting.host(view: CheckoutHost(flags: flags))
        defer { ViewHosting.expel() }
        try await Task.sleep(for: .milliseconds(50))          // Deja que SwiftUI monte el primer render

        let primero = try #require(RegistroCheckout.enUso)
        let construidosAlPrincipio = RegistroCheckout.creados

        for _ in 0..<5 {
            flags.bannerPromo.toggle()                        // El padre se actualiza
            try await Task.sleep(for: .milliseconds(30))
        }

        #expect(RegistroCheckout.enUso == primero,
                "modelos construidos: \(construidosAlPrincipio) → \(RegistroCheckout.creados)")
    }
    #endif
}
