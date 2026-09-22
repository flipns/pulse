# Capítulo 7: Layout avanzado y geometría

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. `Layout` (iOS 16), `onGeometryChange` (SDK iOS 18, *back-deploy*) y espacios de coordenadas nombrados (iOS 17) están cubiertos; 7.8 marca lo que requiere iOS 27.

## 7.1. Cuándo un `Layout` propio

El capítulo 4 cubre la mayoría de las pantallas con stacks, `frame`, `ViewThatFits` y `containerRelativeFrame`. Un grupo menor de casos son distribuciones que ningún contenedor estándar expresa: un *flow* de etiquetas que salta de línea, una *masonry*, una rueda de avatares, un teclado con teclas de distinto ancho. Ahí hay dos caminos:

| Camino | Cuándo | Coste |
| :--- | :--- | :--- |
| **Protocolo `Layout`** (iOS 16+) | Siempre que puedas | Un tipo, dos métodos, sin estado en la vista |
| **`GeometryReader` + preferencias** | Solo pre-iOS 16 o cuando necesitas insertar vistas que no son subvistas | Varios modificadores, estado intermedio, riesgo de bucles |

Con nuestro mínimo de iOS 18, el segundo camino es *legacy* y aparece aquí porque lo vas a encontrar en código existente.

## 7.2. El protocolo `Layout`

Un `Layout` es un contenedor: recibe la propuesta del padre, mide a sus hijos y los coloca. Dos métodos obligatorios:

```swift
struct FlowLayout: Layout {
    var espaciado: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.replacingUnspecifiedDimensions().width
        let marcos = distribuir(subviews.map { $0.sizeThatFits(.unspecified) }, anchoContenedor: ancho)
        return marcos.reduce(CGRect.zero) { $0.union($1) }.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let marcos = distribuir(subviews.map { $0.sizeThatFits(.unspecified) }, anchoContenedor: bounds.width)
        for (marco, subvista) in zip(marcos, subviews) {
            subvista.place(
                at: CGPoint(x: bounds.minX + marco.minX, y: bounds.minY + marco.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(marco.size)
            )
        }
    }

    func distribuir(_ tamaños: [CGSize], anchoContenedor: CGFloat) -> [CGRect] {   // internal: se prueba en el capítulo 10
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
```

Uso: `FlowLayout(espaciado: 6) { ForEach(etiquetas) { Etiqueta($0) } }`. El contenido es un `@ViewBuilder` normal: `if`, `ForEach` y `Group` funcionan, y `subviews` refleja lo que hay en cada momento.

Detalles que no son opcionales:

- **`replacingUnspecifiedDimensions()`** sustituye `nil` por **10×10** por defecto. Si el padre propone `nil` en ancho (un `ScrollView` horizontal, un `fixedSize`), tu *flow* calculará un contenedor de 10 pt de ancho. Decide qué significa "sin restricción" para tu layout y pásalo con `by:`.
- **`place(at:anchor:proposal:)`**, en ese orden, y `anchor` por defecto es `.center`. Si calculas orígenes, di `.topLeading`.
- **Las coordenadas de `bounds` no empiezan en cero.** Suma `bounds.minX` y `bounds.minY`.
- **`sizeThatFits` y `placeSubviews` se llaman por separado**, posiblemente varias veces por pase, con propuestas distintas. Cualquier trabajo que hagas en uno lo repites en el otro. De ahí la caché (7.3).
- **Los requisitos del protocolo son `nonisolated`, y eso gana sobre el aislamiento por defecto del módulo.** Aunque tu app tenga *Default Actor Isolation = MainActor*, `sizeThatFits` y `placeSubviews` se compilan sin aislamiento: es el propio protocolo quien lo exige. Eso dice algo sobre el aislamiento de **tus métodos**, no sobre en qué ejecutor corre internamente el motor de layout de SwiftUI, que es un detalle de implementación que Apple no documenta y contra el que no conviene diseñar. La consecuencia práctica, que es la que importa: desde estos métodos no puedes leer nada aislado al `MainActor` (un modelo `@Observable`, una propiedad `static` normal del módulo, un `Logger` compartido sin marcar). Es una de las razones por las que la caché (7.3) es prácticamente el único estado que un `Layout` puede tener.

