# Capítulo 10: Testing

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. Swift Testing (Xcode 16+); *exit tests* y *attachments* requieren Swift 6.2; `Observations` requiere iOS 26 en el *host* de tests. XCTest aparece solo para UI tests.

## 10.1. Qué se prueba en SwiftUI, y qué no

SwiftUI no tiene una API de tests. Lo que tiene es una arquitectura que, si has seguido los capítulos 3 y 5, deja casi toda la lógica fuera de las vistas. Así que la pirámide real es:

| Capa | Qué contiene | Cómo se prueba | Peso |
| :--- | :--- | :--- | :--- |
| **Modelos `@Observable` y actores** | Lógica de negocio, estado, transformaciones | Swift Testing, síncrono o `async` | La mayoría |
| **`Layout`, formateadores, reductores de preferencias** | Funciones puras con entrada y salida | Swift Testing, parametrizado | Bastante |
| **Vistas** | Composición y *binding* | Snapshot (apariencia) e inspección (estructura), con moderación | Poco |
| **Flujos** | Navegación, presentaciones, gestos | XCUITest, solo los críticos | Mínimo |

Si tus tests de vistas son muchos, es una señal de que hay lógica en las vistas que debería estar en modelos.

## 10.2. Swift Testing

```swift
import Testing
@testable import PulseCheckout

@Suite("Checkout")
struct CheckoutModelTests {

    @Test("El total incluye envío cuando no llega al mínimo")
    @MainActor
    func totalConEnvio() {
        let modelo = CheckoutModel(carrito: .prueba(importe: 20))
        #expect(modelo.total == 20 + CheckoutModel.envio)
    }

    @Test("Aplicar cupón inválido lanza")
    @MainActor
    func cuponInvalido() throws {
        let modelo = CheckoutModel(carrito: .prueba(importe: 20))
        #expect(throws: CuponError.noEncontrado) {
            try modelo.aplicar(cupon: "NOEXISTE")
        }
    }
}
```

Las piezas:

- **`#expect`** registra el fallo y sigue; **`#require`** aborta el test si falla (y desenvuelve opcionales: `let pedido = try #require(modelo.pedido)`).
- **`#expect(throws:)`** y **`#require(throws:)`** para errores. No existe una forma `#expect { }` con *closure* para "agrupar" fallos; lo que agrupa fallos es la propia suite.
- **`@MainActor`** en los tests que tocan modelos aislados al `MainActor`. Con el aislamiento por defecto del módulo de tests en Xcode 27, suele ser implícito; escribirlo documenta la intención y evita sorpresas si el módulo de tests tiene otra configuración.
- **`.serialized`** en una suite cuyos tests comparten estado global (un singleton, `UserDefaults`, una base de datos en disco). Por defecto Swift Testing ejecuta en paralelo, y eso es una ventaja solo si tus tests no comparten nada.
- **`.tags(...)`** para filtrar en CI (`.ui`, `.lento`, `.red`).

### Parametrizado

```swift
@Test("Formato de precio", arguments: [
    (1999, "19,99"),
    (0, "0,00"),
    (100_000, "1000,00"),      // Sin asumir separador de millares
])
func precio(centimos: Int, parteNumerica: String) {
    let texto = Precio(centimos: centimos).texto(locale: .es)
    let normalizado = texto
        .replacingOccurrences(of: "\u{00A0}", with: " ")   // Espacio duro → espacio normal
        .replacingOccurrences(of: ".", with: "")            // Separador de millares, si lo hay
    #expect(normalizado.hasSuffix("€"))
    #expect(normalizado.hasPrefix(parteNumerica))
}
```

Cada argumento es un test independiente en el navegador de tests; un fallo no oculta los demás. Con dos colecciones en `arguments:` se prueba el producto cartesiano.

> **No afirmes sobre cadenas localizadas completas.** La primera versión de este test comparaba `texto == "19,99 €"` y fallaba con un informe desconcertante: los dos valores del `Expectation failed` **parecían idénticos**. La causa, invisible a simple vista, eran dos detalles del formateador: un espacio duro (U+00A0) antes del símbolo de moneda en lugar de un espacio normal, y un separador de millares que aparece o no según el locale, el sistema operativo y la versión de ICU. Afirma sobre lo que controlas (el valor numérico, el sufijo de moneda), no sobre la tipografía exacta que produce `Foundation`.

### Asíncrono y *callbacks*

Un test `async` simplemente espera:

```swift
@Test @MainActor
func cargaProducto() async throws {
    let modelo = ProductModel(catalogo: CatalogoStub(producto: .prueba))
    await modelo.cargar(id: "p1")
    #expect(modelo.producto?.id == "p1")
}
```

