import SwiftUI
import PulseCore

#if PULSE_BUG
// Libro: cap. 9, §9.9 — el código que pasó la revisión (cap9-bug)
@Observable @MainActor
public final class SearchModel {
    public var consulta = ""
    public var resultados: [Producto] = []
    private let catalogo: any CatalogoProveedor
    public init(catalogo: any CatalogoProveedor) { self.catalogo = catalogo }

    public func consultaCambio() {
        Task {
            let r = try? await catalogo.buscar(consulta)
            resultados = r ?? []
        }
    }
    public func buscar() async { consultaCambio() }
}

public struct SearchView: View {
    @State private var modelo: SearchModel
    public init(catalogo: any CatalogoProveedor) { _modelo = State(initialValue: SearchModel(catalogo: catalogo)) }
    public var body: some View {
        VStack {
            TextField("Buscar", text: $modelo.consulta)
                .onChange(of: modelo.consulta) { modelo.consultaCambio() }
            List(modelo.resultados) { Text($0.nombre) }
        }
    }
}
#else
// Libro: cap. 9, §9.2 y §9.9 — la solución (cap9-fix)
@Observable @MainActor
public final class SearchModel {
    public var consulta = ""
    public private(set) var resultados: [Producto] = []
    public private(set) var cargando = false
    public private(set) var error: String?
    private let catalogo: any CatalogoProveedor

    public init(catalogo: any CatalogoProveedor) { self.catalogo = catalogo }   // Inyección por init (5.7)

    public func buscar() async {
        let consultaLanzada = consulta
        cargando = true
        defer { cargando = false }
        do {
            let r = try await catalogo.buscar(consultaLanzada)
            guard !Task.isCancelled, consultaLanzada == consulta else { return }   // (2) La pregunta sigue vigente
            resultados = r
        } catch is CancellationError {
            // La vista canceló; no es un error de usuario
        } catch {
            self.error = error.localizedDescription
        }
    }
}

public struct SearchView: View {
    @State private var modelo: SearchModel
    public init(catalogo: any CatalogoProveedor) { self.modelo = SearchModel(catalogo: catalogo) }   // §3.3, forma macro (V3)

    public var body: some View {
        VStack {
            TextField("Buscar", text: $modelo.consulta)
            List(modelo.resultados) { Text($0.nombre) }
        }
        .task(id: modelo.consulta) {                                    // (1) Cancela la anterior; debounce
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await modelo.buscar()
        }
    }
}
#endif
