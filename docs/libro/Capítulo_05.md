# Capítulo 5: El entorno

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. `@Entry` (Xcode 16, *back-deploy*) y `@Environment(Tipo.self)` (iOS 17) están cubiertos; 5.7 marca SwiftData en iOS 27.

## 5.1. Qué es y qué no es

El entorno es un **diccionario tipado que fluye hacia abajo por el árbol de vistas**. Cada nodo hereda el de su padre y puede sobrescribir entradas para su subárbol. Nada más y nada menos.

Lo que resuelve bien: configuración compartida (fuentes, colores, locale, tamaño de texto), servicios que muchas vistas necesitan (cliente de red, *feature flags*, contexto de persistencia) y estilos de componentes.

Lo que no resuelve: comunicación hacia arriba (para eso están `Binding` y las preferencias del capítulo 7) ni comunicación entre hermanos (para eso está un modelo compartido). Cuando el entorno se usa para eso, el resultado es una app en la que nadie sabe de dónde sale un valor.

## 5.2. Cómo fluye

```swift
VStack {
    Text("Total")        // Hereda .title
    Text("42,00 €")      // Hereda .title
}
.font(.title)            // Escribe en el entorno del subárbol
```

`.font(.title)` es azúcar para `.environment(\.font, .title)`. El modificador crea un nodo que sobrescribe esa clave para todo lo que hay debajo. El orden importa exactamente igual que en el capítulo 2: el modificador afecta a lo que está **dentro** de él, no a lo que está después en el código.

```swift
Text("Hola")
    .font(.title)        // Afecta al Text
    .padding()
    .font(.caption)      // No afecta a nada: el Text ya está dentro de .font(.title)
```

Eso también significa que el entorno **no atraviesa fronteras de presentación por accidente**: un `sheet` o un `fullScreenCover` hereda el entorno del nodo que lo presenta, no el de la raíz de la app. Si inyectas algo en un subárbol y la *sheet* se presenta desde fuera de ese subárbol, no lo verá.

### Leer

```swift
struct Precio: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var tamaño

    var body: some View { /* ... */ }
}
```

`@Environment` crea una dependencia: la vista se invalida cuando cambia el valor que lee. Como con `@Observable`, lee lo mínimo. Si solo necesitas saber si estás en tamaños de accesibilidad, no dependas de todo `dynamicTypeSize`:

```swift
@Environment(\.dynamicTypeSize.isAccessibilitySize) private var esAccesible
```

El *key path* compuesto funciona porque `@Environment` acepta cualquier `KeyPath<EnvironmentValues, T>`. La vista ahora solo se invalida cuando ese booleano cambia, que es mucho menos frecuente que cada salto de tamaño. Cuánto ahorra depende de tu jerarquía; se mide en Instruments, no se estima.

| Valor | Para qué |
| :--- | :--- |
| `\.dynamicTypeSize`, `\.dynamicTypeSize.isAccessibilitySize` | Adaptar layout al tamaño de texto (capítulo 4). |
| `\.horizontalSizeClass` | Disposición compacta/regular. Desde iOS 27, cambia en iPhone. |
| `\.scenePhase` | Activa / inactiva / segundo plano. |
| `\.locale`, `\.calendar`, `\.timeZone` | Formateo. |
| `\.accessibilityReduceMotion` | Desactivar animaciones decorativas (capítulo 6). |
| `\.dismiss`, `\.openURL` | Acciones del sistema. |
| `\.modelContext` | Contexto de SwiftData. |

Declara siempre las propiedades `@Environment` como `private`: son una dependencia de la vista, no parte de su interfaz.

## 5.3. Claves propias con `@Entry`

Desde Xcode 16 (con *back-deploy* completo), una clave de entorno es una línea:

```swift
extension EnvironmentValues {
    @Entry var colorDeMarca: Color = .indigo
}
```

La macro genera la `EnvironmentKey`, su `defaultValue` y la propiedad computada. Opcionalmente, una extensión de `View` para escritura fluida:

```swift
extension View {
    func colorDeMarca(_ color: Color) -> some View {
        environment(\.colorDeMarca, color)
    }
}
```

Con Swift 6, el `defaultValue` estático de un tipo que no sea `Sendable` produce un error de aislamiento (es estado global compartido). Los valores de entorno deben ser `Sendable` o estar aislados al `MainActor`; para tipos propios, casi siempre lo primero.

> **Antipatrón.** Claves de entorno para pasar datos de un padre a un hijo directo. Eso es un parámetro. El entorno es para valores que muchos descendientes, a distintas profundidades, necesitan sin que los intermedios sepan de ellos.

## 5.4. Componentes estilizables

El patrón con el que Apple implementa `ButtonStyle`, `LabelStyle` o `ToggleStyle` es reproducible: un protocolo de estilo, una configuración que describe las piezas del componente, y una clave de entorno que transporta el estilo actual.

