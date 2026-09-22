# Capítulo 6: Animaciones y transiciones

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. `@Animatable` y Liquid Glass requieren iOS 26; `.navigationTransition(.crossFade)`, iOS 27.

## 6.1. Qué se anima

SwiftUI no anima vistas. Anima **la diferencia entre dos árboles de vistas** cuando esa diferencia ocurre dentro de una transacción con animación. Eso obliga a distinguir dos situaciones que se parecen en pantalla y son opuestas en el grafo (capítulo 2):

| | Animación de propiedades | Transición |
| :--- | :--- | :--- |
| **Identidad** | El nodo persiste | El nodo se inserta o se elimina |
| **Qué se interpola** | Valores `Animatable` del mismo nodo (`frame`, `opacity`, `rotation`, color) | Nada por defecto; una `Transition` aplica un efecto de entrada/salida |
| **Cómo se dispara** | Un cambio de estado dentro de `withAnimation` o cubierto por `.animation` | Un `if`, un `switch`, un `.id` que cambia, un `ForEach` que inserta o quita |
| **Coste** | Bajo | Medio: construye y destruye nodos |

La consecuencia práctica: **cuando una animación "salta" en lugar de interpolar, casi siempre es una transición que creías animación de propiedades**. La sección 6.8 tiene el caso.

### Interpolación

Un valor se puede animar si su tipo conforma a `Animatable`, que exige una propiedad `animatableData` de un tipo `VectorArithmetic` (sumable y escalable). `CGFloat`, `Double`, `CGSize`, `CGPoint`, `Color`, `Angle` y `AnimatablePair` ya lo son. Cuando el estado cambia dentro de una animación, SwiftUI interpola `animatableData` entre el valor anterior y el nuevo siguiendo la curva de la transacción.

Las animaciones son **aditivas y cancelables** por defecto: si el estado vuelve a cambiar antes de terminar, la nueva animación arranca desde el valor intermedio actual, no desde el destino de la anterior. Es lo que hace que un botón pulsado tres veces seguidas no parpadee.

## 6.2. Dónde se declara la animación

### Explícita: `withAnimation`

Envuelve el **cambio de estado** en el código de evento. Todo lo que ese cambio invalide, en cualquier parte del árbol, se anima:

```swift
Button("Ampliar") {
    withAnimation(.snappy) { ampliado.toggle() }
}
```

Ámbito global y fuente única: solo se anima lo que cambia dentro del *closure*.

### Implícita: `.animation(_:value:)`

Se declara en el **árbol** y se aplica cuando `value` cambia, venga de donde venga el cambio (usuario, red, `Timer`):

```swift
Rectangle()
    .frame(width: ampliado ? 200 : 100)
    .animation(.snappy, value: ampliado)
```

Ámbito local (el subárbol bajo el modificador) y cualquier fuente.

### Implícita acotada: `.animation(_:body:)` (iOS 17+)

Anima solo los modificadores del *closure*, sin afectar a lo que está más abajo:

```swift
Tarjeta()
    .animation(.bouncy) { contenido in
        contenido.scaleEffect(pulsada ? 0.96 : 1)
    }
```

### Sobre un `Binding`

`$activo.animation(.default)` devuelve un `Binding` cuyo `setter` está envuelto en `withAnimation`. Útil para controles (`Toggle`, `Slider`) sin tocar el código de evento.

| | `withAnimation` | `.animation(_:value:)` | `.animation(_:body:)` |
| :--- | :--- | :--- | :--- |
| Se escribe en | Evento | Árbol | Árbol |
| Fuente del cambio | Solo la envuelta | Cualquiera | Cualquiera |
| Ámbito | Todo lo invalidado | Subárbol | Solo los modificadores del *closure* |
| Cuándo usarla | Interacción directa | Datos asíncronos, modelos `@Observable` | Efectos que no deben propagarse |

> **Pro Tip para Seniors.** Con modelos `@Observable` actualizados desde red, las implícitas ganan: no tienes que envolver cada asignación en `withAnimation` dentro del *view model*, y el *view model* no debería saber que existe una animación.

## 6.3. Transacciones

