import SwiftUI
import PulseCore

#if PULSE_BUG
// Libro: cap. 2, §2.9 — "el código que pasó la revisión" (cap2-bug)
public struct FeedRow: View {
    let articulo: Articulo
    @State private var desplegada = false

    public init(articulo: Articulo, estado: EstadoFeed) { self.articulo = articulo }

    public var body: some View {
        let _ = Self._printChanges()
        if articulo.esDestacado {
            FilaDestacada(articulo: articulo, desplegada: $desplegada)
        } else {
            FilaNormal(articulo: articulo, desplegada: $desplegada)
        }
    }
}

struct FilaDestacada: View {
    let articulo: Articulo
    @Binding var desplegada: Bool
    @State private var alturaMedida: CGFloat = 0     // Estado interno que se pierde al cambiar de rama
    var body: some View {
        let _ = Self._printChanges()
        FilaArticulo(articulo: articulo, destacada: true, desplegada: $desplegada)
    }
}

struct FilaNormal: View {
    let articulo: Articulo
    @Binding var desplegada: Bool
    var body: some View {
        let _ = Self._printChanges()
        FilaArticulo(articulo: articulo, destacada: false, desplegada: $desplegada)
    }
}
#else
// Libro: cap. 2, §2.9 — "la solución" (cap2-fix)
public struct FeedRow: View {
    let articulo: Articulo
    @Bindable var estado: EstadoFeed

    public init(articulo: Articulo, estado: EstadoFeed) { self.articulo = articulo; self.estado = estado }

    public var body: some View {
        FilaArticulo(
            articulo: articulo,
            destacada: articulo.esDestacado,                       // Una sola vista; la variante es un parámetro
            desplegada: estado.binding(desplegada: articulo.id)     // El modelo recuerda, por id
        )
    }
}
#endif

/// Una sola identidad estructural para normal y destacada.
struct FilaArticulo: View {
    let articulo: Articulo
    let destacada: Bool
    @Binding var desplegada: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(articulo.titulo)
                .font(destacada ? .title3.bold() : .headline)      // Valor condicional, no vista condicional
            if desplegada {
                Text(articulo.resumen).font(.body).transition(.opacity)
            }
        }
        .padding(destacada ? 16 : 12)
        .background(destacada ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
        .contentShape(.rect)
        .onTapGesture { withAnimation(.snappy) { desplegada.toggle() } }
    }
}
