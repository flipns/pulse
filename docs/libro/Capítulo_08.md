# Capítulo 8: Rendimiento

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. Instruments 26+ para la plantilla SwiftUI; Xcode 27 para la métrica de *hitches* ampliada; `OSSignposter` requiere iOS 15. La sección 8.7 trata tiempo de compilación, no de ejecución.

## 8.1. Tres problemas distintos que parecen uno

"La app va lenta" son, en SwiftUI, al menos tres problemas con tres diagnósticos y tres soluciones:

| Problema | Síntoma | Se ve en | Se arregla en |
| :--- | :--- | :--- | :--- |
| **Demasiadas actualizaciones** | `body` que se ejecutan sin interacción; batería | *Update Groups* y *Cause & Effect Graph* | El modelo: granularidad de observación, identidad |
| **Actualizaciones caras** | Tirones al tocar o al hacer *scroll* | *Long View Body Updates*, Time Profiler | La vista: sacar trabajo del `body` |
| **Renderizado caro** | Tirones aunque los `body` sean baratos | Métrica de *hitches*, Core Animation | Composición: `drawingGroup`, menos capas, animaciones de render |

Antes de tocar código, decide cuál de los tres tienes. Optimizar el equivocado es la forma más común de perder una semana.

## 8.2. Instruments: la plantilla SwiftUI

Perfil en **dispositivo real**, en *release* o al menos con optimizaciones (`-O`); el simulador y las *builds* de depuración mienten sobre rendimiento.

- **Update Groups.** Cada grupo es un ciclo de reconciliación (capítulo 3). Grupos continuos sin que el usuario haga nada delatan un estado que cambia en bucle: un `onChange` que escribe lo que observa, un `Timer` más frecuente de lo necesario, un `@Observable` que se muta desde una respuesta de red por cada elemento en lugar de una vez, o un modelo que publica el *payload* del servidor tal cual (§8.8): Observation no notifica si el valor nuevo es igual al anterior (capítulo 3, §3.5), así que si hay Update Groups en reposo es porque el valor **sí** cambia, y a veces cambia por un campo que a nadie le importa.
- **Long View Body Updates.** Los `body` que superan el presupuesto de un *frame* (16,6 ms a 60 Hz, 8,3 ms a 120 Hz). Casi siempre hay formateo, ordenación, filtrado o construcción de objetos dentro del `body`.
- **Cause & Effect Graph.** Selecciona una actualización y verás la cadena completa desde el dato que cambió hasta cada `body` ejecutado. Responde a "¿por qué esta vista?" con la propiedad exacta.

Complementos:

- **Time Profiler**, filtrado por tu módulo, para ver qué función concreta consume dentro de un `body` largo. En Xcode 27 la pila muestra los saltos de actor, así que un `await` que pasa por el `MainActor` sin necesidad aparece como tal.
- **Hitches** (Xcode 27). La métrica cubre ahora tirones fuera del *scroll* (presentaciones, animaciones, efectos Liquid Glass). Un *hitch* es un *frame* que llegó tarde; la métrica te dice cuántos, cuánto y dónde.
- **Memory Graph** (Xcode 27) para lo que es: un grafo de **objetos** y quién retiene a quién. Ahí encuentras los modelos que un `Task` sin cancelar mantiene vivos o las filas de `List` que creías destruidas, porque siguen teniendo dueño. No lo confundas con una ventana al grafo de atributos de SwiftUI: la relación entre un cambio de dato y los `body` que provoca la da el *Cause & Effect Graph* del instrumento SwiftUI, no el Memory Graph.

## 8.3. `OSSignposter`: medir lo tuyo

Para intervalos que Instruments no conoce (tu capa de red, tu `Layout`, tu parser), `OSSignposter` (iOS 15+) dibuja intervalos en la línea de tiempo:

```swift
import os

// `nonisolated` no es opcional aquí: ver el recuadro de debajo.
nonisolated enum Signposts {
    static let feed = OSSignposter(subsystem: "app.pulse", category: "Feed")
}

@Observable @MainActor
final class FeedModel {
    private(set) var visibles: [ArticuloPresentado] = []
    private let repositorio: any FeedRepository

    func cargar() async {
        let id = Signposts.feed.makeSignpostID()
        let estado = Signposts.feed.beginInterval("Cargar feed", id: id)
        defer { Signposts.feed.endInterval("Cargar feed", estado) }

        await aplicar((try? await repositorio.articulos()) ?? [])   // §8.8
    }
}
```

> **Decláralo `nonisolated`.** Con aislamiento por defecto en `MainActor`, ese `static let` queda aislado aunque `OSSignposter` sea `Sendable`, y entonces no puedes leerlo desde un `Layout` (capítulo 7) ni desde una función `@concurrent` (§8.5). El capítulo 9 (§9.1) explica por qué `Sendable` y `nonisolated` son cosas distintas y por qué aquí hacen falta las dos.

`beginInterval` devuelve un estado que se pasa a `endInterval`; `defer` garantiza el cierre aunque haya errores. Un `id` por intervalo evita colisiones cuando dos cargas se solapan. Los *signposts* no van dentro de un `body`: el `body` ya lo mide Instruments, y meter un intervalo ahí (con un `let _ =`) añade ruido y una llamada más a algo que estás intentando abaratar.

Dentro de un `Layout` sí tienen sentido, porque `sizeThatFits` y `placeSubviews` son funciones normales y quieres contar cuántas veces se llaman por pase (capítulo 7).

## 8.4. `body` baratos

Un `body` se ejecuta cada vez que cualquiera de sus dependencias cambia. Todo lo que hay dentro se repite. Las cosas que no deben estar ahí:

- **Formateo** de fechas, números y monedas. Un `DateFormatter` cuesta crearlo y cuesta usarlo. `Text(fecha, format: .dateTime)` es mejor que construir el `String` a mano, pero lo mejor es que el modelo entregue el texto ya formateado.
- **Ordenar y filtrar.** `articulos.filter { }.sorted { }` en el `body` se ejecuta en cada actualización, incluida la que provoca el tecleo de un carácter en la búsqueda. El resultado vive en el modelo, recalculado cuando cambian sus entradas.
- **Construir objetos.** `let formatter = ...`, `let modelo = ...`. Capítulo 3.
- **Trabajo síncrono de disco o red.** Nunca. Y ojo con la falsa sensación de seguridad: el compilador comprueba **aislamiento**, no bloqueo. `Data(contentsOf:)` o `FileHandle.readToEnd()` siguen siendo síncronas y siguen compilando dentro de un `body`; simplemente bloquean el hilo que las ejecuta, que ahí es el principal. Nadie te va a avisar.

La regla que lo resume: **el `body` transforma estado en vistas; no calcula estado**. Un tipo `ArticuloPresentado` con `titulo`, `fechaTexto`, `precioTexto` ya resueltos, construido una vez por artículo en el modelo, es la diferencia entre 40 `body` baratos y 40 `body` que formatean tres cosas cada uno.

### Vistas `Equatable`

Cuando una subvista recibe parámetros que no cambian pero el padre se actualiza por otra razón, SwiftUI reejecuta su `body` de todas formas (los parámetros son `struct`; el *framework* no sabe si son iguales). Con `.equatable()` sobre una vista conforme a `Equatable`, SwiftUI compara antes y se salta el `body` si no ha cambiado nada:

```swift
struct FilaFeed: View, Equatable {
    let articulo: ArticuloPresentado         // Equatable
    var body: some View { /* ... */ }
}

FilaFeed(articulo: a).equatable()
```

Funciona cuando la comparación es más barata que el `body` y los parámetros son valores (no `@Observable`, que ya se observan por propiedad).

## 8.5. Trabajo pesado: `@concurrent`

