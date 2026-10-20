import Foundation
import PulseCore
import PulseFeed

enum DatosDePrueba {
    /// 400 artículos con fechas escalonadas, algunos destacados y algunos ocultos.
    static func articulos(_ n: Int = 400) -> [Articulo] {
        let ahora = Date.now
        return (0..<n).map { i in
            Articulo(
                titulo: "Artículo \(i)",
                resumen: "Resumen del artículo \(i).",
                fecha: ahora.addingTimeInterval(-Double(i) * 600),
                esDestacado: i % 17 == 0,
                oculto: i % 23 == 0,
                vistas: i * 3
            )
        }
    }
}

// nonisolated: el protocolo es Sendable y el feed lo llama desde fuera del MainActor (H1).
nonisolated struct RepositorioDePrueba: FeedRepository {
    let lista: [Articulo]
    func articulos() async throws -> [Articulo] { lista }
}

/// El ping del servidor del caso §8.8: cada segundo, los mismos artículos con más visitas.
@MainActor
func simularPings(feed: FeedModel, base: [Articulo]) async {
    var actual = base
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        for i in actual.indices { actual[i].vistas += 1 }
        await feed.aplicar(actual)
    }
}
