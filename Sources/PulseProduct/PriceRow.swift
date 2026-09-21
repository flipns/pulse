import SwiftUI
import PulseCore
import PulseCart

// Libro: cap. 4, §4.8
public struct PriceRow: View {
    let producto: Producto
    @Bindable var carrito: Carrito
    public init(producto: Producto, carrito: Carrito) { self.producto = producto; self.carrito = carrito }

    public var body: some View {
        #if PULSE_BUG
        // cap4-bug: el HStack reparte a partes iguales entre dos cosas que no son igual de importantes
        HStack {
            Text(Precio(centimos: producto.precioCentimos).texto(locale: .current)).font(.title2.bold())
            Spacer()
            Button("Añadir al carrito") { carrito.añadir(producto) }.buttonStyle(.borderedProminent)
        }
        #else
        // cap4-fix: prioridad explícita, fixedSize y ViewThatFits
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                precio.layoutPriority(1)
                Spacer(minLength: 12)
                boton.fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                precio
                boton.frame(maxWidth: .infinity)
            }
        }
        #endif
    }

    private var precio: some View {
        Text(Precio(centimos: producto.precioCentimos).texto(locale: .current))
            .font(.title2.bold())
            .fixedSize()                        // Nunca truncar
    }

    private var boton: some View {
        Button("Añadir al carrito") { carrito.añadir(producto) }
            .buttonStyle(.borderedProminent)
    }
}

#Preview("Accesibilidad 5, 320 pt") {          // V5
    PriceRow(producto: .prueba, carrito: Carrito())
        .environment(\.dynamicTypeSize, .accessibility5)
        .frame(width: 320)
}
