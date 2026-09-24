# Capítulo 9: Concurrencia y datos reactivos

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. `Observations` requiere iOS 26; `async` en `defer` y `~Sendable` requieren Swift 6.4 sin restricción de sistema.

## 9.1. Qué cambia con la concurrencia estricta

Hasta Swift 5 la corrección de un flujo de datos era una convención: "esto se llama en el hilo principal", "este *closure* puede venir de cualquier cola". En Swift 6 es un tipo: cada función tiene un aislamiento, cada valor que cruza una frontera tiene que ser `Sendable`, y el compilador rechaza lo que no cuadra. Cuesta al principio; a cambio, una gran parte de los errores de acceso concurrente pasan a ser errores de aislamiento que el compilador puede detectar, en vez de convenciones que el equipo tiene que recordar.

El coste real que hay detrás de "usa `Task`, no hilos": un hilo del sistema reserva 512 KB de pila por defecto (1 MB el principal) y un cambio de contexto pasa por el kernel; una `Task` es trabajo gestionado por el runtime de concurrencia y se ejecuta sobre ejecutores y pools compartidos; al suspenderse libera el recurso de ejecución para que otro trabajo avance. No necesitas convertir esto en una tabla de cifras: la decisión importante es no confundir "tener muchas tareas" con "tener muchos hilos".

Con *Approachable Concurrency*, el modelo mental correcto es:

1. **Todo es** **`MainActor`** salvo que digas lo contrario. Vistas, modelos `@Observable`, la mayoría del código de la app.
2. **`nonisolated async`** **hereda el actor del llamador.** Llamada desde el `MainActor`, sigue ahí. No es "en segundo plano".
3. **`@concurrent`** es cómo pides explícitamente el pool de hilos. Parámetros y resultado `Sendable`.
4. **`actor`** es cómo proteges estado mutable que no es de UI (caché, conexión, base de datos).
5. **Lo que cruza al `actor` o se lee fuera del `MainActor` necesita `nonisolated`, no solo `Sendable`.** Una `struct` de datos, un `static let` compartido, un *logger*: si el aislamiento por defecto los alcanza y algo fuera del `MainActor` los usa, hay que decirlo explícitamente (§9.2, y el recuadro del capítulo 8, §8.3).

Sin *Approachable Concurrency*, el punto 2 se invierte (`nonisolated async` va al pool). Por eso el capítulo 8 y este asumen la configuración y el repositorio la fija: un libro que dijera "depende" en cada párrafo no serviría para nada.

## 9.2. Arquitectura: `@MainActor` arriba, `actor` abajo

El patrón que funciona tiene dos capas y una frontera clara:

```swift
nonisolated struct Producto: Sendable, Identifiable, Equatable {
    let id: String
    let nombre: String
    let precioCentimos: Int
}

// CAPA DE DATOS: estado mutable protegido por el actor
actor CatalogoService {
    private var cache: [String: [Producto]] = [:]
    private let session: URLSession
    private let base: URL

    init(session: URLSession = .shared, base: URL = URL(string: "https://api.pulse.example")!) {
        self.session = session; self.base = base
    }

    func buscar(_ consulta: String) async throws -> [Producto] {
        if let cacheados = cache[consulta] { return cacheados }
        let url = base.appending(path: "search")
                      .appending(queryItems: [.init(name: "q", value: consulta)])
        let (datos, _) = try await session.data(from: url)
        let productos = try JSONDecoder().decode([Producto].self, from: datos)
        cache[consulta] = productos
        return productos
    }
}

// CAPA DE PRESENTACIÓN: estado de UI, síncrono, observable
@Observable @MainActor
final class SearchModel {
    var consulta = ""
    private(set) var resultados: [Producto] = []
    private(set) var cargando = false
    private(set) var error: String?

    private let catalogo: CatalogoService

    init(catalogo: CatalogoService) { self.catalogo = catalogo }   // Inyección por init, no por @Environment (5.7)

    func buscar() async {
        cargando = true
        defer { cargando = false }
        do {
            resultados = try await catalogo.buscar(consulta)   // Salto al actor y vuelta
        } catch is CancellationError {
            // La vista canceló; no es un error de usuario
        } catch {
            self.error = error.localizedDescription
        }
    }
}

```

Por qué así y no de otra forma:

