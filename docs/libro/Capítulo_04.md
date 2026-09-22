# Capítulo 4: Layout

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. `containerRelativeFrame` y `ViewThatFits` (iOS 17) están cubiertos; 4.10 marca lo que requiere iOS 27.

## 4.1. Una sola regla

El algoritmo de layout de SwiftUI cabe en una frase: **el padre propone, el hijo decide, el padre posiciona.** Todo lo demás son casos particulares.

1. **Propuesta (de arriba abajo).** El padre ofrece un tamaño a cada hijo. Cada dimensión puede ser un número o `nil` ("sin restricción").
2. **Decisión (recursiva).** El hijo calcula su tamaño según la propuesta, su contenido y sus modificadores. Si tiene hijos, les propone a su vez.
3. **Reporte (de abajo arriba).** El hijo devuelve su tamaño. **Es definitivo.** El padre no puede cambiarlo; solo puede proponer otra cosa la próxima vez.
4. **Posicionamiento.** El padre coloca al hijo dentro de su propio marco usando las guías de alineación.

El tipo que transporta la propuesta es público desde iOS 16:

```swift
struct ProposedViewSize {
    var width: CGFloat?    // nil = sin restricción en ese eje
    var height: CGFloat?
    static let zero, infinity, unspecified: ProposedViewSize
}
```

Y la interfaz real con la que un contenedor pregunta a un hijo (protocolo `Layout`, capítulo 7):

```swift
subview.sizeThatFits(_ proposal: ProposedViewSize) -> CGSize
```

Tres propuestas tienen nombre y comportamiento propio en casi todas las vistas: `.zero` (tamaño mínimo), `.infinity` (tamaño máximo) y `.unspecified` (tamaño ideal).

### Un ejemplo completo

```swift
Text("Favorito")
    .padding(10)
    .background(Color.teal)
```

| Paso | Quién | Recibe | Devuelve | Por qué |
| :--- | :--- | :--- | :--- | :--- |
| 1 | `background` | 320×480 | — | Propuesta de la ventana. |
| 2 | `padding` | 320×480 | — | `background` pasa la propuesta intacta a su contenido principal. |
| 3 | `Text` | 300×460 | 51×17 | `padding` resta 10 por lado. `Text` usa su tamaño intrínseco. |
| 4 | `padding` | — | 71×37 | Suma 10 por lado al tamaño del hijo. |
| 5 | `Color` | 71×37 | 71×37 | `background` propone a su secundario el tamaño del principal. `Color` acepta lo que le den. |
| 6 | `background` | — | 71×37 | Reporta el tamaño del principal, no del fondo. |

Todo el capítulo es aprender lo que cada vista hace en los pasos 2 y 3.

## 4.2. Cómo ver el layout

- **`.border(.red)`** sobre una vista muestra su tamaño reportado. Es la herramienta que más problemas resuelve por minuto invertido.
- **`GeometryReader` en `background` u `overlay`** para medir sin alterar el layout: recibe como propuesta el tamaño de la vista principal y no cambia el reporte.
- **`onGeometryChange(for:of:action:)`** (SDK iOS 18, *back-deploy* a iOS 16) para reaccionar a un tamaño sin un `GeometryReader` en el árbol:

```swift
Text(titulo)
    .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
    } action: { ancho in
        seTrunca = ancho >= anchoMaximo
    }
```

- **Previews de Xcode 27** con asas de redimensionado: arrastra y observa cómo se reparte el espacio. En iOS 27 las apps de iPhone son redimensionables (iPhone Mirroring, iPad), así que "en iPhone el ancho es fijo" ha dejado de ser cierto.

## 4.3. Tres tipos de vista

| Tipo | Hijos | Responsabilidad | Ejemplos |
| :--- | :--- | :--- | :--- |
| **Hoja** | Ninguno | Decidir su tamaño según contenido y propuesta | `Text`, `Image`, `Color`, `Shape` |
| **Modificador** | Uno | Alterar la propuesta que baja o el tamaño que sube | `padding`, `frame`, `fixedSize` |
| **Contenedor** | Varios | Repartir la propuesta y posicionar | `HStack`, `ZStack`, `ScrollView`, `Layout` propios |

