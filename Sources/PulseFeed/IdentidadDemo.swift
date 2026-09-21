import SwiftUI
import PulseCore

// Libro: cap. 2, §2.10–2.11 (V2) — índice frente a identidad estable.
//
// Cada fila guarda en `@State` el título del artículo para el que se CREÓ su nodo. Como el valor
// asignado en el `init` solo se usa cuando el nodo nace (cap. 3, §3.3), esa `@State` es una marca
// de identidad: si más tarde la fila muestra otro artículo, su nodo no se ha recreado, se ha
// reutilizado para un dato distinto. Eso es exactamente lo que hace `ForEach` con índices al
// insertar al principio.
//
// Usa `VStack`, no `List` ni un contenedor perezoso: así todas las filas existen a la vez y el
// resultado no depende del margen de retención del contenedor (§2.8).

/// Registro de la sonda. `MainActor` por el aislamiento por defecto del módulo: lo escriben los
/// `body` y lo lee el test, los dos en el `MainActor`.
enum RegistroIdentidad {
    static var evaluaciones = 0
    static var desajustes: [(mostrado: String, nacidaPara: String)] = []
    static func reiniciar() { evaluaciones = 0; desajustes = [] }
}

@Observable @MainActor
final class ModeloIdentidad {
    var items: [Articulo]
    init(items: [Articulo]) { self.items = items }
}

struct FilaConMemoria: View {
    let articulo: Articulo
    @State private var nacidaPara: String        // Sin valor en línea: se fija al nacer el nodo

    init(articulo: Articulo) {
        self.articulo = articulo                   // Primero el resto de propiedades (TN3211)
        self.nacidaPara = articulo.titulo
    }

    var body: some View {
        let _ = {
            RegistroIdentidad.evaluaciones += 1
            if nacidaPara != articulo.titulo {
                RegistroIdentidad.desajustes.append((articulo.titulo, nacidaPara))
            }
        }()
        return Text(articulo.titulo)
    }
}

struct IdentidadDemo: View {
    let modelo: ModeloIdentidad

    var body: some View {
        VStack {
            #if PULSE_BUG
            // cap2-bug: la identidad es la POSICIÓN.
            ForEach(modelo.items.indices, id: \.self) { i in
                FilaConMemoria(articulo: modelo.items[i])
            }
            #else
            // cap2-fix: la identidad es el ARTÍCULO.
            ForEach(modelo.items) { articulo in
                FilaConMemoria(articulo: articulo)
            }
            #endif
        }
    }
}