- No plantees un `actor` como el modelo observable que SwiftUI lee directamente en `body`: el acceso a sus propiedades está aislado y requiere `await`. En `Pulse`, el estado que la vista lee es `@MainActor @Observable`; el actor queda detrás de esa frontera.
- Un tipo aislado a un *global actor* tiene tratamiento `Sendable` para cruzar fronteras de aislamiento; eso permite que una referencia a un modelo `@MainActor` participe en código concurrente sin convertir su estado en compartido sin protección.
- `Producto` es `nonisolated` **y** `Sendable`, y hacen falta las dos anotaciones para lo que hace este código. `Sendable` dice que el **valor** puede cruzar la frontera de aislamiento. `nonisolated` dice que su **código** (el `init`, en este caso) puede ejecutarse fuera del `MainActor`. Con *Default Actor Isolation = MainActor* activado (nuestra configuración desde el capítulo 1), el `init` sintetizado de una `struct` normal queda aislado al `MainActor`, así que un `actor` como `CatalogoService` no podría construir un `Producto` sin el `nonisolated` explícito: compilaría la declaración y fallaría en la llamada, con un error que no menciona la causa. Cualquier tipo de datos que un `actor` cree o lea directamente necesita esta doble anotación.
- El `await` en `buscar()` es la frontera: antes y después estás en el `MainActor`; en medio, en el actor. La UI nunca ve estado a medias.

> **Antipatrón.** `DispatchQueue.main.async { self.resultados = ... }` dentro de un modelo `@MainActor`. Compila (a veces), es redundante siempre, y esconde que quien lo escribió no sabe en qué actor está. Cada uno que veas en un *code review* es deuda técnica con nombre.

## 9.3. `.task` y la cancelación

`.task` (iOS 15+) une la vida de una vista con una `Task`: arranca cuando el nodo aparece, SwiftUI puede cancelarla cuando desaparece y `task(id:)` la cancela y recrea cuando cambia su `id`. La tarea hereda el aislamiento del contexto que la crea; en este libro, ese contexto es `MainActor`.

```swift
.task(id: modelo.consulta) {
    try? await Task.sleep(for: .milliseconds(300))     // Debounce: si la consulta cambia, esto se cancela
    guard !Task.isCancelled else { return }
    await modelo.buscar()
}

```

Tres cosas que este bloque hace sin que las escribas: cancela la búsqueda anterior al teclear (cambia el `id`), no lanza búsquedas para consultas que duraron menos de 300 ms, y cancela todo si el usuario sale de la pantalla. Para el caso de una búsqueda ligada a la vida de una vista, sustituye el patrón habitual de `debounce` + cancelación del trabajo anterior sin necesitar un `AnyCancellable`. Si el *pipeline* tiene semántica más compleja, usa los operadores de `swift-async-algorithms`.

La cancelación es **cooperativa**: `Task.sleep` y `URLSession.data` la respetan y lanzan `CancellationError`; tu código la respeta si comprueba `Task.isCancelled` o llama a `try Task.checkCancellation()` en los bucles largos. Una `Task` que no la comprueba no se cancela; se ignora.

Guardar la `Task` en un `@State` y cancelarla a mano en `onDisappear` es el mismo patrón escrito a mano, con un sitio más donde equivocarse. Hazlo solo cuando la vida de la tarea no coincida con la de una vista (una subida que debe continuar aunque cierres la pantalla).

## 9.4. Consumir Combine desde `async/await`

Combine no es el enemigo de este capítulo: es la tecnología que tienes en producción y que necesitas integrar sin reescribirla de golpe. Cualquier `Publisher` expone `.values`, una `AsyncSequence` (iOS 15+). Es el puente en la dirección que interesa: de lo antiguo hacia lo nuevo.

```swift
let latidos = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

.task {
    for await _ in latidos.values {          // No lanza: Failure == Never
        modelo.refrescar()
    }
}

```

Si el publisher tiene `Failure == Never`, el bucle no lanza y un `do/catch` alrededor es código muerto que el compilador señala. Si tiene un `Failure`, `.values` es una `AsyncThrowingSequence` y ahí sí capturas. La cancelación llega por `.task`: al desaparecer la vista, el `for await` termina y la suscripción se cancela.

Lo que `.values` no resuelve es la dirección contraria (exponer una `AsyncSequence` como `Publisher`) ni los operadores de combinación. Para lo primero, no lo hagas: migra el consumidor. Para lo segundo, 9.7.

## 9.5. `AsyncStream`: el sustituto de `PassthroughSubject`

Cuando eres tú quien produce eventos (un *socket*, un delegado, un `CLLocationManager`), el tipo es `AsyncStream` (o `AsyncThrowingStream` si puede fallar):

```swift
actor PreciosEnVivo {
    private let (stream, continuation) = AsyncStream.makeStream(of: [Producto].self,
                                                                 bufferingPolicy: .bufferingNewest(1))

    var actualizaciones: AsyncStream<[Producto]> { stream }

    func alRecibir(_ productos: [Producto]) { continuation.yield(productos) }
    func cerrar() { continuation.finish() }
}

```

