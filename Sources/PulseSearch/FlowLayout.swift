import SwiftUI
import PulseCore
import Synchronization

#if DEBUG
/// Sonda de V9 (cap. 7, §7.9): cuántas veces se llama a cada método del `Layout` y cuántas
/// subvistas se miden. Los métodos de `Layout` son `nonisolated` (§7.2), así que el contador no
/// puede vivir en el `MainActor`: va protegido con un `Mutex`, no con `nonisolated(unsafe)`.
nonisolated enum RegistroLayout {
    struct Cuenta: Sendable, Equatable {
        var sizeThatFits = 0
        var placeSubviews = 0
        var medicionesDeSubvistas = 0
    }
    static let cuenta = Mutex(Cuenta())
    static func reiniciar() { cuenta.withLock { $0 = Cuenta() } }
    static var actual: Cuenta { cuenta.withLock { $0 } }
}
#endif

// Libro: cap. 7, §7.2 y §7.3
public struct FlowLayout: Layout {
    public var espaciado: CGFloat = 8
    public init(espaciado: CGFloat = 8) { self.espaciado = espaciado }

    #if PULSE_BUG
    // cap7-bug: sin caché. Cada método mide todas las subvistas (V9).
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let id = Signposts.layout.makeSignpostID()
        let s = Signposts.layout.beginInterval("sizeThatFits", id: id)
        #if DEBUG
        RegistroLayout.cuenta.withLock { $0.sizeThatFits += 1 }
        #endif
        defer { Signposts.layout.endInterval("sizeThatFits", s) }
        let ancho = proposal.replacingUnspecifiedDimensions().width
        let marcos = distribuir(medir(subviews), anchoContenedor: ancho)
        return marcos.reduce(CGRect.zero) { $0.union($1) }.size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let id = Signposts.layout.makeSignpostID()
        let s = Signposts.layout.beginInterval("placeSubviews", id: id)
        #if DEBUG
        RegistroLayout.cuenta.withLock { $0.placeSubviews += 1 }
        #endif
        defer { Signposts.layout.endInterval("placeSubviews", s) }
        let marcos = distribuir(medir(subviews), anchoContenedor: bounds.width)
        colocar(marcos, subviews, in: bounds)
    }
    #else
    // cap7-fix: caché de tamaños ideales y de marcos por ancho.
    public struct Cache {
        var tamaños: [CGSize] = []
        var ultimoAncho: CGFloat? = nil
        var marcos: [CGRect] = []
    }

    public func makeCache(subviews: Subviews) -> Cache {
        Cache(tamaños: medir(subviews))
    }

    public func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.tamaños = medir(subviews)
        cache.ultimoAncho = nil
    }

    private func marcos(para ancho: CGFloat, cache: inout Cache) -> [CGRect] {
        if cache.ultimoAncho != ancho {
            cache.marcos = distribuir(cache.tamaños, anchoContenedor: ancho)
            cache.ultimoAncho = ancho
        }
        return cache.marcos
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let id = Signposts.layout.makeSignpostID()
        let s = Signposts.layout.beginInterval("sizeThatFits", id: id)
        #if DEBUG
        RegistroLayout.cuenta.withLock { $0.sizeThatFits += 1 }
        #endif
        defer { Signposts.layout.endInterval("sizeThatFits", s) }
        let ancho = proposal.replacingUnspecifiedDimensions(by: .init(width: 320, height: 10)).width
        return marcos(para: ancho, cache: &cache).reduce(CGRect.zero) { $0.union($1) }.size
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let id = Signposts.layout.makeSignpostID()
        let s = Signposts.layout.beginInterval("placeSubviews", id: id)
        #if DEBUG
        RegistroLayout.cuenta.withLock { $0.placeSubviews += 1 }
        #endif
        defer { Signposts.layout.endInterval("placeSubviews", s) }
        colocar(marcos(para: bounds.width, cache: &cache), subviews, in: bounds)
    }
    #endif

    /// Mide el tamaño ideal de todas las subvistas. Es el trabajo que la caché evita repetir.
    private func medir(_ subviews: Subviews) -> [CGSize] {
        #if DEBUG
        RegistroLayout.cuenta.withLock { $0.medicionesDeSubvistas += subviews.count }
        #endif
        return subviews.map { $0.sizeThatFits(.unspecified) }
    }

    private func colocar(_ marcos: [CGRect], _ subviews: Subviews, in bounds: CGRect) {
        for (marco, subvista) in zip(marcos, subviews) {
            subvista.place(
                at: CGPoint(x: bounds.minX + marco.minX, y: bounds.minY + marco.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(marco.size)
            )
        }
    }

    // internal: se prueba en el capítulo 10 (V17)
    func distribuir(_ tamaños: [CGSize], anchoContenedor: CGFloat) -> [CGRect] {
        var resultado: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, altoLinea: CGFloat = 0
        for tamaño in tamaños {
            if x > 0, x + tamaño.width > anchoContenedor {
                x = 0
                y += altoLinea + espaciado
                altoLinea = 0
            }
            resultado.append(CGRect(origin: CGPoint(x: x, y: y), size: tamaño))
            x += tamaño.width + espaciado
            altoLinea = max(altoLinea, tamaño.height)
        }
        return resultado
    }
}
