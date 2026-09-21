import SwiftUI
import PulseCore

public protocol FeedRepository: Sendable {
    func articulos() async throws -> [Articulo]
}

#if PULSE_BUG
// Libro: cap. 8, §8.8 — el modelo publica el payload del servidor tal cual (cap8-bug).
// Cada ping trae `vistas` distinto → el array difiere → las 400 filas se invalidan.
@Observable @MainActor
public final class FeedModel {
    public var articulos: [Articulo] = []
    private let repositorio: any FeedRepository
    public init(repositorio: any FeedRepository) { self.repositorio = repositorio }

    public func aplicar(_ crudos: [Articulo]) async { articulos = crudos }
    public func cargar() async { await aplicar((try? await repositorio.articulos()) ?? []) }
}
#else
// Libro: cap. 8, §8.3 y §8.8 — el modelo publica la proyección que la UI consume (cap8-fix).
@Observable @MainActor
public final class FeedModel {
    public private(set) var visibles: [ArticuloPresentado] = []
    private let repositorio: any FeedRepository
    public init(repositorio: any FeedRepository) { self.repositorio = repositorio }

    public func cargar() async {
        let id = Signposts.feed.makeSignpostID()
        let estado = Signposts.feed.beginInterval("Cargar feed", id: id)
        defer { Signposts.feed.endInterval("Cargar feed", estado) }
        await aplicar((try? await repositorio.articulos()) ?? [])
    }

    public func aplicar(_ crudos: [Articulo]) async {
        let nuevos = await Self.presentar(crudos)          // (1) Fuera del MainActor
        guard nuevos != visibles else { return }           // (2) Comparar lo que la UI muestra
        visibles = nuevos
    }

    // Libro: cap. 8, §8.5
    @concurrent
    private nonisolated static func presentar(_ crudos: [Articulo]) async -> [ArticuloPresentado] {
        // Un solo formateador y una sola fecha de referencia para todo el lote: la proyección
        // es determinista, que es lo que permite compararla en `aplicar(_:)`.
        ArticuloPresentado.proyectar(
            crudos.filter { !$0.oculto }.sorted { $0.fecha > $1.fecha }   // Sin `vistas`: la UI no lo muestra
        )
    }
}
#endif
