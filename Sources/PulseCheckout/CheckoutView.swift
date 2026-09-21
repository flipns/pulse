import SwiftUI
import PulseCore
import PulseCart

// Libro: cap. 3, §3.7 y cap. 5, §5.6
public struct CheckoutView: View {
    let orderID: UUID
    let carrito: Carrito

    #if PULSE_BUG
    private let modelo: CheckoutModel                                  // cap3-bug: vive en la struct
    public init(orderID: UUID, carrito: Carrito) {
        self.orderID = orderID; self.carrito = carrito
        self.modelo = CheckoutModel(carrito: carrito)                  // Nuevo objeto en cada reconstrucción
    }
    @Environment(FeatureFlags.self) private var flags                  // cap5-bug: crash sin inyección
    #else
    @State private var modelo: CheckoutModel                           // cap3-fix: vive en el nodo
    public init(orderID: UUID, carrito: Carrito) {
        self.orderID = orderID; self.carrito = carrito
        self.modelo = CheckoutModel(carrito: carrito)                  // §3.3: sin valor en línea, asignación en init
    }
    // H3: la opcionalidad va en el TIPO DE LA PROPIEDAD, no en el argumento.
    // `@Environment(FeatureFlags?.self)` no compila: no existe esa sobrecarga.
    @Environment(FeatureFlags.self) private var flagsInyectados: FeatureFlags?   // cap5-fix
    private var flags: FeatureFlags { flagsInyectados ?? .porDefecto }
    #endif

    /// Acceso de solo lectura para el test de ownership (cap. 10, §10.6). `internal`, no `public`.
    var modeloParaTests: CheckoutModel { modelo }

    public var body: some View {
        let _ = Self._printChanges()
        let _ = { RegistroCheckout.enUso = ObjectIdentifier(modelo) }()   // H6/H11: qué instancia usa la vista
        return VStack(spacing: 16) {
            if flags.bannerPromo { PromoBanner() }
            PaymentForm(modelo: modelo)
        }
        .padding()
    }
}

struct PaymentForm: View {
    @Bindable var modelo: CheckoutModel
    var body: some View {
        Form {
            TextField("Titular", text: $modelo.titular)
            TextField("Número de tarjeta", text: $modelo.numeroTarjeta)
            Toggle("Acepto las condiciones", isOn: $modelo.aceptaCondiciones)
            LabeledContent("Total", value: Precio(centimos: modelo.total).texto(locale: .current))
        }
    }
}

public struct PromoBanner: View {
    public init() {}
    public var body: some View {
        Label("Envío gratis a partir de 50 €", systemImage: "gift")
            .padding().frame(maxWidth: .infinity).background(.yellow.opacity(0.25), in: .rect(cornerRadius: 12))
    }
}

/// Padre de prueba para el caso del capítulo 3 y el test del capítulo 10 (§10.6).
///
/// H11: es IMPRESCINDIBLE que este `body` lea `flags.bannerPromo` de verdad. Si el padre se limita
/// a pasar `flags` por el entorno sin leerlo, cambiar el flag invalida a `CheckoutView` (que sí lo
/// lee) pero NO reconstruye la struct de este padre, y el bug del capítulo 3 no se dispara ni
/// siquiera con `private let modelo`. El bug solo aparece cuando una actualización reconstruye la
/// struct de la vista que posee el modelo, no con cualquier invalidación.
public struct CheckoutHost: View {
    let flags: FeatureFlags
    let carrito: Carrito
    public init(flags: FeatureFlags, carrito: Carrito = .prueba(importe: 20)) {
        self.flags = flags; self.carrito = carrito
    }
    public var body: some View {
        VStack {
            if flags.bannerPromo { Text("promo") }      // Dependencia real: fuerza la reconstrucción
            CheckoutView(orderID: UUID(), carrito: carrito)
        }
        .environment(flags)
    }
}
