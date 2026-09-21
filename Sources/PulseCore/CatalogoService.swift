import Foundation

// Libro: cap. 10, §10.3 — la dependencia entra por protocolo Sendable para poder sustituirla en tests
public protocol CatalogoProveedor: Sendable {
    func buscar(_ consulta: String) async throws -> [Producto]
}

// Libro: cap. 9, §9.2 — capa de datos: estado mutable protegido por el actor
public actor CatalogoService: CatalogoProveedor {
    private var cache: [String: [Producto]] = [:]
    private let session: URLSession
    private let base: URL

    public init(session: URLSession = .shared, base: URL = URL(string: "https://api.pulse.example")!) {
        self.session = session; self.base = base
    }

    public func buscar(_ consulta: String) async throws -> [Producto] {
        if let cacheados = cache[consulta] { return cacheados }
        let url = base.appending(path: "search").appending(queryItems: [.init(name: "q", value: consulta)])
        let (datos, _) = try await session.data(from: url)
        let productos = try JSONDecoder().decode([Producto].self, from: datos)
        cache[consulta] = productos
        return productos
    }
}

// Libro: cap. 9, §9.9 — stub con latencia inversa a la longitud de la consulta:
// "za" tarda más que "zap", así que las respuestas llegan fuera de orden de forma determinista (V14).
public actor CatalogoStub: CatalogoProveedor {
    public var latenciaBase: Duration
    public var invertirOrden: Bool
    private var fijos: [Producto]

    public init(productos: [Producto] = [.prueba], latenciaBase: Duration = .milliseconds(300), invertirOrden: Bool = false) {
        self.fijos = productos; self.latenciaBase = latenciaBase; self.invertirOrden = invertirOrden
    }

    public func configurar(invertirOrden: Bool) { self.invertirOrden = invertirOrden }

    public func buscar(_ consulta: String) async throws -> [Producto] {
        if invertirOrden {
            // Más corta → más lenta. Con "z", "za", "zap": 300, 200, 100 ms.
            let factor = max(1, 4 - consulta.count)
            try await Task.sleep(for: latenciaBase * factor / 3)
        } else {
            try await Task.sleep(for: latenciaBase)
        }
        try Task.checkCancellation()
        return fijos.filter { consulta.isEmpty || $0.nombre.localizedCaseInsensitiveContains(consulta) }
            + [Producto(id: "q-\(consulta)", nombre: "Resultado para \(consulta)", precioCentimos: 100)]
    }
}
