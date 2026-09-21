import Testing
import CoreGraphics
@testable import PulseSearch

// Libro: cap. 10, §10.4 (V17)
@Suite("FlowLayout")
struct FlowLayoutTests {
    @Test("El flow salta de línea cuando no cabe", arguments: [280.0, 320.0, 390.0])
    func flowSaltaDeLinea(ancho: CGFloat) {
        let tamaños = Array(repeating: CGSize(width: 100, height: 30), count: 5)
        let marcos = FlowLayout(espaciado: 8).distribuir(tamaños, anchoContenedor: ancho)
        let porLinea = Int((ancho + 8) / 108)
        #expect(marcos[porLinea].minY > 0)
        #expect(marcos.allSatisfy { $0.maxX <= ancho })
    }

    @Test("Un solo elemento más ancho que el contenedor no salta de línea")
    func elementoAncho() {
        let marcos = FlowLayout().distribuir([CGSize(width: 500, height: 20)], anchoContenedor: 300)
        #expect(marcos.first?.minY == 0)
    }
}