## 4.4. Vistas hoja

### `Text`

Es la vista más flexible del sistema y siempre reporta **exactamente** lo que ocupa. Ante una propuesta demasiado estrecha degrada en este orden: partir por palabras → partir por caracteres → truncar → recortar. Modificadores que cambian esa estrategia:

| Modificador | Efecto |
| :--- | :--- |
| `.lineLimit(n)` | Máximo de líneas; el resto se trunca. `.lineLimit(n, reservesSpace: true)` reserva siempre la altura de `n` líneas. |
| `.minimumScaleFactor(f)` | Reduce la fuente hasta `f` antes de truncar. |
| `.fixedSize()` / `.fixedSize(horizontal:vertical:)` | Ignora la propuesta en ese eje y reporta el tamaño ideal. |
| `.truncationMode(_:)` | Dónde se truncan las líneas (`.head`, `.middle`, `.tail`). |

### `Shape` y `Color`

`Rectangle`, `RoundedRectangle`, `Capsule`, `Ellipse` y `Color` aceptan cualquier propuesta y la reportan tal cual: rellenan lo que les den. Con `nil` en un eje, usan 10 pt.

**`Circle` no.** Reporta un cuadrado cuyo lado es la **menor** de las dos dimensiones propuestas. En un `HStack` de 320×40, un `Circle` mide 40×40, no 320×40. Es la diferencia entre `Circle` y `Ellipse`, y es pregunta de entrevista por algo.

### `Image`

Sin `.resizable()`, ignora la propuesta y reporta su tamaño intrínseco en puntos (los SF Symbols escalan con la fuente porque su tamaño intrínseco depende de ella; nada de esto es nuevo). Con `.resizable()` acepta la propuesta y la reporta; `.aspectRatio(contentMode:)` decide entre `.fit` (cabe dentro) y `.fill` (cubre, y probablemente necesitas `.clipped()`).

### `Divider`

Flexible en el eje del stack en que está y fijo en el otro: en un `VStack` ocupa todo el ancho y 1 pt de alto; en un `HStack`, todo el alto y 1 pt de ancho.

### `Spacer`

Dentro de un `HStack` o `VStack`, crece en el eje del stack hasta ocupar el espacio que sobre y no ocupa nada en el eje perpendicular. Su `minLength` por defecto es `nil`, que el sistema interpreta como el espaciado por defecto del contenedor; `Spacer(minLength: 0)` es lo que escribes cuando quieres que pueda desaparecer del todo. Dos matices que importan: si el stack recibe `nil` en su eje (dentro de un `ScrollView` en ese eje, o bajo `fixedSize`), no hay "espacio que sobre" y el `Spacer` se reduce a su `minLength`; y en un `LazyVStack`/`LazyHStack` ocurre lo mismo por la misma razón (4.6). Fuera de un stack, `Spacer` se comporta como una vista flexible en ambos ejes, que rara vez es lo que quieres.

Para alinear un solo hijo, `Spacer` es la herramienta equivocada. Un *frame* flexible con alineación da el mismo resultado sin añadir un nodo ni cambiar cómo se reparte el espacio con los hermanos:

```swift
Text(precio)
    .frame(maxWidth: .infinity, alignment: .trailing)
```

## 4.5. Modificadores

### `padding`

Resta su valor a la propuesta que baja y lo suma al reporte que sube. El contenido nunca pierde espacio por culpa del `padding`; lo pierde el padre.

### `frame` fijo

`.frame(width:height:alignment:)` propone y reporta exactamente esas dimensiones, mida lo que mida el hijo. El hijo se posiciona dentro con `alignment` y, si es más grande, **sobresale** (el *frame* no recorta; para eso está `.clipped()`).

### `frame` flexible

`.frame(minWidth:idealWidth:maxWidth:minHeight:idealHeight:maxHeight:alignment:)` hace dos *clampings*: uno de la propuesta antes de pasarla al hijo, otro del reporte del hijo antes de subirlo.