Marcar una función `async` no la saca del `MainActor`, y `nonisolated async` tampoco: con la configuración que asume este libro, hereda el actor de quien la llama. La anotación que sí pide explícitamente el pool de hilos es **`@concurrent`**, y es la que necesitas aquí. El modelo completo de aislamiento está en el capítulo 9 (§9.1); para este capítulo basta con la regla práctica:

```swift
@Observable @MainActor
final class FeedModel {
    // ...
    @concurrent
    private nonisolated func presentar(_ crudos: [Articulo]) async -> [ArticuloPresentado] {
        crudos.map(ArticuloPresentado.init)   // Formateo en segundo plano
    }
}
```

Los parámetros y el resultado deben ser `Sendable`, y si son tipos que defines tú, además `nonisolated` (capítulo 9, §9.2). Es el patrón para parseo, formateo masivo, ordenaciones grandes y procesado de imágenes; para I/O (red, disco), un `actor` propio (capítulo 9).

## 8.6. Renderizado

Cuando los `body` son baratos y sigue habiendo tirones, el coste está en Core Animation: demasiadas capas, sombras, desenfoques, máscaras.

- **`drawingGroup()`** aplana el subárbol en una sola textura Metal renderizada fuera de pantalla. Vale para composiciones vectoriales complejas (gráficos, muchos `Shape` con gradientes y sombras). No vale para texto (se rasteriza y pierde nitidez con Dynamic Type y zoom) ni para controles interactivos.
- **Animaciones de render, no de layout.** `opacity`, `scaleEffect`, `offset`, `rotationEffect` se resuelven en composición. `frame`, `padding`, `font` invalidan el layout en cada *frame* (capítulo 6).
- **Liquid Glass (iOS 26+)** es un efecto de composición caro. Un `glassEffect` por barra está bien; uno por fila de una lista, no. La métrica de *hitches* de Xcode 27 lo muestra como tal.
- **Sombras y desenfoques** en filas de listas: trátalos como candidatos a investigar cuando la métrica de *hitches* señale composición o renderizado; no atribuyas el coste a una sola propiedad sin perfilar.

## 8.7. Tiempo de compilación

Un problema de rendimiento que no sale en Instruments: el de compilar. Con `ContentBuilder` (Xcode 27), los bloques de builder ya no obligan a que su contenido conforme a `View` y el compilador no ensaya sobrecargas indistinguibles, así que los `body` grandes se comprueban sustancialmente más rápido. Tres reglas siguen aplicando:

1. **`body` de más de ~40 líneas se extrae** en subvistas o propiedades computadas `some View`. No por estilo: porque el *type-checker* trabaja sobre la expresión completa.
2. **`if / else if` de muchas ramas dentro de un builder** se saca a una función anotada con el builder correspondiente. TN3211 muestra precisamente un caso de Swift Charts en *deployment targets* anteriores a iOS 27 donde una expresión con suficientes ramas condicionales puede disparar el *type-checker*. Trátalo como un patrón de diagnóstico, no como una frontera universal de "diez ramas": extrae el contenido cuando el compilador lo señale y usa `@ChartContentBuilder` para aislar la expresión.
3. **`-Xfrontend -warn-long-expression-type-checking=100`** en *Other Swift Flags* de la configuración de depuración avisa de cada expresión que tarde más de 100 ms. Es la única forma de ver el problema antes de que sea un `body` de dos minutos.

## 8.8. Code review: el feed que da tirones

En `Pulse`, el feed muestra 400 artículos y refresca cada segundo contra el servidor. Está en `Feed/FeedList.swift`.

### El código que pasó la revisión

