import SwiftUI
import PulseCore
import PulseFeed
import PulseSearch
import PulseCheckout

// Menú de depuración: un disparador por caso. Solo se enlaza en Debug.
@Observable @MainActor
public final class DebugControles {
    public var invertirOrdenRespuestas = false      // cap. 9, §9.9
    public var bannerActivo = false                 // cap. 3, §3.7 / cap. 5, §5.6
    public var latenciaSegundos = 0.0
    public init() {}
}

public struct DebugMenu: View {
    @Bindable var controles: DebugControles
    let flags: FeatureFlags
    let feed: FeedModel
    let estadoFeed: EstadoFeed
    let catalogo: CatalogoStub
    var articulos: [Articulo]

    public init(controles: DebugControles, flags: FeatureFlags, feed: FeedModel, estadoFeed: EstadoFeed,
                catalogo: CatalogoStub, articulos: [Articulo]) {
        self.controles = controles; self.flags = flags; self.feed = feed; self.estadoFeed = estadoFeed
        self.catalogo = catalogo; self.articulos = articulos
    }

    public var body: some View {
        Form {
            Section("Feed (cap. 2, 8)") {
                Button("Promocionar primer artículo") {           // cap2: cambio de rama
                    var copia = articulos
                    if !copia.isEmpty { copia[0].esDestacado.toggle() }
                    Task { await feed.aplicar(copia) }
                }
                Button("Insertar promoción al principio") {         // cap2: ForEach por índice
                    Task { await feed.aplicar([Articulo(titulo: "Promoción")] + articulos) }
                }
                Button("Ping del servidor (solo cambian visitas)") {   // cap8, H10: campo que la UI no muestra
                    var conMasVistas = articulos
                    for i in conMasVistas.indices { conMasVistas[i].vistas += 1 }
                    Task { await feed.aplicar(conMasVistas) }
                }
                Button("Ping idéntico (no debería notificar)") {         // H10: control, Observation lo suprime
                    Task { await feed.aplicar(articulos) }
                }
            }
            Section("Checkout (cap. 3, 5)") {
                Toggle("Banner de promoción", isOn: Bindable(flags).bannerPromo)
            }
            Section("Búsqueda (cap. 9)") {
                Toggle("Invertir orden de respuestas", isOn: $controles.invertirOrdenRespuestas)
                    .onChange(of: controles.invertirOrdenRespuestas) { _, nuevo in
                        Task { await catalogo.configurar(invertirOrden: nuevo) }
                    }
            }
        }
    }
}