> **El estado compartido de un test asíncrono necesita un tipo, no una variable local.** `var contador = 0` capturada y mutada dentro de una `Task` no compila bajo concurrencia estricta: dos accesos concurrentes a una variable local no aislada son exactamente lo que Swift 6 impide. La solución no es forzar el compilador; es declarar una clase pequeña (`@MainActor final class Contador { private(set) var valor = 0; func incrementar() { valor += 1 } }`) y capturar esa instancia. Es de las primeras cosas con las que choca quien escribe su primer test con `Task`.

Para código que llama a un *closure* (delegados, notificaciones) en lugar de devolver, `confirmation`:

```swift
@Test
func notificaAlAñadir() async {
    await confirmation("callback de carrito") { confirmar in
        let carrito = Carrito(alCambiar: { confirmar() })
        carrito.añadir(.prueba)
    }
}
```

### Swift 6.2+: *exit tests* y *attachments*

- **`#expect(processExitsWith:) { ... }`** ejecuta el *closure* en un proceso hijo y comprueba cómo termina. Es la forma de probar un `precondition` o un `fatalError` sin que el fallo se lleve por delante el resto de la ejecución. En `Pulse` lo usamos para el caso del capítulo 5: una vista que lee `FeatureFlags` del entorno, evaluada con `ImageRenderer` **sin** inyectarlo. En `cap5-fix` la propiedad es opcional y tiene valor por defecto, así que el hijo termina bien; en `cap5-bug` no lo es, SwiftUI aborta, y el test falla sin tumbar nada más:

```swift
@Test("Sin inyección, la vista no aborta")
func sinInyeccionNoAborta() async {
    await #expect(processExitsWith: .success) {
        _ = await MainActor.run { ImageRenderer(content: VistaSinInyeccion()).cgImage }
    }
}
```

Dos cautelas que vale la pena tomar. La primera: acompáñalo de un gemelo **con** la inyección que también espere `.success`. Si el gemelo fallara, el problema no sería `@Environment` sino el mecanismo con el que fuerzas la evaluación de la vista en el hijo, y el primer test no demostraría lo que crees. La segunda: si alguna vez un `fatalError` tumba tu proceso de tests entero, no culpes al *exit test* que casualmente estaba en marcha. Busca qué test evaluó la vista **fuera** de un proceso hijo: un test de vista que inspecciona un componente sin el entorno que su padre le inyecta produce exactamente ese síntoma, en el proceso principal.
- **`Attachment`** adjunta datos al resultado del test (una imagen, un JSON, el *dump* de un modelo). En snapshot tests, adjuntar la imagen obtenida y la esperada cuando fallan convierte un "no coincide" en algo que se puede mirar en el informe de CI.

## 10.3. Probar modelos `@Observable`

Un modelo `@Observable` se prueba como cualquier clase: se construye, se llama, se comprueba. Lo que a veces hace falta es comprobar **que notifica**, no solo que cambia. Con iOS 26+ en el *host* de tests, `Observations`:

```swift
import Observation   // Sin este import, "Observations" no se encuentra en el scope del test

@Test @MainActor
func elTotalNotificaAlCambiarCantidad() async {
    let modelo = CheckoutModel(carrito: .prueba(importe: 20))
    let totales = Observations { modelo.total }

    var iterador = totales.makeAsyncIterator()
    _ = await iterador.next()                       // Valor inicial
    modelo.carrito.cantidad(de: .prueba, a: 2)
    #expect(await iterador.next() == 40 + CheckoutModel.envio)
}
```

Para *targets* de test que corran en hosts anteriores, `withObservationTracking` con `onChange` da lo mismo en una sola notificación, y es además la forma correcta de probar que un modelo **no** notifica cuando no debería: registra el rastreo antes de la mutación, dispara la mutación, y comprueba que el `onChange` no se ha llamado. Es el patrón que usa el caso del capítulo 8 (§8.8) para demostrar que Observation suprime una notificación cuando el valor nuevo es igual al anterior (capítulo 3, §3.5) — y, importante, **todo test de "esto no notifica" necesita un segundo test de control que confirme que "esto sí notifica"** cuando el valor cambia de verdad. Sin el control, un fallo en el propio mecanismo de rastreo del test (no en el código que pruebas) produce un falso positivo: el test pasa porque nada lo hizo fallar nunca, en ninguna de las dos variantes.

Las dependencias entran por `init` (capítulo 5). Un `protocol CatalogoProveedor: Sendable` con una implementación real (`actor CatalogoService`) y un *stub* de tests es todo lo que hace falta; los tests no necesitan red, y el compilador se encarga de que el *stub* sea seguro para concurrencia.

## 10.4. Probar un `Layout`

`sizeThatFits` y `placeSubviews` necesitan `LayoutSubviews`, que solo SwiftUI puede construir. Lo que sí se prueba es la función pura que hace el trabajo (capítulo 7):