```swift
struct BadgeConfiguration {
    let label: AnyView        // El contenido que el estilo debe colocar
    let cuenta: Int
}

protocol BadgeStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: BadgeConfiguration) -> Body
}

extension EnvironmentValues {
    @Entry var badgeStyle: any BadgeStyle = DefaultBadgeStyle()
}

extension View {
    func badgeStyle(_ style: some BadgeStyle) -> some View {
        environment(\.badgeStyle, style)
    }
}
```

`AnyView` en la configuración es deliberado: la configuración es una frontera de tipo (el estilo no puede conocer el tipo del contenido de antemano), igual que `ButtonStyleConfiguration.Label` es un tipo opaco en la API de Apple. Es uno de los pocos sitios donde el borrado de tipo es la solución y no el problema.

El componente lee el estilo del entorno y delega:

```swift
struct Badge<Label: View>: View {
    @Environment(\.badgeStyle) private var style
    let cuenta: Int
    @ViewBuilder let label: () -> Label

    var body: some View {
        AnyView(style.makeBody(configuration: .init(label: AnyView(label()), cuenta: cuenta)))
    }
}
```

El `AnyView` externo existe porque `any BadgeStyle` tiene un `Body` existencial. Si te molesta, la alternativa es una clave de entorno con un `AnyBadgeStyle` que haga el borrado una sola vez; el resultado es el mismo.

Uso:

```swift
Badge(cuenta: 3) { Text("Carrito") }
    .badgeStyle(BadgeEstiloPromo())
```

## 5.5. Objetos en el entorno

Es el mecanismo estándar para inyectar servicios y modelos `@Observable`.

### Escribir

```swift
RootView()
    .environment(sesion)          // sesion: SesionUsuario, @Observable
```

`.environment(_:)` usa el **tipo** del objeto como clave. Solo puede haber uno por tipo en un subárbol; si necesitas dos instancias del mismo tipo, envuélvelas en tipos distintos o usa una clave `@Entry`.

### Leer

Aquí está el detalle que más *crashes* produce en previews y en *targets* secundarios:

```swift
@Environment(SesionUsuario.self) private var sesion: SesionUsuario     // CRASH si no está inyectado.
@Environment(SesionUsuario.self) private var sesion: SesionUsuario?    // nil si no está inyectado.
```

**La opcionalidad va en el tipo de la propiedad, no en el argumento.** No existe una sobrecarga que acepte `SesionUsuario?.self`: el inicializador siempre toma `T.Type`, y `SesionUsuario?.self` hace que el compilador descarte las sobrecargas de objeto (piden `AnyObject & Observable`, y un opcional no lo es) y caiga en la de *key path*, donde falla con un mensaje sobre `KeyPath` que no menciona la causa real. Si te encuentras ese error, la primera sospecha es esta.

La forma no opcional se comporta exactamente como `@EnvironmentObject`: si nadie inyectó el objeto por encima, la app aborta al leer. La forma opcional te obliga a decidir qué hacer si falta. Regla: **no opcional para dependencias que la app no puede funcionar sin ellas** (y una preview que crashea es una preview que te avisa); **opcional para servicios con comportamiento por defecto razonable** (analítica, *feature flags*, caché).

### Escribir desde el hijo

`@Environment` solo lee. Para obtener un `Binding` a una propiedad del objeto, `@Bindable` local (capítulo 3):

```swift
var body: some View {
    @Bindable var sesion = sesion
    Toggle("Notificaciones", isOn: $sesion.notificaciones)
}
```

### *Legacy*: `@EnvironmentObject`

Mismo patrón para `ObservableObject`, con `.environmentObject(_:)` y `@EnvironmentObject var x: Tipo`. No está deprecado, pero no tiene forma opcional, invalida la vista con cualquier `@Published` que cambie, y exige Combine. Solo para código que ya lo usa.

## 5.6. Code review: el *feature flag* que crashea la preview y no llega a la *sheet*

`Pulse` tiene un servicio `FeatureFlags` (`@Observable @MainActor`) que decide, entre otras cosas, si el banner de promoción del checkout está activo. Está en `Core/FeatureFlags.swift`.

### El código que pasó la revisión

```swift
// App
PulseApp: WindowGroup {
    RootTabs()
        .environment(flags)
}

// Checkout, presentado como sheet desde ProductView
struct CheckoutView: View {
    @Environment(FeatureFlags.self) private var flags
    // ...
    if flags.bannerPromo { PromoBanner() }
}

// Preview
#Preview {
    CheckoutView(orderID: .init())
}
```

### Los bugs

Dos, con la misma causa.

**Uno.** La preview de `CheckoutView` crashea al abrirse: `FeatureFlags` no está inyectado en ese árbol y `@Environment(FeatureFlags.self)` no admite ausencia. El equipo lo "arregló" durante meses añadiendo `.environment(FeatureFlags())` a cada preview a mano, hasta que alguien lo olvidó en un *target* de widget y el crash llegó a producción.

