import SwiftUI
import PulseCore
import PulseFeed
import PulseSearch
import PulseProduct
import PulseCart
import PulseCheckout
import PulseDebug

@main
struct PulseApp: App {
    private let base = DatosDePrueba.articulos()

    @State private var flags = FeatureFlags(bannerPromo: false)
    @State private var estadoFeed = EstadoFeed()
    @State private var carrito = Carrito()
    @State private var controles = DebugControles()
    @State private var catalogo = CatalogoStub()
    @State private var feed: FeedModel

    init() {
        let base = DatosDePrueba.articulos()
        _feed = State(initialValue: FeedModel(repositorio: RepositorioDePrueba(lista: base)))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("Feed", systemImage: "newspaper") {
                    FeedList(modelo: feed, estado: estadoFeed)
                        .task {
                            await feed.cargar()
                            await simularPings(feed: feed, base: base)
                        }
                }
                Tab("Buscar", systemImage: "magnifyingglass") {
                    VStack {
                        SearchView(catalogo: catalogo)
                        TagCloudView(etiquetas: TagCloudView.sesenta)
                    }
                }
                Tab("Producto", systemImage: "bag") {
                    PriceRow(producto: .prueba, carrito: carrito).padding()
                }
                Tab("Checkout", systemImage: "creditcard") {
                    CheckoutView(orderID: UUID(), carrito: carrito)
                }
                Tab("Debug", systemImage: "ladybug") {
                    DebugMenu(controles: controles, flags: flags, feed: feed,
                              estadoFeed: estadoFeed, catalogo: catalogo, articulos: base)
                }
            }
            .environment(flags)
        }
    }
}
