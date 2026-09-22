import Testing
import Observation
import Foundation
import PulseCore
@testable import PulseFeed

nonisolated struct RepoStub: FeedRepository {
    let lista: [Articulo]
    func articulos() async throws -> [Articulo] { lista }
}

extension Tag { @Tag static var bug: Self }

// Libro: cap. 8, §8.8, tras H10.
//
// Lo que se prueba NO es "reasignar lo mismo no notifica": eso lo garantiza Observation y pasaría
// en las dos variantes. Se prueba que un ping que cambia un campo que la interfaz NO muestra
// (`vistas`) no invalide a los observadores. cap8-bug publica el payload crudo → notifica → falla.
@Suite("FeedModel", .tags(.bug))
@MainActor
struct FeedModelTests {

    private func articulosBase() -> [Articulo] {
        [Articulo(titulo: "A", vistas: 10), Articulo(titulo: "B", vistas: 20)]
    }

    private func observar(_ modelo: FeedModel, mutar: @escaping @MainActor () async -> Void) async throws -> Bool {
        let notificado = Notificado()
        withObservationTracking {
            #if PULSE_BUG
            _ = modelo.articulos
            #else
            _ = modelo.visibles
            #endif
        } onChange: {
            Task { @MainActor in notificado.marcar() }
        }
        await mutar()
        try await Task.sleep(for: .milliseconds(50))
        return notificado.ocurrio
    }

    @Test("Un ping que solo cambia campos invisibles no invalida")
    func pingDeContadoresNoInvalida() async throws {
        let base = articulosBase()
        let modelo = FeedModel(repositorio: RepoStub(lista: base))
        await modelo.aplicar(base)

        var conMasVistas = base
        conMasVistas[0].vistas += 1                         // El servidor cuenta una visita más
        conMasVistas[1].vistas += 7

        let notificado = try await observar(modelo) { await modelo.aplicar(conMasVistas) }
        #expect(notificado == false)
    }

    // P2 de la revisión externa: si la proyección tomara `Date.now` en cada ping, dos payloads
    // iguales a los dos lados de un umbral de formato relativo ("ahora" → "hace 1 min") darían
    // textos distintos y la vista se invalidaría igual. Este test cruza el umbral a propósito:
    // los 90 segundos son de la fecha de referencia, no de espera real.
    @Test("Un ping que cruza el umbral del minuto no invalida por sí solo")
    func umbralDelMinutoNoInvalida() async throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let base = [Articulo(titulo: "A", fecha: t0.addingTimeInterval(-30), vistas: 10)]
        let modelo = FeedModel(repositorio: RepoStub(lista: base), referenciaTemporal: t0)
        await modelo.aplicar(base)

        var conMasVistas = base
        conMasVistas[0].vistas += 1

        // El reloj de pared avanza 90 s, pero el de presentación no: el ping no debe invalidar.
        let notificado = try await observar(modelo) { await modelo.aplicar(conMasVistas) }
        #expect(notificado == false)
    }

    // Control: el reloj de presentación sí avanza cuando lo movemos a propósito.
    @Test("Refrescar los textos relativos sí invalida")
    func refrescarSiInvalida() async throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let base = [Articulo(titulo: "A", fecha: t0.addingTimeInterval(-30), vistas: 10)]
        let modelo = FeedModel(repositorio: RepoStub(lista: base), referenciaTemporal: t0)
        await modelo.aplicar(base)

        let notificado = try await observar(modelo) {
            await modelo.refrescarTextosRelativos(t0.addingTimeInterval(90))
        }
        #expect(notificado)
    }

    @Test("Un cambio que la interfaz sí muestra invalida")
    func cambioVisibleInvalida() async throws {
        let base = articulosBase()
        let modelo = FeedModel(repositorio: RepoStub(lista: base))
        await modelo.aplicar(base)

        var conTituloNuevo = base
        conTituloNuevo[0].titulo = "A (editado)"

        let notificado = try await observar(modelo) { await modelo.aplicar(conTituloNuevo) }
        #expect(notificado)                                 // Control del aparato de medida
    }
}

@MainActor
final class Notificado {
    private(set) var ocurrio = false
    func marcar() { ocurrio = true }
}