| Escritura | Resultado |
| :--- | :--- |
| `.frame(maxWidth: .infinity)` | Se expande a todo el ancho propuesto; nunca más estrecho que el hijo. |
| `.frame(minWidth: 0, maxWidth: .infinity)` | Reporta el ancho propuesto tal cual, sea el hijo más ancho o más estrecho. |
| `.frame(idealWidth: 200)` | Solo cuenta cuando alguien propone `nil` en ese eje (por ejemplo, `fixedSize`). |

### `aspectRatio`

Calcula el mayor (`.fit`) o menor (`.fill`) rectángulo con esa proporción dentro de la propuesta, se lo propone al hijo y **reporta lo que el hijo devuelve**, no el rectángulo calculado. Con un `Text` dentro, el resultado suele sorprender.

### `background` y `overlay`

El secundario recibe como propuesta el tamaño del principal y **no influye en el reporte**: el padre ve el tamaño del principal aunque el fondo sea más grande. Es lo que los hace ideales para medir y para decorar sin romper el layout.

### `fixedSize`

Propone `nil` (tamaño ideal) al hijo en los ejes indicados y reporta lo que el hijo devuelve. Es la forma de decirle a un `Text` "no te partas" o a una `Image` "usa tu tamaño". Si el resultado no cabe en el padre, sobresale.

### Modificadores que no son de layout

`.offset`, `.rotationEffect`, `.scaleEffect` y compañía actúan en la fase de **renderizado**: el layout sigue viendo la vista en su posición y tamaño originales. Si necesitas que el layout se entere, no son la herramienta (usa `padding`, `frame` o un `Layout` propio).

## 4.6. Contenedores

### `HStack` y `VStack`

Reparten el espacio del eje principal en dos fases. Primero preguntan a cada hijo su rango (`.zero` a `.infinity`) y los ordenan de **menos flexible a más flexible**; luego proponen, por ese orden, el espacio restante dividido entre los hijos que quedan. Por eso un `Text` "gana" a un `Color`: el `Text` tiene un rango estrecho y se sirve primero.

`.layoutPriority(_:)` altera ese orden: los hijos con mayor prioridad se sirven antes, independientemente de su flexibilidad. Es el mecanismo para decidir qué `Text` se trunca cuando no caben dos.

### `ZStack`

Propone a **todos** sus hijos el tamaño que recibe y reporta la **unión** de sus marcos. A diferencia de `overlay`, crece si alguno de los apilados es grande. Alineación por defecto: centro.

### `ScrollView`

Reporta el tamaño propuesto por su padre. A su contenido le propone `nil` en el eje de *scroll* (tamaño ideal) y la propuesta intacta en el otro. Es la razón por la que un `frame(maxWidth: .infinity)` dentro de un `ScrollView` vertical funciona y un `frame(maxHeight: .infinity)` no.

### `GeometryReader`

Acepta la propuesta y la reporta (es un contenedor flexible). Coloca a sus hijos en **`.topLeading`**, no en el centro; si quieres centrar, hazlo tú con `frame` o `position`. Úsalo en `background`/`overlay` para medir; como contenedor de contenido, rompe el flujo porque siempre ocupa todo lo que le proponen.

### `List`

Toma la propuesta del padre; a las filas les propone su ancho y `nil` en altura. Es perezoso (capítulo 2): las filas fuera del margen de retención no existen.

### `LazyVStack` / `LazyHStack`

No reparten espacio: proponen `nil` a cada hijo en el eje principal (tamaño ideal) y la propuesta intacta en el secundario. Un `Spacer` dentro de un `LazyVStack` no hace nada. Van siempre dentro de un `ScrollView`.

### `LazyVGrid` / `LazyHGrid`

Definen pistas con `GridItem`:

| `GridItem` | Comportamiento |
| :--- | :--- |
| `.fixed(w)` | Ancho exacto. |
| `.flexible(minimum:maximum:)` | Reparte el espacio sobrante a partes iguales. |
| `.adaptive(minimum:maximum:)` | Tantas pistas como quepan sin bajar del mínimo. La opción responsiva. |

