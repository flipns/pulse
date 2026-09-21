import SwiftUI
import PulseCore

// Libro: cap. 6, §6.8
public struct AddToCartButton: View {
    @Bindable var carrito: Carrito
    let producto: Producto
    public init(carrito: Carrito, producto: Producto) { self.carrito = carrito; self.producto = producto }

    private var añadido: Bool { carrito.contiene(producto) }

    public var body: some View {
        Button {
            withAnimation(.bouncy) { carrito.alternar(producto) }
        } label: {
            #if PULSE_BUG
            // cap6-bug: dos nodos; withAnimation anima una inserción y una eliminación
            if añadido {
                Label("Añadido", systemImage: "checkmark").foregroundStyle(.green)
            } else {
                Label("Añadir al carrito", systemImage: "cart.badge.plus")
            }
            #else
            // cap6-fix: un solo nodo cuyos parámetros cambian
            Label(añadido ? "Añadido" : "Añadir al carrito",
                  systemImage: añadido ? "checkmark" : "cart.badge.plus")
                .foregroundStyle(añadido ? .green : .primary)
                .contentTransition(.symbolEffect(.replace))
            #endif
        }
        .buttonStyle(.borderedProminent)
        .sensoryFeedback(.success, trigger: añadido) { !$0 && $1 }
    }
}

// Libro: cap. 6, §6.5 — Animatable a mano. V7: sustituir por @Animatable si el target lo permite.
struct Sacudida: ViewModifier, Animatable {
    var sacudidas: Double
    var animatableData: Double { get { sacudidas } set { sacudidas = newValue } }
    func body(content: Content) -> some View {
        content.offset(x: -sin(sacudidas * 2 * .pi) * 30)
    }
}