```swift
@Observable @MainActor
final class FeedModel {
    var articulos: [Articulo] = []          // El payload del servidor, tal cual
    private let repositorio: any FeedRepository

    func aplicar(_ crudos: [Articulo]) async {
        articulos = crudos
    }
}

struct FeedList: View {
    let modelo: FeedModel

    var body: some View {
        List(modelo.articulos.filter { !$0.oculto }.sorted { $0.fecha > $1.fecha }) { articulo in
            FeedRow(articulo: articulo, formatter: RelativeDateTimeFormatter())
        }
    }
}

struct FeedRow: View {
    let articulo: Articulo
    let formatter: RelativeDateTimeFormatter

    var body: some View {
        VStack(alignment: .leading) {
            Text(articulo.titulo).font(.headline)
            Text(formatter.localizedString(for: articulo.fecha, relativeTo: .now))
                .font(.caption)
        }
        .shadow(radius: 4)
    }
}
```

### El diagnóstico, en orden

**1. Update Groups: un ciclo por segundo con la app en reposo.**

El *Cause & Effect Graph* señala `FeedModel.articulos`. Y aquí hay un matiz que conviene entender antes de tocar nada, porque cambia la solución.

Observation **compara antes de notificar** (capítulo 3, §3.5): si el array nuevo fuera igual al anterior, no habría notificación y no habría nada que arreglar. Si la hay, es porque el array **no** es igual. Mirando el modelo de datos:

```swift
struct Articulo: Equatable {
    let id: UUID
    var titulo: String
    var fecha: Date
    var esDestacado: Bool
    var oculto: Bool
    var vistas: Int          // Contador del servidor. La interfaz no lo muestra.
}
```

`vistas` sube con cada visita de cualquier usuario. El servidor devuelve los mismos 400 artículos con un contador distinto, el array difiere, y las 400 filas se invalidan por un número que nadie ve.

Este es el problema de verdad, y no es "reasignar lo mismo": es que **la noción de "ha cambiado" del modelo es más gruesa que la de la interfaz**.

**2. Long View Body Updates: `FeedList.body` muy por encima del presupuesto de un *frame*.**

Time Profiler: `filter` + `sorted` sobre 400 artículos en cada actualización, y un `RelativeDateTimeFormatter()` construido por fila.

**3. Hitches que persisten** tras arreglar lo anterior. La traza apunta a la composición de cada fila y a la sombra por fila.

### La solución

```swift
@Observable @MainActor
final class FeedModel {
    private(set) var visibles: [ArticuloPresentado] = []   // La proyección que la UI consume

    private let repositorio: any FeedRepository

    /// El reloj de la presentación: con qué fecha se construyen los textos relativos.
    /// No es `Date.now` en cada ping. Ver la nota de abajo.
    private var referenciaTemporal: Date

    func aplicar(_ crudos: [Articulo]) async {
        let nuevos = await Self.presentar(crudos, ahora: referenciaTemporal)   // (1) Fuera del MainActor
        guard nuevos != visibles else { return }                                // (2) Comparar lo que la UI muestra
        visibles = nuevos
    }

    @concurrent
    private nonisolated static func presentar(_ crudos: [Articulo], ahora: Date) async -> [ArticuloPresentado] {
        // Un solo formateador y una sola fecha de referencia para todo el lote: sin eso la
        // proyección no sería determinista y compararla en (2) no serviría de nada.
        ArticuloPresentado.proyectar(
            crudos.filter { !$0.oculto }.sorted { $0.fecha > $1.fecha },  // Sin `vistas`
            ahora: ahora
        )
    }
}

struct FeedList: View {
    let modelo: FeedModel
    var body: some View {
        List(modelo.visibles) { FilaFeed(articulo: $0).equatable() }   // (3)
    }
}

struct FilaFeed: View, Equatable {
    let articulo: ArticuloPresentado
    var body: some View {
        VStack(alignment: .leading) {
            Text(articulo.titulo).font(.headline)
            Text(articulo.fechaRelativa).font(.caption)
        }
        .background(.background, in: .rect(cornerRadius: 12))          // (4)
    }
}
```