Cuando combinas `.adaptive` con celdas de altura variable, el *grid* necesita medir en dos fases y puede verse un pase intermedio en la primera aparición. Si aparece, fija la altura de las celdas o usa un `Layout` propio (capítulo 7).

### `ViewThatFits`

Muestra el **primer** hijo (en orden de código) cuyo tamaño ideal cabe en la propuesta; si ninguno cabe, el último. Es la respuesta correcta a "un `HStack` si cabe y un `VStack` si no", y desde iOS 27 es la herramienta de primera línea para apps que pueden redimensionarse.

## 4.7. Alineación

Posicionar es el último paso: el padre coloca el origen del hijo restando la guía del hijo a la guía del padre:

$$x_{\text{origen}} = \text{guía}_{\text{padre}} - \text{guía}_{\text{hijo}}$$

Las guías integradas (`.leading`, `.center`, `.trailing`, `.top`, `.bottom`, `.firstTextBaseline`, `.lastTextBaseline`) cubren el 95 % de los casos. Para el resto:

- **`.alignmentGuide(_:computeValue:)`** sobrescribe el valor que una vista reporta para una guía. El *closure* recibe `ViewDimensions` con el tamaño y todas las guías de la vista.
- **Guías propias**: un tipo que conforma a `AlignmentID` con `defaultValue(in:)`, expuesto como extensión de `HorizontalAlignment` o `VerticalAlignment`. Sirven para alinear cosas que están en contenedores distintos (etiquetas de un formulario con sus campos).

## 4.8. Code review: el precio y el botón que se rompen con Dynamic Type

En `Pulse`, la ficha de producto tiene una fila con el precio y el botón de añadir al carrito. Está en `Product/PriceRow.swift`.

### El código que pasó la revisión

```swift
HStack {
    Text(producto.precioFormateado)
        .font(.title2.bold())
    Spacer()
    Button("Añadir al carrito") { carrito.añadir(producto) }
        .buttonStyle(.borderedProminent)
}
```

En el simulador, con el tamaño de texto por defecto, es perfecto.

### El bug

Accesibilidad reporta que con tamaños grandes de Dynamic Type el precio aparece como "1.2…" y el botón como "Añadir al…". En pantallas estrechas (o con la app redimensionada en iPad), ocurre con tamaños normales.

Lo que ha pasado en términos del algoritmo:

1. El `HStack` tiene tres hijos. `Spacer` es el más flexible (rango 0…∞), así que se sirve **el último**. Los dos `Text` (el del botón es un `Text`) tienen rangos estrechos y parecidos.
2. El `HStack` divide el ancho entre los dos hijos no flexibles a partes iguales. Ninguno cabe en su mitad.
3. Cada `Text` recibe una propuesta menor que su tamaño ideal y hace lo que sabe: truncar.
4. `Spacer` recibe lo que queda: nada.

Nadie decidió qué era más importante, así que el `HStack` no tuvo criterio.

### La solución

Primero, decidir. El precio no se puede truncar nunca; el botón puede pasar a una segunda línea. Y en tamaños de accesibilidad, la fila entera debe apilarse.

```swift
ViewThatFits(in: .horizontal) {
    // Cabe en una fila
    HStack(alignment: .firstTextBaseline) {
        precio.layoutPriority(1)
        Spacer(minLength: 12)
        boton.fixedSize(horizontal: false, vertical: true)
    }
    // No cabe: apilar
    VStack(alignment: .leading, spacing: 12) {
        precio
        boton.frame(maxWidth: .infinity)
    }
}

private var precio: some View {
    Text(producto.precioFormateado)
        .font(.title2.bold())
        .fixedSize()                        // Nunca truncar
}

private var boton: some View {
    Button("Añadir al carrito") { carrito.añadir(producto) }
        .buttonStyle(.borderedProminent)
}
```