```swift
@Test("El flow salta de línea cuando no cabe", arguments: [280.0, 320.0, 390.0])
func flowSaltaDeLinea(ancho: CGFloat) {
    let tamaños = Array(repeating: CGSize(width: 100, height: 30), count: 5)
    let marcos = FlowLayout(espaciado: 8).distribuir(tamaños, anchoContenedor: ancho)
    let porLinea = Int((ancho + 8) / 108)
    #expect(marcos[porLinea].minY > 0)
    #expect(marcos.allSatisfy { $0.maxX <= ancho })
}
```

Si el algoritmo no está en una función pura, es la primera refactorización que te pide el test.

## 10.5. Vistas: snapshots e inspección

### Snapshot (apariencia)

`swift-snapshot-testing` (Point-Free) puede integrarse con Swift Testing; el adaptador concreto y la versión del paquete forman parte de la configuración del repositorio. En el ejemplo, `assertSnapshot` es la aserción de snapshot y el test sigue siendo un `@Test`.

```swift
import SnapshotTesting
import Testing

@Test @MainActor
func fichaProductoAccesible() {
    let vista = FichaProducto(producto: .prueba)
        .environment(\.dynamicTypeSize, .accessibility3)
        .frame(width: 320)
    assertSnapshot(of: vista, as: .image(perceptualPrecision: 0.98))
}
```

Reglas para que no se conviertan en ruido: un tamaño y un `dynamicTypeSize` fijos por snapshot; `perceptualPrecision` en lugar de igualdad exacta (el *antialiasing* cambia entre SDKs); las referencias se regeneran solo en la máquina de CI, con el mismo simulador; y cada snapshot documenta **qué** protege (Dynamic Type, modo oscuro, RTL), porque un snapshot sin propósito es una referencia que alguien regenerará sin mirar.

### Inspección (estructura)

`ViewInspector` recorre la jerarquía de una vista de forma síncrona y permite afirmar cosas como "hay un `Button` con este texto" o "el `Toggle` está ligado a esta propiedad". Es caja blanca: se rompe cuando cambias la estructura aunque la apariencia no cambie. Úsalo para *bindings* y acciones, no para layout, y acepta que no cubre todas las APIs nuevas de cada SDK el día de lanzamiento.

## 10.6. Code review: el test que habría parado el checkout

El bug del capítulo 3 —el formulario de checkout que se vacía cuando aparece el banner— pasó todos los tests. Probaban `CheckoutModel`, y `CheckoutModel` funcionaba. Lo que fallaba era quién poseía el modelo, y eso ningún test de modelo lo ve.

Escribir el test que sí lo detecta es más difícil de lo que parece, y las dos formas obvias de intentarlo fallan por razones distintas. Vale la pena verlas: los dos fallos son en sí mismos una lección sobre el grafo de atributos.

### Primer intento: comparar identidades con `inspect().actualView()`

```swift
let antes = try raiz.inspect().find(CheckoutView.self).actualView().modeloParaTests
antes.titular = "Ana"
flags.bannerPromo = true
let despues = try raiz.inspect().find(CheckoutView.self).actualView().modeloParaTests
#expect(despues === antes)
```

Falla en las **dos** variantes, `cap3-bug` y `cap3-fix`. La causa: `raiz.inspect()`, sin hostear la vista con `ViewHosting`, no crea un nodo en el grafo de atributos (capítulo 2). Cada llamada a `.inspect()` construye la `struct` de cero y lee el `@State` fuera de cualquier pase de render, así que `antes` y `despues` son siempre instancias distintas, tenga el bug o no. El test estaba comprobando la persistencia de `@State` en un entorno donde `@State` no persiste.

### Segundo intento: contar instancias con `ViewHosting`

Montar la vista con `ViewHosting.host(view:)` arregla la falta de nodo, pero abre un segundo problema si el criterio sigue siendo "cuántos modelos se han construido": con `@State` **asignado en el `init`** (la forma que recomienda el capítulo 3, §3.3, para un valor que llega por parámetro), el inicializador del modelo se ejecuta en **cada** reconstrucción de la `struct`, y el objeto recién construido se descarta. El contador sube igual en `cap3-bug` y en `cap3-fix`: seis construcciones en las dos, para cinco actualizaciones del padre. Contar instancias no distingue nada, aunque el `@State` esté haciendo su trabajo correctamente (capítulo 3, §3.3 y §3.4).

### El test que sí funciona: qué instancia usa la vista

La pregunta correcta no es "¿cuántas veces se ha construido el modelo?" sino "¿cuál de las instancias construidas está usando la vista ahora?":