### `LayoutSubview`

El *proxy* de cada hijo. Lo que sabe decirte:

| API | Para qué |
| :--- | :--- |
| `sizeThatFits(_:)` | Tamaño para una propuesta. `.zero`, `.unspecified` e `.infinity` dan mínimo, ideal y máximo. |
| `dimensions(in:)` | Tamaño **y** guías de alineación (`ViewDimensions`) para una propuesta. Necesario para alinear por *baseline*. |
| `priority` | El `layoutPriority` del hijo (iOS 13+). |
| `spacing` | Su espaciado preferido; `spacing.distance(to:along:)` lo combina con el de otro hijo. |
| `subview[Clave.self]` | Un valor de layout personalizado (abajo). |

### Valores de layout personalizados

Un hijo puede declarar una intención que el contenedor lee, como un valor de entorno que sube en lugar de bajar:

```swift
struct OcupaLinea: LayoutValueKey { static let defaultValue = false }

extension View {
    func ocupaLineaCompleta(_ v: Bool = true) -> some View { layoutValue(key: OcupaLinea.self, value: v) }
}

// En el layout:
if subview[OcupaLinea.self] { /* saltar de línea antes y después */ }
```

### Guías de alineación del contenedor

`explicitAlignment(of:in:proposal:subviews:cache:)` permite que tu contenedor responda a `.firstTextBaseline` o a una guía propia cuando lo alineen desde fuera. Sin implementarlo, el contenedor se alinea por sus bordes.

## 7.3. La caché

`Cache` es un tipo asociado (por defecto `()`) que el layout crea con `makeCache(subviews:)` y que SwiftUI le pasa `inout` a cada método. Se invalida (llama a `updateCache`) cuando cambia la colección de subvistas.

```swift
struct FlowLayout: Layout {
    struct Cache {
        var tamaños: [CGSize] = []
        var ultimoAncho: CGFloat? = nil
        var marcos: [CGRect] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(tamaños: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.tamaños = subviews.map { $0.sizeThatFits(.unspecified) }
        cache.ultimoAncho = nil
    }

    private func marcos(para ancho: CGFloat, cache: inout Cache) -> [CGRect] {
        if cache.ultimoAncho != ancho {
            cache.marcos = distribuir(cache.tamaños, anchoContenedor: ancho)
            cache.ultimoAncho = ancho
        }
        return cache.marcos
    }
    // sizeThatFits y placeSubviews llaman a marcos(para:cache:)
}
```

Dos avisos. Primero: la caché no sobrevive a un cambio de subvistas, así que en un `ForEach` cuyos datos cambian a menudo ahorra menos de lo que parece. Segundo: **no implementes caché hasta que Instruments te diga que la necesitas**. El caso 7.9 muestra cómo saberlo.

## 7.4. Medir: `GeometryReader` y `onGeometryChange`

`GeometryReader` acepta la propuesta, la reporta y expone un `GeometryProxy` con `size`, `safeAreaInsets` y `frame(in:)`. Como contenedor de contenido rompe el flujo (capítulo 4); como herramienta de medición en `background` u `overlay` es inocua.

Para **reaccionar** a una medida sin `GeometryReader`, el modificador correcto es `onGeometryChange(for:of:action:)`:

```swift
Text(resumen)
    .onGeometryChange(for: CGSize.self) { proxy in
        proxy.size                                  // Qué medir
    } action: { tamaño in
        desborda = tamaño.width > anchoMaximo       // Qué hacer, ya en MainActor
    }
```

El *closure* `of:` transforma el `GeometryProxy` en un valor comparable; `action` se ejecuta cuando ese valor cambia. Es la sustitución directa del patrón `GeometryReader` + `PreferenceKey` + `onPreferenceChange` para una sola vista.

## 7.5. Preferencias: información que sube

Cuando varias subvistas tienen que comunicar algo a un ancestro (sus tamaños, sus posiciones, cuál está seleccionada), el mecanismo son las **preferencias**. Fluyen hacia arriba y se combinan con un reductor:

```swift
struct TamañosKey: PreferenceKey {
    static let defaultValue: [Articulo.ID: CGSize] = [:]
    static func reduce(value: inout [Articulo.ID: CGSize], nextValue: () -> [Articulo.ID: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func reportarTamaño(id: Articulo.ID) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(key: TamañosKey.self, value: [id: proxy.size])
            }
        }
    }
}

// Ancestro:
.onPreferenceChange(TamañosKey.self) { tamaños in
    Task { @MainActor in self.tamaños = tamaños }
}
```

> **Advertencia (Swift 6).** El *closure* de `onPreferenceChange` es `nonisolated`: no está aislado al `MainActor`, así que escribir en un `@State` desde él puede requerir un salto explícito, como el `Task { @MainActor in }` de arriba.
>
> Conviene conocer la historia, porque hay mucho código y muchas respuestas de internet escritas sobre una versión intermedia: en las primeras versiones del SDK de iOS 18 ese *closure* exigía además `@Sendable`, lo que provocaba diagnósticos de concurrencia en código que no los merecía. Ese requisito se relajó en iOS 18.4 y la firma actual ya no lo lleva. Si te encuentras con un `@Sendable` forzado o con un `MainActor.assumeIsolated` puesto para callar al compilador, probablemente sea un resto de aquella etapa y puedas simplificarlo.

Usa preferencias cuando necesitas **agregar** datos de varias subvistas. Para una sola, `onGeometryChange`. Para posicionar según lo medido, `Layout`.

### Bucles de layout

Un ancestro que cambia el tamaño que propone en función de lo que sus hijos reportan, y unos hijos que cambian lo que reportan en función de la propuesta, es un bucle. SwiftUI lo corta tras unas iteraciones y lo que ves es parpadeo o un tamaño "aleatorio". La solución *legacy* era `.fixedSize()` en el hijo (rompe el bucle, mata la adaptabilidad). La solución real es un `Layout`, donde la medición y la colocación ocurren en un solo pase controlado por ti.

## 7.6. Espacios de coordenadas y anclajes

`proxy.frame(in: .global)` y `.local` cubren lo básico. Para medir respecto a un ancestro concreto, nómbralo:

```swift
ScrollView { contenido }
    .coordinateSpace(.named("scroll"))           // API actual

// Dentro:
proxy.frame(in: .named("scroll")).minY
```

Un **`Anchor<T>`** es una medida (`CGRect`, `CGPoint`) tomada en coordenadas globales que un `GeometryProxy` puede resolver en las suyas con `proxy[ancla]`. Se transporta con `anchorPreference(key:value:transform:)` y evita que tengas que elegir un espacio de coordenadas en el momento de medir. Es la base del indicador de selección que se desliza bajo la pestaña activa, y de `matchedGeometryEffect`.

## 7.7. `matchedGeometryEffect`

Anima posición y tamaño entre dos vistas que comparten `id` y `@Namespace`, típicamente una que se elimina y otra que se inserta:

```swift
@Namespace private var espacio

if expandida {
    Tarjeta().matchedGeometryEffect(id: producto.id, in: espacio)
} else {
    Miniatura().matchedGeometryEffect(id: producto.id, in: espacio)
}
```

Regla de precedencia: el efecto se aplica como `frame` + `offset` animados, así que **un `frame` fijo escrito después de `matchedGeometryEffect` anula el efecto**. Colócalo lo más cerca posible de la vista que quieres emparejar, antes de cualquier restricción de tamaño.

Para el caso concreto de navegación (miniatura → ficha), `navigationTransition(.zoom)` con `matchedTransitionSource` (capítulo 6) es más simple y más correcto.

## 7.8. Solo iOS 27+: reordenar en un `Layout` propio

iOS 27 lleva la reordenación por arrastre a cualquier contenedor, incluidos los `Layout` personalizados, con las mismas APIs que `List` (`reorderable` y `reorderContainer`; a fecha de cierre de este texto la documentación de Apple las marca todavía como *beta*, así que el repositorio las comprueba contra el SDK final). Lo que exige de tu layout: identidad estable por elemento (capítulo 2) y una colocación que dependa solo del orden de `subviews`, no de estado guardado fuera. Un `FlowLayout` como el de 7.2 cumple ambas sin cambios; uno que haya cacheado posiciones por índice, no. El repositorio tiene el ejemplo en `Sources/PulseSearch/` (`FlowLayout.swift` para el layout, `TagCloudView.swift` para la vista que lo usa).