`bufferingPolicy` es la decisión que Combine no te obligaba a tomar: si el consumidor va lento, ¿acumulas, descartas lo viejo o descartas lo nuevo? Para precios, lo viejo no interesa: `.bufferingNewest(1)`. No trates un `AsyncStream` como un bus de eventos para múltiples consumidores concurrentes: la iteración concurrente sobre sus iteradores no es un patrón seguro/documentado. Si necesitas fan-out real, modela el estado compartido explícitamente o crea una secuencia por consumidor.

`NotificationCenter.default.notifications(named:)` (iOS 15+) y las notificaciones tipadas de Swift 6.2 (`MainActorMessage` / `AsyncMessage`) son la misma idea aplicada a las notificaciones del sistema: `for await` en lugar de `sink`.

## 9.6. `Observations`: el modelo como fuente asíncrona

**Solo iOS 26+.** Hasta aquí SwiftUI observaba modelos y todo lo demás usaba Combine para hacerlo. `Observations` cierra el hueco: una `AsyncSequence` que emite cada vez que cambia lo que lee su *closure*, con semántica **transaccional**: todos los cambios síncronos hasta el siguiente punto de suspensión se agrupan en una sola emisión.

```swift
// Un servicio de analítica que reacciona al carrito sin que el carrito sepa que existe
func observarCarrito(_ carrito: Carrito) async {
    for await total in Observations({ carrito.totalCentimos }) {
        await analitica.registrar(.carritoActualizado(total))
    }
}

```

Esto cubre una parte importante de lo que antes resolvíamos con `objectWillChange.sink` o con `$propiedad.sink`: observas el valor que te interesa, no el publisher global del objeto. Su semántica de observación transaccional también evita convertir cada mutación síncrona de una misma transacción en una notificación independiente. El capítulo 10 la usa para probar que un modelo notifica.

El puente conceptual completo queda así:

```text
@Observable  ──(SwiftUI observa solo)──►  body
     │
     └──(fuera de SwiftUI)──►  Observations  ──►  AsyncSequence  ──►  for await

```

Combine sale de la ecuación para observar modelos. Se queda para lo que sigue.

## 9.7. Operadores: Swift Async Algorithms

`AsyncSequence` en la biblioteca estándar tiene `map`, `filter`, `compactMap`, `prefix`, `first` y poco más. Para `merge`, `combineLatest`, `zip`, `debounce`, `throttle`, `chunked` y compañía, el paquete oficial **swift-async-algorithms** (Apple, fuera del SDK):

```swift
import AsyncAlgorithms

for await (consulta, filtros) in combineLatest(consultas, filtrosActivos).debounce(for: .milliseconds(300)) {
    await modelo.buscar(consulta, filtros: filtros)
}

```

Los operadores de Combine y los de `AsyncSequence` pertenecen a abstracciones distintas: elige una abstracción para cada *pipeline* en vez de intentar encadenarlas como si fueran el mismo tipo de secuencia. Si un *pipeline* de Combine es largo y funciona, déjalo y consúmelo con `.values` al final; migra cuando lo toques por otra razón.

## 9.8. Solo Swift 6.4+

Tres cosas del compilador que este capítulo usa o menciona:

- **`async` en `defer`.** `defer { await conexion.cerrar() }` dentro de una función `async`. Hasta ahora la limpieza asíncrona obligaba a duplicarla en cada salida o a un `do/catch` artificial. Cambia cómo se escriben los actores que gestionan recursos.
- **`~Sendable`.** Marca un tipo como auditado y deliberadamente no `Sendable`, suprimiendo la inferencia. Sirve para documentar que un tipo con un `enum` cuyo caso asociado no es `Sendable` no debe cruzar fronteras, en lugar de dejar que el compilador lo infiera en silencio.
- **`@diagnose`.** Diagnósticos propios sobre tus APIs (avisar cuando alguien llama a `buscar()` sin `await` en un contexto concreto, por ejemplo). Útil en módulos compartidos; fuera del alcance de este libro.

## 9.9. Code review: dos respuestas de búsqueda que llegan fuera de orden

En `Pulse`, la búsqueda mostraba a veces resultados de la consulta anterior. Está en `Search/SearchModel.swift`.

### El código que pasó la revisión

```swift
@Observable @MainActor
final class SearchModel {
    var consulta = ""
    var resultados: [Producto] = []
    private let catalogo: CatalogoService

    func consultaCambio() {
        Task {
            let r = try? await catalogo.buscar(consulta)
            resultados = r ?? []
        }
    }
}

// Vista
TextField("Buscar", text: $modelo.consulta)
    .onChange(of: modelo.consulta) { modelo.consultaCambio() }

```

