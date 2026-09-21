import SwiftUI
import PulseCore

@Observable @MainActor
public final class Carrito {
    public private(set) var lineas: [Producto.ID: (producto: Producto, cantidad: Int)] = [:]
    public var alCambiar: (() -> Void)?
    public init(alCambiar: (() -> Void)? = nil) { self.alCambiar = alCambiar }

    public func contiene(_ p: Producto) -> Bool { lineas[p.id] != nil }
    public func añadir(_ p: Producto) { lineas[p.id] = (p, (lineas[p.id]?.cantidad ?? 0) + 1); alCambiar?() }
    public func quitar(_ p: Producto) { lineas[p.id] = nil; alCambiar?() }
    public func alternar(_ p: Producto) { contiene(p) ? quitar(p) : añadir(p) }
    public func cantidad(de p: Producto, a n: Int) { lineas[p.id] = (p, n); alCambiar?() }

    public var totalCentimos: Int { lineas.values.reduce(0) { $0 + $1.producto.precioCentimos * $1.cantidad } }

    public static func prueba(importe: Int) -> Carrito {
        let c = Carrito(); c.añadir(Producto(id: "t", nombre: "Prueba", precioCentimos: importe * 100)); return c
    }
}