1. Filtrar, ordenar y formatear ocurre **una vez por respuesta**, fuera del `MainActor`. El `body` deja de calcular.
2. La comparación es sobre la **proyección**, no sobre el *payload*. Un `guard crudos != ultimosCrudos` no habría servido de nada: el *payload* difiere en cada *ping* por culpa de `vistas`. Al comparar `[ArticuloPresentado]`, un *ping* que solo mueve contadores produce una proyección idéntica y la asignación no llega a ocurrir; y si llegara, Observation la suprimiría igualmente (capítulo 3, §3.5).
3. `.equatable()` evita reejecutar 400 `body` cuando lo que cambia no es su artículo.
4. La sombra por fila se sustituye por un fondo; si Diseño la quiere, va en el contenedor.

**Qué está verificado y qué no.** Lo que el repositorio demuestra es la parte lógica del arreglo, que no depende del hardware: con el *payload* crudo, un *ping* que solo cambia `vistas` invalida a los observadores; con la proyección, no. Es el test `FeedModelTests` de `Pulse`, que falla en `cap8-bug` y pasa en `cap8-fix`, con un segundo test de control que confirma que un cambio que la interfaz sí muestra sigue invalidando.

Lo que **no** damos es una cifra de fotogramas por segundo. Medir el efecto real sobre el *scroll* exige un dispositivo físico con la versión del sistema del libro, y no vamos a sustituirlo por el simulador: como se dice en §8.2, el simulador miente sobre rendimiento, y una cifra tomada ahí contradiría lo que este mismo capítulo enseña. Si tienes el dispositivo, el protocolo es sencillo: *Release*, plantilla SwiftUI, diez segundos en reposo y veinte de *scroll*, tres repeticiones de cada variante. Lo que deberías ver es que los *Update Groups* en reposo desaparecen con el arreglo; cuánto mejora el *scroll* depende de tu dispositivo, y es exactamente lo que conviene que midas tú.

### Un segundo reloj escondido

Queda un detalle que es fácil pasar por alto y que anula todo lo anterior. La proyección incluye `fechaRelativa`, un texto del tipo "hace 3 min". Si se construyera con `Date.now` **en cada ping**, dos respuestas idénticas del servidor proyectadas a uno y otro lado de un umbral ("ahora" → "hace 1 min") darían textos distintos, la comparación detectaría un cambio y las 400 filas se invalidarían igual. Habríamos cambiado un campo que la interfaz no muestra (`vistas`) por otro que sí muestra pero que nadie ha pedido refrescar.

Por eso el modelo guarda una **referencia temporal** propia y proyecta siempre contra ella. Son dos relojes distintos:

- El **reloj de los datos** avanza cuando el servidor manda algo nuevo. Lo dispara `aplicar(_:)`.
- El **reloj de la presentación** avanza cuando decidimos refrescar los textos, con un temporizador lento de un minuto. Lo dispara `refrescarTextosRelativos(_:)`, y entonces sí invalida, a propósito.

La regla general: **cuando compares proyecciones para decidir si notificar, todo lo que entre en la proyección tiene que ser función de datos que controles**. Una hora leída del sistema dentro de la proyección es una entrada oculta que cambia sola, y convierte tu comparación en una moneda al aire.

> **Antipatrón.** Publicar en el modelo el *payload* del servidor tal cual. Cualquier campo que el backend toque (contadores, marcas de tiempo, telemetría) invalida vistas que no lo muestran. Publica la proyección que la interfaz consume, y compárala.

> **Regla de oro.** El `body` transforma estado en vistas; el modelo calcula el estado, una vez, cuando cambia **algo que la interfaz muestra**. Las dos mitades de esa frase tienen un caso de este capítulo detrás.

> **Siguiente paso.** Perfila tu pantalla más pesada en un dispositivo real con la plantilla SwiftUI, sin tocar nada, durante treinta segundos. Si hay Update Groups en reposo, mira primero qué campo del modelo cambia y si la interfaz lo usa; si no, por el `body` más largo; si tampoco, por los *hitches*. En ese orden.
