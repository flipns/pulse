import SwiftUI
import PulseCart

public enum CuponError: Error, Equatable { case noEncontrado }

/// Registro de instrumentación para el caso de ownership del capítulo 3 (§3.7) y el test del
/// capítulo 10 (§10.6). Deliberadamente FUERA de la clase observable: una estática dentro de un
/// tipo `@Observable` hace que la macro intente tratarla como propiedad observable y la expansión
/// falla en este SDK ("generic parameter 'Member' could not be inferred"). No es nada del libro;
/// es una rareza de la macro descubierta al escribir la sonda de verificación.
public enum RegistroCheckout {
    nonisolated(unsafe) public static var creados = 0
    nonisolated(unsafe) public static var enUso: ObjectIdentifier?
    public static func reiniciar() { creados = 0; enUso = nil }
}

// Libro: cap. 3, §3.7 y cap. 10, §10.2, §10.6
@Observable @MainActor
public final class CheckoutModel {
    public static let envio = 4_99
    public static let minimoEnvioGratis = 50_00

    public var titular = ""
    public var numeroTarjeta = ""
    public var aceptaCondiciones = false
    public let carrito: Carrito

    public init(carrito: Carrito) {
        self.carrito = carrito
        RegistroCheckout.creados += 1
    }

    public var total: Int {
        carrito.totalCentimos + (carrito.totalCentimos >= Self.minimoEnvioGratis ? 0 : Self.envio)
    }

    public func aplicar(cupon: String) throws {
        guard cupon == "PULSE10" else { throw CuponError.noEncontrado }
    }
}
