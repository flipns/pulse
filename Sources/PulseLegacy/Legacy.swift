import SwiftUI
import Combine
import PulseCore

// Único módulo con `import Combine`. Existe para que las secciones legacy del libro compilen.

// Libro: cap. 3, §3.8–3.10
public final class ModeloLegacy: ObservableObject {
    @Published public var valor = 0
    public init() {}
}

public struct ContadorLegacy: View {
    @StateObject private var modelo = ModeloLegacy()
    public init() {}
    public var body: some View {
        Button("Inc: \(modelo.valor)") { modelo.valor += 1 }
    }
}

public struct DetalleLegacy: View {
    @ObservedObject var modelo: ModeloLegacy
    public init(modelo: ModeloLegacy) { self.modelo = modelo }
    public var body: some View { Text("\(modelo.valor)") }
}

// Libro: cap. 9, §9.4 — consumir un Publisher con .values (Failure == Never: no lanza)
public struct LiveFeedView: View {
    @State private var eventos: [String] = []
    private let latidos = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    public init() {}

    public var body: some View {
        List(eventos.reversed(), id: \.self) { Text($0) }
            .task {
                for await _ in latidos.values {
                    eventos.append(Date.now.formatted(date: .omitted, time: .standard))
                    if eventos.count > 50 { eventos.removeFirst() }
                }
            }
    }
}
