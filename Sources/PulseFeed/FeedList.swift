import SwiftUI
import PulseCore

#if PULSE_BUG
// Libro: cap. 8, §8.8 — el código que pasó la revisión (cap8-bug)
public struct FeedList: View {
    let modelo: FeedModel
    let estado: EstadoFeed
    public init(modelo: FeedModel, estado: EstadoFeed) { self.modelo = modelo; self.estado = estado }

    public var body: some View {
        List(modelo.articulos.filter { !$0.oculto }.sorted { $0.fecha > $1.fecha }) { articulo in
            FeedRowLenta(articulo: articulo, formatter: RelativeDateTimeFormatter())
                .shadow(radius: 4)
        }
    }
}

struct FeedRowLenta: View {
    let articulo: Articulo
    let formatter: RelativeDateTimeFormatter
    var body: some View {
        VStack(alignment: .leading) {
            Text(articulo.titulo).font(.headline)
            Text(formatter.localizedString(for: articulo.fecha, relativeTo: .now)).font(.caption)
        }
    }
}
#else
// Libro: cap. 8, §8.8 — la solución (cap8-fix)
public struct FeedList: View {
    let modelo: FeedModel
    let estado: EstadoFeed
    public init(modelo: FeedModel, estado: EstadoFeed) { self.modelo = modelo; self.estado = estado }

    public var body: some View {
        List(modelo.visibles) { FilaFeed(articulo: $0).equatable() }   // (3)
    }
}

struct FilaFeed: View, Equatable {
    let articulo: ArticuloPresentado
    var body: some View {
        VStack(alignment: .leading) {
            Text(articulo.titulo).font(.headline)
            Text(articulo.fechaRelativa).font(.caption)
        }
        .background(.background, in: .rect(cornerRadius: 12))         // (4) Sin sombra por fila
    }
}
#endif

// Libro: cap. 2, §2.7 — ForEach cuyos elementos producen un número variable de vistas (V1)
public struct FeedSlowPathDemo: View {
    let items: [Articulo]
    public init(items: [Articulo]) { self.items = items }
    public var body: some View {
        List {
            ForEach(items) { item in
                #if PULSE_BUG
                if !item.oculto { Text(item.titulo) }                   // Slow path
                #else
                VStack { if !item.oculto { Text(item.titulo) } }        // Una vista por elemento
                #endif
            }
        }
    }
}