Cada actualización lleva una `Transaction`: la animación, si la hay, y sus *handlers*. `withAnimation` es azúcar sobre `withTransaction`:

```swift
var t = Transaction(animation: .snappy)
t.disablesAnimations = true          // Ignora las .animation implícitas del subárbol
withTransaction(t) { ampliado.toggle() }
```

Precedencia: una animación **implícita** declarada en el árbol sustituye a la explícita que llega en la transacción, salvo que la transacción lleve `disablesAnimations = true`. Es la forma de forzar "sin animación" en un cambio concreto aunque el subárbol tenga `.animation`.

`.transaction { t in ... }` modifica la transacción que baja por el subárbol; `.transaction(value:) { t in ... }` (iOS 17+) lo hace solo cuando `value` cambia.

### Completado (iOS 17+)

```swift
withAnimation(.snappy, completionCriteria: .removed) {
    mostrarConfirmacion = true
} completion: {
    Task { await modelo.registrarCompra() }   // Ya en MainActor
}
```

`completionCriteria` distingue `.logicallyComplete` (la animación ha llegado a su valor aunque queden *frames* de un *spring* asentándose) de `.removed` (ha terminado del todo). El *closure* se ejecuta en el `MainActor`; no lo marques `nonisolated` ni lo lances a un hilo de fondo: es el sitio donde encadenar el siguiente paso de UI.

Dentro de una transacción, `t.addAnimationCompletion(criteria:_:)` hace lo mismo.

## 6.4. Curvas, fases y *keyframes*

`Animation` incluye las curvas clásicas (`.linear`, `.easeInOut`), las de resorte (`.spring(duration:bounce:)`) y presets con nombre (`.snappy`, `.bouncy`, `.smooth`). `.timingCurve(_:_:_:_:duration:)` acepta una Bézier cúbica propia.

### `phaseAnimator` (iOS 17+)

Recorre una lista de fases discretas y anima entre ellas. Ideal para secuencias cortas disparadas por un evento:

```swift
Image(systemName: "cart.fill")
    .phaseAnimator([0, -8, 8, 0], trigger: añadidos) { contenido, desplazamiento in
        contenido.offset(x: desplazamiento)
    } animation: { _ in .snappy(duration: 0.12) }
```

### `keyframeAnimator` (iOS 17+)

Control total sobre una línea de tiempo, con una pista por propiedad:

```swift
.keyframeAnimator(initialValue: Pose(), trigger: añadidos) { contenido, pose in
    contenido
        .scaleEffect(pose.escala)
        .offset(y: pose.y)
} keyframes: { _ in
    KeyframeTrack(\.escala) {
        SpringKeyframe(1.3, duration: 0.15)
        SpringKeyframe(1.0, duration: 0.25)
    }
    KeyframeTrack(\.y) {
        CubicKeyframe(-12, duration: 0.15)
        CubicKeyframe(0, duration: 0.25)
    }
}
```

`KeyframeTrack` vive dentro de `keyframeAnimator` (o de un `KeyframeTimeline` si quieres muestrearla a mano). No es un parámetro de `Animation`.

## 6.5. `Animatable` y `@Animatable`

Para animar algo que SwiftUI no sabe interpolar (un número de sacudidas, el progreso de un trazo) expones `animatableData`:

```swift
struct Sacudida: ViewModifier, Animatable {
    var sacudidas: Double

    var animatableData: Double {
        get { sacudidas }
        set { sacudidas = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: -sin(sacudidas * 2 * .pi) * 30)
    }
}
```

Animar `sacudidas` de 0 a 1 produce un ciclo completo de vaivén que empieza y termina en 0. Para dos o más valores, `AnimatablePair`.

> **Solo iOS 26+: la macro `@Animatable`.** Apple la documenta como una macro de SwiftUI que sintetiza la conformidad con `Animatable` y `animatableData` a partir de las propiedades almacenadas que pueden interpolarse; `@AnimatableIgnored` excluye una propiedad. Con nuestro *deployment target* iOS 18, este libro la trata como una API disponible desde iOS 26 en adelante y el listado queda aislado en este recuadro. Si el repositorio necesita *back-deployment* real de este símbolo, la comprobación debe hacerse en Xcode 27 con el *target* del módulo.