```swift
@Test("La vista sigue usando el mismo modelo cuando el padre se actualiza", .tags(.bug))
@MainActor
func mismoModeloEnUso() async throws {
    RegistroCheckout.reiniciar()

    let flags = FeatureFlags(bannerPromo: false)
    let raiz = CheckoutHost(flags: flags)           // Su body SÍ lee flags.bannerPromo (ver nota)
    ViewHosting.host(view: raiz)
    defer { ViewHosting.expel() }
    try await Task.sleep(for: .milliseconds(50))    // Deja que SwiftUI monte el primer render

    let primero = try #require(RegistroCheckout.enUso)

    for _ in 0..<5 {
        flags.bannerPromo.toggle()                  // El padre se actualiza
        try await Task.sleep(for: .milliseconds(30))
    }

    #expect(RegistroCheckout.enUso == primero)      // Sigue siendo la primera instancia
}
```

`RegistroCheckout.enUso` se actualiza desde la primera línea del `body` de `CheckoutView` (`RegistroCheckout.enUso = ObjectIdentifier(modelo)`), así que registra qué objeto está usando la vista en cada render, no cuántos se han creado. En `cap3-fix` pasa: siempre la misma instancia. En `cap3-bug` falla: cada render usa la que se acaba de construir.

**Un requisito que no es opcional para que esto reproduzca el bug:** el padre de prueba (`CheckoutHost`) tiene que **leer de verdad** el dato que cambia (`flags.bannerPromo`) en su propio `body`. Si el padre solo pasa `flags` por el entorno sin leerlo, cambiar el flag invalida a `CheckoutView` pero no reconstruye la `struct` del padre, y el bug del capítulo 3 no se dispara: sobrevive incluso `private let modelo`. El bug del checkout no lo dispara cualquier actualización, sino una que **reconstruya la `struct`** de la vista que posee el modelo, es decir, una que invalide a un ancestro. Es la razón por la que, en producción, tardó meses en reproducirse: solo aparecía cuando el banner de promoción (que sí vive en un ancestro real) cambiaba de estado.

**Cada `@State` que guarda una clase merece un test que compruebe que sobrevive a una actualización de un ancestro real, verificando qué instancia usa la vista y no cuántas se han construido.** Es barato de escribir una vez que sabes dónde están las dos trampas, y cubre una familia de bugs que ningún test de modelo puede detectar.

## 10.7. El repositorio como parte del libro

Las reglas del repositorio `Pulse` (documento de diseño):

1. Cada listado del libro existe literalmente en el repositorio y compila en Xcode 27 con *Strict Concurrency: Complete*.
2. Cada caso de *code review* tiene sus dos variantes, `capN-bug` y `capN-fix`, para ejecutarlas y compararlas. El criterio al que aspiran todos es tener además un test que falle en la primera y pase en la segunda; hoy lo cumplen seis (capítulos 2, 3, 5, 7, 8 y 9). Los de los capítulos 4 y 6 dependen de lo que se ve en pantalla —un texto truncado, una animación que salta— y se comprueban en la app, no en un test.
3. CI público con Xcode 27; el *badge* en la página de venta.
4. **Dependencias con versión exacta y `Package.resolved` en el repositorio.** Un rango como `from: "0.10.0"` deja entrar cualquier versión posterior, incluida una publicada rota. Nos pasó durante la verificación de este mismo libro: una versión nueva de una dependencia de tests declaraba una plataforma que su propio manifiesto no podía reconocer, y el repositorio dejó de compilar sin que nadie hubiera tocado una línea. En una app en desarrollo, los rangos tienen sentido porque quieres las correcciones. En un repositorio que tiene que reproducir un resultado concreto —el que acompaña a un libro, o el de un informe de verificación—, la versión exacta es la única que garantiza que dentro de un año obtengas lo mismo que hoy.

No es un extra: es lo que hace verificable cada afirmación de los capítulos anteriores.

**Un experimento sobre ciclo de vida de vistas no mide nada si la vista que hosteas no se reconstruye de verdad.** Una vista raíz montada directamente en el test nunca se reconstruye, y un padre que guarda a su hija en una propiedad almacenada (en vez de construirla dentro de su `body`) tampoco. Las dos formas dan resultados que **parecen** una medición y son en realidad la ausencia de una: compilan, se ejecutan, y devuelven el mismo número en las dos variantes del código que intentas distinguir. Antes de confiar en un experimento de este tipo, comprueba con un caso de control que el fenómeno que quieres medir ocurre cuando debería (§10.3).

> **Regla de oro.** Prueba modelos y funciones puras con Swift Testing; prueba vistas solo para lo que los modelos no pueden ver (ownership de estado, *bindings*, apariencia con Dynamic Type). Si necesitas muchos tests de vista, mueve lógica al modelo.

> **Siguiente paso.** Escribe un test para el bug que más te haya costado en el último año. Si no puedes escribirlo, ese es el problema de arquitectura que hay que resolver primero.