## 7.9. Code review: la nube de etiquetas que se mide una y otra vez

En `Pulse`, la pantalla de búsqueda muestra las etiquetas populares en un `FlowLayout`. Con 60 etiquetas, el *scroll* de la pantalla daba tirones. Está en `Sources/PulseSearch/FlowLayout.swift`, y la vista que lo usa en `TagCloudView.swift`.

### El código que pasó la revisión

El `FlowLayout` de 7.2, tal cual, sin caché. Correcto, legible, y cada método llama a `sizeThatFits(.unspecified)` sobre las 60 subvistas.

### El diagnóstico

Instruments, plantilla SwiftUI, pista *Long View Body Updates*: nada. Los `body` son baratos. Time Profiler: el tiempo está en `FlowLayout.sizeThatFits` y `placeSubviews`. Para saber cuánto trabajo hacen, `Pulse` cuenta las llamadas y las mediciones con un contador dentro de cada método.

Lo primero que enseña ese contador es una cautela: **cuántas veces te llama SwiftUI no es un número que puedas dar por fijo**. En nuestras ejecuciones del mismo montaje, en máquinas distintas, salieron 7 llamadas a `sizeThatFits` con 2 a `placeSubviews`, y también 7 con 1. El padre propone los tamaños que necesita para decidir, y eso depende del contexto, de la versión y de lo que haya alrededor. Cualquier libro que te dé una cifra de invocaciones como si fuera una propiedad del *framework* te está vendiendo una casualidad de su máquina.

Lo que sí es estable es la **proporción**, y es donde está el problema: en cada una de esas llamadas se miden otra vez las 60 etiquetas. Con 9 llamadas fueron 540 mediciones; con 8, 480. El número de arriba cambia; el hecho de que se multiplique por 60, no.

Que haya varias llamadas no es un bug y no está en tu mano: el montaje inicial puede implicar más de un pase, y por eso el contador suma todo el montaje en lugar de hablar de "por pase". Lo que sí está en tu mano es no volver a medir las mismas 60 etiquetas en cada llamada, cuando su tamaño ideal no ha cambiado entre una y otra.

### La solución

La caché de 7.3: los tamaños ideales se calculan una vez en `makeCache` (y en `updateCache` cuando cambian las etiquetas), y los marcos se recalculan solo cuando cambia el ancho propuesto. Las llamadas siguen siendo las que SwiftUI decida —eso no lo controla el layout—, pero las mediciones pasan a ser **60, una por etiqueta**, en lugar de 60 por llamada. El test `FlowLayoutMedicionTests` del repositorio comprueba justo esa relación, no una cifra concreta: falla si el layout mide en cada invocación y pasa si no lo hace.

Y una segunda mejora que no tiene que ver con el `Layout`: las etiquetas eran `Text` con `.font(.caption)` y `.padding`; extraerlas a una vista `Etiqueta` conforme a `Equatable` con `.equatable()` evita que se reevalúen cuando lo que cambia es la consulta de búsqueda y no las etiquetas (capítulo 8).

> **Antipatrón.** Implementar `Cache` "por si acaso" antes de medir. Añade estado, invalidación y una fuente nueva de *bugs* a cambio de un ahorro que en muchos layouts no existe. La caché se justifica con un *signpost* que muestra mediciones repetidas, no con una corazonada.

> **Regla de oro.** Si tienes que medir para colocar, escribe un `Layout`. Si tienes que medir para decidir otra cosa (mostrar un "leer más", ajustar un texto), usa `onGeometryChange`. Preferencias solo para agregar de varias subvistas, y `GeometryReader` solo dentro de un `background`.

> **Siguiente paso.** Localiza en tu proyecto los `GeometryReader` que no estén en un `background` o un `overlay`. Cada uno es o bien un `Layout` que no escribiste, o bien un `containerRelativeFrame` que no conocías.