## 6.6. Transiciones

Una transición solo se ejecuta si hay una animación activa en el **contenedor estable** que envuelve la inserción o eliminación:

```swift
VStack {
    if mostrarAviso {
        Aviso()
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
.animation(.snappy, value: mostrarAviso)
```

Sin la animación en el `VStack` (o un `withAnimation` alrededor del cambio de `mostrarAviso`), el `Aviso` aparece y desaparece de golpe aunque tenga `.transition`.

### El protocolo `Transition` (iOS 17+)

Una transición propia es un tipo que describe cómo se ve el contenido en cada fase:

```swift
struct Desenfoque: Transition {
    var radio: CGFloat = 8

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .blur(radius: phase.isIdentity ? 0 : radio)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

Aviso().transition(Desenfoque())
```

`TransitionPhase` es `.willAppear`, `.identity` o `.didDisappear`; con `phase.value` (-1, 0, 1) puedes hacer transiciones asimétricas en una sola expresión. `AsymmetricTransition(insertion:removal:)` combina dos transiciones distintas; `.combined(with:)` las superpone. La forma antigua, `AnyTransition.modifier(active:identity:)`, sigue funcionando pero no la escribas nueva.

### Transiciones de navegación (iOS 18+)

```swift
NavigationLink(value: producto) {
    Miniatura(producto)
        .matchedTransitionSource(id: producto.id, in: espacio)
}
// destino:
FichaProducto(producto)
    .navigationTransition(.zoom(sourceID: producto.id, in: espacio))
```

`@Namespace private var espacio` en la vista contenedora. Es el *hero* de miniatura a ficha sin `matchedGeometryEffect` a mano.

Este ejemplo entra aquí aunque la navegación tenga su propio capítulo en la siguiente edición, y conviene decir por qué: sin él no se puede explicar cuándo **no** usar `matchedGeometryEffect`, que es lo que hace el capítulo 7 (§7.7). Para lo demás que tenga que ver con navegación, el libro no es la referencia.

> **Solo iOS 26+: Liquid Glass.** Sus materiales (`glassEffect`, `GlassEffectContainer`) quedan fuera de esta edición, pero hay una consecuencia que sí pertenece a este capítulo: sus transiciones se animan como cualquier otro cambio de estado, con `withAnimation`, y el sistema se encarga de fundir un elemento de vidrio con otro. Si un día ves una de esas transiciones saltar, la causa será la de §6.1 y no el material.

> **Solo iOS 27+.** La transición de presentación de fundido cruzado se expresa con `.navigationTransition(.crossFade)` sobre el contenido de la presentación. Apple la documenta para `sheet`; el soporte y comportamiento exactos de cada tipo de presentación deben comprobarse en el SDK que compile el repositorio.

## 6.7. Gestos

La regla es una: `onChanged` sin animación (el dedo manda), `onEnded` con animación (la vista vuelve o se asienta):

```swift
.gesture(
    DragGesture()
        .onChanged { desplazamiento = $0.translation }
        .onEnded { _ in
            withAnimation(.snappy) { desplazamiento = .zero }
        }
)
```

Con `@GestureState` el retorno a `.zero` al soltar es automático, y la animación se declara con `.animation(_:value:)` sobre el estado del gesto.

## 6.8. Code review: la animación de "añadido al carrito" que salta

En `Pulse`, el botón de la ficha de producto cambia a "Añadido ✓" con una animación de confirmación. Está en `Cart/AddToCartButton.swift`.

### El código que pasó la revisión

```swift
struct AddToCartButton: View {
    @Bindable var carrito: Carrito
    let producto: Producto

    private var añadido: Bool { carrito.contiene(producto) }

    var body: some View {
        Button {
            withAnimation(.bouncy) { carrito.alternar(producto) }
        } label: {
            if añadido {
                Label("Añadido", systemImage: "checkmark")
                    .foregroundStyle(.green)
            } else {
                Label("Añadir al carrito", systemImage: "cart.badge.plus")
            }
        }
        .buttonStyle(.borderedProminent)
    }
}
```

