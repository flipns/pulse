import Foundation
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

    /// Fecha de referencia con la que se construyen los textos relativos ("hace 3 min").
    ///
    /// No es `Date.now` en cada proyección, y esto NO es un detalle: si cada ping usara la hora
    /// actual, dos payloads idénticos proyectados a los dos lados de un umbral ("ahora" → "hace
    /// 1 min") darían textos distintos, la comparación de `aplicar(_:)` detectaría un cambio y
    /// las vistas se invalidarían igual. Son dos relojes distintos: el de los datos, que avanza
    /// cuando el servidor manda algo nuevo, y el de la presentación, que avanza cuando queremos
    /// refrescar los textos. Mezclarlos devuelve el problema que este caso viene a resolver.
    private var referenciaTemporal: Date

    public init(repositorio: any FeedRepository, referenciaTemporal: Date = .now) {
        self.repositorio = repositorio
        self.referenciaTemporal = referenciaTemporal
    }

    /// Avanza el reloj de la presentación a propósito: reproyecta con la hora actual para que los
    /// textos relativos se actualicen. Llámalo desde un temporizador lento (un minuto), no desde
    /// cada respuesta del servidor.
    public func refrescarTextosRelativos(_ ahora: Date = .now) async {
        referenciaTemporal = ahora
        let nuevos = await Self.presentar(ultimosCrudos, ahora: ahora)
        guard nuevos != visibles else { return }
        visibles = nuevos
    }

    private var ultimosCrudos: [Articulo] = []

    public func cargar() async {
        let id = Signposts.feed.makeSignpostID()
        let estado = Signposts.feed.beginInterval("Cargar feed", id: id)
        defer { Signposts.feed.endInterval("Cargar feed", estado) }
        await aplicar((try? await repositorio.articulos()) ?? [])
    }

    public func aplicar(_ crudos: [Articulo]) async {
        ultimosCrudos = crudos
        let nuevos = await Self.presentar(crudos, ahora: referenciaTemporal)   // (1) Fuera del MainActor
        guard nuevos != visibles else { return }                                // (2) Comparar lo que la UI muestra
        visibles = nuevos
    }

    // Libro: cap. 8, §8.5
    @concurrent
    private nonisolated static func presentar(_ crudos: [Articulo], ahora: Date) async -> [ArticuloPresentado] {
        // Un solo formateador y una sola fecha de referencia para todo el lote: la proyección
        // es determinista, que es lo que permite compararla en `aplicar(_:)`.
        ArticuloPresentado.proyectar(
            crudos.filter { !$0.oculto }.sorted { $0.fecha > $1.fecha },  // Sin `vistas`: la UI no lo muestra
            ahora: ahora                                                  // Reloj de presentación, no Date.now
        )
    }
}
#endif
