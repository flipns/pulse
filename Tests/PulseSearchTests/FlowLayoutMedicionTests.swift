import Testing
import SwiftUI
@testable import PulseSearch
#if canImport(ViewInspector)
import ViewInspector
#endif

// Libro: cap. 7, §7.3 y §7.9 (V9). cap7-bug falla, cap7-fix pasa.
// (El tag `.bug` ya está declarado en OrdenRespuestasTests.swift, en este mismo módulo.)
@Suite("Mediciones del FlowLayout", .tags(.bug), .serialized)
@MainActor
struct FlowLayoutMedicionTests {

    #if canImport(ViewInspector)
    @Test("El layout no vuelve a medir las etiquetas en cada llamada")
    func noRemideEnCadaLlamada() async throws {
        let etiquetas = TagCloudView.sesenta
        RegistroLayout.reiniciar()
        ViewHosting.host(view: TagCloudView(etiquetas: etiquetas).frame(width: 390))
        defer { ViewHosting.expel() }
        try await Task.sleep(for: .milliseconds(150))

        let c = RegistroLayout.actual
        // Los números van al log: son el dato que §7.9 cita ("cuatro llamadas por pase").
        print("V9 — etiquetas: \(etiquetas.count) · sizeThatFits: \(c.sizeThatFits) · placeSubviews: \(c.placeSubviews) · mediciones de subvistas: \(c.medicionesDeSubvistas)")

        // Control: el layout se ha ejecutado de verdad.
        #expect(c.sizeThatFits > 0 && c.placeSubviews > 0, "el layout no llegó a ejecutarse")

        // El caso. Sin caché, cada llamada mide las 60 etiquetas:
        //   mediciones == etiquetas × (sizeThatFits + placeSubviews).
        // Con caché, las mide al crear o actualizar la caché, no en cada llamada.
        let sinCache = etiquetas.count * (c.sizeThatFits + c.placeSubviews)
        #expect(c.medicionesDeSubvistas < sinCache,
                "mide en cada llamada: \(c.medicionesDeSubvistas) mediciones = \(etiquetas.count) × \(c.sizeThatFits + c.placeSubviews) llamadas")
    }
    #endif
}
