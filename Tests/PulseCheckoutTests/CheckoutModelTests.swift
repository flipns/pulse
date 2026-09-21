import Testing
import Foundation
import PulseCore
import PulseCart
@testable import PulseCheckout

// Libro: cap. 10, §10.2
@Suite("Checkout")
@MainActor
struct CheckoutModelTests {

    @Test("El total incluye envío cuando no llega al mínimo")
    func totalConEnvio() {
        let modelo = CheckoutModel(carrito: .prueba(importe: 20))
        #expect(modelo.total == 20_00 + CheckoutModel.envio)
    }

    @Test("El total no incluye envío a partir del mínimo")
    func totalSinEnvio() {
        let modelo = CheckoutModel(carrito: .prueba(importe: 60))
        #expect(modelo.total == 60_00)
    }

    @Test("Aplicar cupón inválido lanza")
    func cuponInvalido() throws {
        let modelo = CheckoutModel(carrito: .prueba(importe: 20))
        #expect(throws: CuponError.noEncontrado) {
            try modelo.aplicar(cupon: "NOEXISTE")
        }
    }

    // H7: NO afirmes sobre cadenas localizadas completas.
    // "19,99 €" y "19,99 €" se ven iguales y no lo son: el formateador usa espacio duro (U+00A0)
    // antes del símbolo, y la separación de millares depende del locale, del SO y de la versión.
    // Comprueba lo que controlas: el valor numérico y la forma, no la tipografía de Foundation.
    @Test("Formato de precio", arguments: [
        (1999, "19,99"),
        (0, "0,00"),
        (100_000, "1000,00"),      // Sin asumir separador de millares
    ])
    func precio(centimos: Int, parteNumerica: String) {
        let texto = Precio(centimos: centimos).texto(locale: .es)
        let normalizado = texto
            .replacingOccurrences(of: "\u{00A0}", with: " ")   // Espacio duro → espacio normal
            .replacingOccurrences(of: ".", with: "")           // Separador de millares, si lo hay
        #expect(normalizado.hasSuffix("€"))
        #expect(normalizado.hasPrefix(parteNumerica))
    }

    @Test("Notifica al añadir")
    func notificaAlAñadir() async {
        await confirmation("callback de carrito") { confirmar in
            let carrito = Carrito(alCambiar: { confirmar() })
            carrito.añadir(.prueba)
        }
    }
}