- `layoutPriority(1)` en el precio hace que el `HStack` le sirva primero, con todo el ancho disponible.
- `fixedSize()` en el precio garantiza que reporta su ideal aunque la propuesta sea menor (si de verdad no cabe, la primera rama de `ViewThatFits` no encaja y salta a la segunda).
- `fixedSize(horizontal: false, vertical: true)` en el botón le permite crecer en alto (dos líneas) sin ensancharse.
- `ViewThatFits` decide entre fila y columna con el tamaño ideal de cada rama, sin `GeometryReader` y sin condicionales sobre `dynamicTypeSize`.
- `precio` y `boton` son propiedades computadas, no `@ViewBuilder` con lógica: el `body` de `PriceRow` sigue siendo barato aunque se ejecute en cada cambio del carrito (capítulo 8).

> **Antipatrón.** `HStack { Text; Spacer(); Button }` para "precio a la izquierda, botón a la derecha". Funciona mientras sobre espacio. En el momento en que no sobra, el `HStack` reparte a partes iguales entre dos cosas que no son igual de importantes.

## 4.9. Layout adaptativo

### `containerRelativeFrame` (iOS 17+)

Dimensiona una vista como fracción del contenedor más cercano (`ScrollView`, `NavigationStack`, ventana) **sin alterar el flujo** alrededor. Sustituye la mayoría de los `GeometryReader` que se usaban para "el 80 % del ancho":

```swift
TarjetaProducto(producto)
    .containerRelativeFrame(.horizontal, count: 5, span: 4)   // 4/5 del ancho

TarjetaProducto(producto)
    .containerRelativeFrame(.horizontal) { ancho, _ in ancho * 0.8 }
```

### El protocolo `Layout` (iOS 16+)

Cuando ningún contenedor estándar expresa lo que necesitas (un *flow*, una *masonry*, una distribución circular), un `Layout` propio te da la propuesta y el posicionamiento en las manos, con `sizeThatFits(proposal:subviews:cache:)` y `placeSubviews(in:proposal:subviews:cache:)`. Es el capítulo 7 entero.

## 4.10. Solo iOS 27+: pantallas que cambian de tamaño

Dos cosas que hasta ahora eran "cosas de iPad" son ahora de iPhone:

- **Apps de iPhone redimensionables.** Las *size classes* pueden cambiar en tiempo de ejecución en un iPhone. Todo lo que dependa de `UIScreen.main.bounds` está mal desde hace años y ahora se nota. La combinación correcta es `containerRelativeFrame` + `ViewThatFits` + `@Environment(\.horizontalSizeClass)`, en ese orden de preferencia.
- **iPhone Duo.** El primer iPhone plegable (anunciado el 9 de septiembre de 2026, a la venta en octubre) tiene una pantalla exterior con *size class* compacta y una interior con *size class* regular, más un conjunto de *poses* (cerrado, abierto, parcialmente plegado como un libro) en las que la bisagra y las cámaras se convierten en **regiones reservadas** del layout. La guía de Apple es la de este capítulo: no diseñes un layout por pose; diseña para compacto y regular con *size classes*, márgenes y *safe area*, y deja que los componentes del sistema desplacen los controles fuera de la bisagra. Para layouts propios hay tres APIs de iOS 27 que este libro no desarrolla pero que conviene conocer: las **vistas de disposición** (*arrangement views*) para presentaciones divididas o superpuestas entre regiones, la consulta de **regiones reservadas** para colocar contenido alrededor de la bisagra y las cámaras, y `onHingeChange` para reaccionar al ángulo de apertura. Un layout escrito con las reglas de 4.4 a 4.9 refluye solo; uno escrito contra `UIScreen.main.bounds`, no.

> **Regla de oro.** Si tienes que decidir qué se trunca, dilo con `layoutPriority` y `fixedSize`; si tienes que decidir entre dos disposiciones, dilo con `ViewThatFits`. Si tienes que medir, mide en un `background`. Si nada de eso basta, escribe un `Layout`. `GeometryReader` como contenedor de contenido casi nunca es la respuesta.

> **Siguiente paso.** Ejecuta `Pulse` (o tu app) con el tamaño de texto de accesibilidad más grande y redimensiona la preview en Xcode 27 hasta 320 pt. Cada `…` que veas es un `HStack` que no tiene criterio.