### El bug

Diseño lo describe así: "el *check* aparece de golpe, el botón cambia de ancho a saltos y, si pulsas dos veces rápido, parpadea". Ingeniería lo describe así: no hay nada que interpolar.

El `if/else` en el `label` son **dos nodos distintos** (capítulo 2). Cambiar `añadido` no modifica un `Label`: elimina uno e inserta otro. `withAnimation(.bouncy)` está haciendo su trabajo; lo que anima es una **transición** con el valor por defecto (`.opacity`), y el cambio de tamaño del botón se interpola, pero el contenido no. El *bounce* que Diseño pidió no tiene sobre qué actuar.

El parpadeo al pulsar dos veces es la misma causa: dos transiciones opuestas encadenadas sobre nodos distintos, sin nada aditivo entre ellas.

### Reproducirlo

`let _ = Self._printChanges()` no basta aquí, porque `AddToCartButton` no cambia de identidad; cambian sus hijos. Añade la línea a un `Label` extraído en una subvista y verás `@identity changed` en cada pulsación.

### La solución

Un solo nodo, cuyos parámetros cambian:

```swift
Button {
    withAnimation(.bouncy) { carrito.alternar(producto) }
} label: {
    Label(
        añadido ? "Añadido" : "Añadir al carrito",
        systemImage: añadido ? "checkmark" : "cart.badge.plus"
    )
    .foregroundStyle(añadido ? .green : .primary)
    .contentTransition(.symbolEffect(.replace))    // El símbolo se sustituye con animación
}
.buttonStyle(.borderedProminent)
.sensoryFeedback(.success, trigger: añadido) { !$0 && $1 }
```

- El `Label` es el mismo nodo antes y después: el color y el ancho se interpolan, el *bounce* actúa.
- `.contentTransition(.symbolEffect(.replace))` (iOS 17+) anima el cambio de símbolo SF dentro de la misma `Image`. Para texto numérico (el contador del carrito) el equivalente es `.contentTransition(.numericText())`.
- Pulsar dos veces rápido ahora es aditivo: la segunda animación arranca desde el estado intermedio.

Si el rediseño exige que "añadido" sea visualmente otra cosa (otro tamaño, otra forma), entonces sí es una transición, y se declara como tal: `.transition(Desenfoque())` en cada rama y `.animation(_:value:)` en el contenedor, aceptando que no habrá interpolación entre los dos contenidos.

> **Antipatrón.** `if/else` dentro de un `label` o de una celda, con `withAnimation` fuera, esperando que "se anime el cambio". Se anima; solo que lo que se anima es una inserción y una eliminación.

## 6.9. Accesibilidad y coste

- **Reducir movimiento.** Lee `@Environment(\.accessibilityReduceMotion)` y sustituye desplazamientos y escalas por fundidos cuando esté activo. Una animación decorativa que no respeta esto es un *bug* de accesibilidad, no una preferencia.
- **Contenido que cambia solo.** `.accessibilityAddTraits(.updatesFrequently)` para que VoiceOver no relea cada *frame* de un contador o un progreso.
- **Decorativo.** `.accessibilityHidden(true)`. La forma `.accessibility(hidden:)` está deprecada.
- **Coste.** Una animación de propiedades sobre `opacity`, `scaleEffect`, `offset` o `rotationEffect` se resuelve en la fase de renderizado y es barata. Una que cambia `frame`, `padding` o `font` invalida el layout en cada *frame*; en listas largas eso se ve en la métrica de *hitches* de Xcode 27. Si tienes que animar tamaño en muchas filas a la vez, anima `scaleEffect`.

> **Regla de oro.** Antes de escribir `withAnimation`, pregunta si el nodo que quieres animar existe antes y después del cambio. Si la respuesta es no, lo que necesitas es una `Transition`, y si la respuesta es "debería", lo que necesitas es una sola vista con parámetros.

> **Siguiente paso.** Busca en tu proyecto `withAnimation` cuyo *closure* cambie una variable que se usa en un `if/else` entre vistas. Cada uno es una transición disfrazada; decide si quieres una transición de verdad o un solo nodo.
