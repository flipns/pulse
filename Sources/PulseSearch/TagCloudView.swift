import SwiftUI

// Libro: cap. 7, §7.9 — nube de etiquetas (60 elementos)
public struct TagCloudView: View {
    public let etiquetas: [String]
    public init(etiquetas: [String]) { self.etiquetas = etiquetas }

    public var body: some View {
        FlowLayout(espaciado: 6) {
            ForEach(etiquetas, id: \.self) { Etiqueta(texto: $0).equatable() }
        }
        // V10: reordenación iOS 27 sobre un Layout propio (`reorderable` / `reorderContainer`, beta al cierre)
    }
}

struct Etiqueta: View, Equatable {
    let texto: String
    var body: some View {
        Text(texto)
            .font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary, in: .capsule)
    }
}

public extension TagCloudView {
    static let sesenta: [String] = (1...60).map { "etiqueta-\($0)" + String(repeating: "x", count: $0 % 7) }
}
