import Testing
import PulseCore
@testable import PulseSearch

extension Tag { @Tag static var bug: Self }

// Libro: cap. 9, §9.9 — dos respuestas fuera de orden (V14). cap9-bug falla, cap9-fix pasa.
//
// AVISO DE DISEÑO (hallazgo de revisión externa): la primera versión de este test esperaba
// solo a `t1.value` y `t2.value` antes de comprobar `resultados`. En la variante con bug eso
// era insuficiente: `buscar()` delega en una `Task` NO estructurada, así que `t1`/`t2` terminan
// en cuanto la han creado y el test comprobaba un `resultados` todavía vacío. Fallaba en `bug`,
// sí, pero por prematuridad, no por desorden — justo lo que §9.9 dice demostrar.
//
// Esta versión espera a que todo el trabajo en vuelo haya terminado (incluidas las tareas
// internas que `t1.cancel()` no alcanza en la variante con bug) antes de afirmar nada. Así:
//   - cap9-fix: t1 se cancela y su escritura queda descartada por el guard → gana "zap".
//   - cap9-bug: la Task interna de "za" sobrevive a la cancelación y, por ser más lenta,
//     escribe DESPUÉS que la de "zap" → gana "za" → el test falla por desorden real.
@Suite("Orden de respuestas de búsqueda", .tags(.bug))
struct OrdenRespuestasTests {

    @Test("La última respuesta corresponde a la última consulta")
    @MainActor
    func ultimaRespuestaUltimaConsulta() async throws {
        // Con invertirOrden, la consulta más corta tarda más: "za" (40 ms) llega
        // después que "zap" (20 ms). El desorden es determinista, no una carrera.
        let stub = CatalogoStub(latenciaBase: .milliseconds(60), invertirOrden: true)
        let modelo = SearchModel(catalogo: stub)

        modelo.consulta = "za"
        let t1 = Task { await modelo.buscar() }
        try await Task.sleep(for: .milliseconds(5))

        modelo.consulta = "zap"
        t1.cancel()                                   // Lo que hace .task(id:) al cambiar la consulta
        let t2 = Task { await modelo.buscar() }

        await t1.value
        await t2.value

        // Clave del test: dar tiempo a que termine CUALQUIER trabajo en vuelo, incluido el que
        // la variante con bug lanzó fuera de la estructura de tareas. Sin esta espera, el test
        // mediría "¿ha llegado ya algo?" en vez de "¿ha ganado la respuesta correcta?".
        try await Task.sleep(for: .milliseconds(400))

        #expect(modelo.resultados.contains { $0.id == "q-zap" },
                "esperaba el resultado de la última consulta; resultados = \(modelo.resultados.map(\.id))")
        #expect(!modelo.resultados.contains { $0.id == "q-za" },
                "una respuesta de una consulta anterior ha sobrescrito a la actual")
    }
}