Compila con concurrencia estricta. La `Task` hereda el `MainActor`, `catalogo` es un actor, `Producto` es `Sendable`. Todo correcto según el compilador.

### El bug

El usuario teclea "za" y luego "zap". La búsqueda de "za" (más resultados, más lenta) llega **después** que la de "zap". La UI muestra los resultados de "za" bajo una consulta que dice "zap". Ningún *data race*: ambas escrituras ocurren en el `MainActor`, en orden. El orden es el equivocado.

La concurrencia estricta garantiza que no corrompes memoria. No garantiza que la última respuesta corresponda a la última pregunta. Eso es lógica tuya.

### Reproducirlo

El menú de depuración de `Pulse` tiene "invertir orden de respuestas": el `CatalogoService` de pruebas añade una latencia inversamente proporcional a la longitud de la consulta. Teclea tres letras seguidas y verás el fallo cada vez.

### La solución

```swift
@Observable @MainActor
final class SearchModel {
    var consulta = ""
    private(set) var resultados: [Producto] = []
    private let catalogo: CatalogoService

    func buscar() async {
        let consultaLanzada = consulta
        do {
            let r = try await catalogo.buscar(consultaLanzada)
            guard !Task.isCancelled, consultaLanzada == consulta else { return }   // (2)
            resultados = r
        } catch is CancellationError {
        } catch {
            // ...
        }
    }
}

// Vista
TextField("Buscar", text: $modelo.consulta)
    .task(id: modelo.consulta) {                                                   // (1)
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        await modelo.buscar()
    }

```

1. **`.task(id:)`** cancela y reinicia la tarea cuando cambia el valor `Equatable` usado como `id`. Es la primera línea de defensa y además nos da el *debounce* del ejemplo.
2. **La comprobación al volver** cubre el caso en que una operación ya en vuelo termina pese a la cancelación (la cancelación es cooperativa). Si la consulta que lanzaste ya no es la actual, descarta la respuesta.

Conviértelo en criterio de revisión: **toda escritura asíncrona en un modelo de UI comprueba que la pregunta que la originó sigue siendo la pregunta actual.** La concurrencia estricta te da el orden de las escrituras; la correspondencia pregunta-respuesta te la da un `guard`.

> **Antipatrón.** `Task { }` suelto en un método de un modelo, disparado desde `onChange`. Sin cancelación, sin correspondencia con la vida de la vista y sin forma de saber cuántos hay en vuelo. Casi siempre es un `.task(id:)` que no se escribió.

## 9.10. Migrar desde Combine

| Combine Swift Concurrency Dónde                    |                                                     |                 |
| -------------------------------------------------- | --------------------------------------------------- | --------------- |
| `ObservableObject` + `@Published`                  | `@Observable`                                       | Capítulo 3      |
| `objectWillChange.sink`, `$prop.sink`              | `Observations` (iOS 26) / `withObservationTracking` | 9.6             |
| `PassthroughSubject` / `CurrentValueSubject`       | `AsyncStream` / propiedad de un `@Observable`       | 9.5             |
| `URLSession.dataTaskPublisher`                     | `URLSession.data(from:)`                            | 9.2             |
| `Timer.publish`, `NotificationCenter.publisher`    | `.values`, `notifications(named:)`                  | 9.4, 9.5        |
| `debounce` + `removeDuplicates` + `switchToLatest` | `.task(id:)` + `Task.sleep`                         | 9.3             |
| `combineLatest`, `merge`, `zip`, `throttle`        | swift-async-algorithms                              | 9.7             |
| `receive(on: DispatchQueue.main)`                  | `@MainActor` en el tipo                             | 9.2             |
| `AnyCancellable` + `store(in:)`                    | La vida de la `Task` (`.task`, `Task.cancel`)       | 9.3             |
| `DispatchQueue.global().async`                     | `@concurrent` o un `actor`                          | Capítulo 8, 9.2 |

Orden de migración que funciona: primero `@MainActor` en los modelos (elimina `receive(on:)` y `DispatchQueue.main`), después `@Observable` (elimina `@Published` y los `sink` de la vista), después las fuentes (`.values` para consumir lo que quede), y por último los *pipelines* con operadores, que pueden esperar años si funcionan.

> **Regla de oro.** El compilador garantiza que dos escrituras no colisionan; no garantiza que la segunda sea la que querías. Cada `await` en un modelo de UI es un punto en el que el mundo puede haber cambiado, y el código que sigue al `await` tiene que preguntárselo.

> **Siguiente paso.** Busca `DispatchQueue.main.async` y `Task {` en tus modelos. Cada uno del primero es un `@MainActor` que falta; cada uno del segundo, un `.task(id:)` que no se escribió o una comprobación tras el `await` que no existe.