**Dos.** Tras una refactorización, `ProductView` pasó a inyectar una variante A/B de los flags para su subárbol:

```swift
ProductView()
    .environment(flagsExperimento)      // Solo para esta pantalla
    .sheet(isPresented: $mostrarCheckout) { CheckoutView(orderID: id) }
```

Y el checkout dejó de mostrar el banner en el grupo experimental. La `sheet` se presenta desde el nodo que tiene el modificador `.sheet`, que está **fuera** del subárbol donde se inyectó `flagsExperimento`; hereda los flags de la raíz. Nadie vio el bug en QA porque en la raíz el flag también estaba activo esa semana.

### La solución

```swift
// FeatureFlags con un valor por defecto seguro
@Observable @MainActor
final class FeatureFlags {
    static let porDefecto = FeatureFlags(bannerPromo: false)
    // ...
}

// Lectura opcional con fallback: nunca crashea, y el comportamiento por defecto es explícito
struct CheckoutView: View {
    @Environment(FeatureFlags.self) private var flagsInyectados: FeatureFlags?
    private var flags: FeatureFlags { flagsInyectados ?? .porDefecto }
    // ...
}

// La variante experimental se inyecta donde se presenta, no donde se lee
ProductView()
    .sheet(isPresented: $mostrarCheckout) {
        CheckoutView(orderID: id)
            .environment(flagsExperimento)
    }
```

Y una regla de equipo: cada tipo que se inyecta en el entorno tiene un `porDefecto` y un *preview trait* (`.environment(FeatureFlags.preview)`) para que ninguna preview dependa de recordar la inyección.

## 5.7. Persistencia y concurrencia

### SwiftData

SwiftData usa el entorno para su contexto: `.modelContainer(for: [Producto.self, Pedido.self])` en la raíz y `@Environment(\.modelContext)` en las vistas. Los objetos `@Model` son observables por propiedad, así que se pueden pasar como referencias normales y bindear con `@Bindable`.

> **Solo iOS 27+.** SwiftData añade consultas seccionadas, predicados compuestos y sobre enums, el atributo `.codable` y `ResultsObserver` para observar resultados fuera de una vista. No cambian cómo se inyecta el contexto; cambian cuánto de la lógica de consulta puede salir de las vistas.

### Servicios pesados: `actor` + `@Observable`

El entorno transporta objetos, no importa de qué tipo, pero conviene separar dos responsabilidades:

- **Estado de UI**: clases `@Observable @MainActor`. Síncronas, leídas por el `body`.
- **Trabajo pesado** (red, disco, cálculo): `actor`. Asíncrono, aislado.

Un `actor` **no puede ser `@Observable`**: la macro necesita acceso síncrono a las propiedades y el actor solo lo ofrece asíncrono. El compilador lo rechaza.

Y otro límite que no negocia: **`@Environment` solo funciona en tipos `View`** (y `App`/`Scene`). Un *view model* no puede leer el entorno. La inyección hacia un *view model* se hace por `init`:

```swift
actor CatalogoService {
    func buscar(_ texto: String) async throws -> [Producto] { /* red */ }
}

@Observable @MainActor
final class BusquedaModel {
    private let catalogo: CatalogoService
    var resultados: [Producto] = []

    init(catalogo: CatalogoService) { self.catalogo = catalogo }

    func buscar(_ texto: String) async {
        resultados = (try? await catalogo.buscar(texto)) ?? []
    }
}

struct BusquedaView: View {
    @Environment(CatalogoService.self) private var catalogo
    @State private var modelo: BusquedaModel?

    var body: some View {
        Group {
            if let modelo { BusquedaContenido(modelo: modelo) }
        }
        .task { modelo = BusquedaModel(catalogo: catalogo) }   // Se construye con la dependencia real
    }
}
```

La vista lee el servicio del entorno y construye el modelo con él. `.task` lo crea una vez por vida del nodo; el `if let` evita un estado intermedio inventado. Si prefieres evitar el opcional, el padre que ya tiene el servicio construye el modelo y lo pasa (capítulo 3: quien posee, `@State`; quien recibe, propiedad normal).

> **Regla de oro.** `@Environment(Tipo.self)` es una afirmación: "esto siempre está". Si no puedes garantizarlo en cada *target*, preview y ruta de presentación, declara la propiedad como `Tipo?` y decide el *fallback* tú, no el *crash*.

> **Siguiente paso.** Haz una lista de todo lo que tu app inyecta con `.environment(_:)` y, para cada tipo, responde: ¿tiene forma opcional o `porDefecto`? ¿Qué previews lo necesitan? ¿Qué *sheets* se presentan desde fuera del subárbol donde se inyecta? Cada respuesta en blanco es un crash o un flag perdido esperando su momento.
