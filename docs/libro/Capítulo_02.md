# Capítulo 2: Árboles de vistas, identidad y grafo de atributos

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. Las mejoras del builder unificado llegan al compilar con Xcode 27; `TupleContent` solo existe con mínimo iOS 27 y no se escribe como restricción con nuestro mínimo.

## 2.1. Dos estructuras, no una

Cuando escribes SwiftUI describes una jerarquía de vistas. Cuando el framework ejecuta esa descripción mantiene estructuras de estado y dependencias que sobreviven a las reconstrucciones de tus `struct`.

Esa distinción explica buena parte de los bugs difíciles de SwiftUI:

- el estado que parece desaparecer;
- una animación que deja de interpolar;
- una fila que empieza a comportarse como si fuera otra;
- una vista que se actualiza aunque aparentemente no haya cambiado nada.

En el libro usaremos **árbol de vistas** y **grafo de atributos** como modelos mentales. No son APIs públicas contra las que debas programar.

| | Árbol de vistas | Grafo de atributos |
| :--- | :--- | :--- |
| **Qué representa** | La descripción actual que producen tus `View` | Estado, dependencias y trabajo persistente que SwiftUI mantiene entre actualizaciones |
| **Vida** | Se reconstruye cuando SwiftUI vuelve a evaluar una vista | Puede sobrevivir a reconstrucciones de los valores `View` mientras su identidad siga siendo válida |
| **Qué contiene** | Valores y composición de vistas | Estado gestionado por SwiftUI, dependencias y otra información del runtime |
| **Lo controlas** | Directamente | Indirectamente, mediante identidad, estado y las APIs que utilizas |

La frase que quiero que recuerdes es esta:

> **La `struct` de una vista puede ser nueva y, sin embargo, el estado asociado a esa posición puede seguir siendo el mismo.**

Ese es el punto de partida para entender `@State`, `@Observable` y las listas.

## 2.2. Los modificadores construyen una estructura

Mira este código:

```swift
Text("Activo")
    .padding(8)
    .background(.green)
```

Los modificadores no mutan `Text`. Cada llamada construye otra vista que envuelve la anterior.

Una forma útil de imaginarlo es:

```text
background
└── padding
    └── Text
```

En los tipos concretos de SwiftUI moderno aparecen estructuras equivalentes a:

```text
ModifiedContent<
    ModifiedContent<Text, _PaddingLayout>,
    ...
>
```

No necesitas memorizar los nombres privados. Lo que sí necesitas entender es la consecuencia:

**el orden de los modificadores forma parte de la composición.**

Compara:

```swift
Text("Activo")
    .padding(8)
    .background(.green)
```

con:

```swift
Text("Activo")
    .background(.green)
    .padding(8)
```

En el primero, el fondo recibe el tamaño de `Text` más el `padding`. En el segundo, el fondo se aplica al `Text` y el `padding` queda fuera.

No has cambiado un detalle estético. Has cambiado la estructura que SwiftUI tiene que evaluar.

> **Pro Tip para Seniors.** Cuando un modifier parece "no funcionar", antes de buscar otra API dibuja mentalmente el árbol que has construido. Muchas veces el problema está dos líneas antes.

## 2.3. `ContentBuilder`: el cambio que importa en Xcode 27

SwiftUI utiliza *result builders* para transformar un closure declarativo en contenido tipado.

Con:

```swift
HStack {
    Image(systemName: "person")
    Text("Javier")
}
```

no estás pasando dos parámetros independientes a `HStack`. El closure construye un único valor de contenido que representa a sus hijos.

En Xcode 27, Apple unifica bajo **`ContentBuilder`** varios builders específicos de SwiftUI. `ViewBuilder` pasa a construirse sobre `ContentBuilder`, y la implementación cambia en un punto clave: durante la construcción, el contenido deja de estar atado a la conformidad `View` y pasa a ser agnóstico respecto al tipo de contenido que acabará produciendo. Eso permite que APIs de `View`, `ToolbarContent`, `Commands` y otros tipos compartan el mismo mecanismo, y elimina la búsqueda de sobrecargas indistinguibles que hacía lento el *type-checking* de builders grandes.

La diferencia importante para este libro es que **`TupleView` deja de ser el modelo mental que conviene enseñar**. Con un mínimo de despliegue iOS 27, el builder produce `TupleContent`; con nuestro *deployment target* iOS 18, `TupleContent` no está disponible y una restricción genérica escrita explícitamente sigue teniendo que decir `TupleView`. La propia nota técnica TN3211 de Apple muestra este caso y recomienda preferir tipos opacos como `some View`; cuando necesitas escribir una restricción concreta y el mínimo es anterior a iOS 27, conserva `TupleView`.

Por tanto, la regla práctica es sencilla:

```swift
struct CardView<Content: View>: View {
    let content: Content

    var body: some View {
        content
    }
}
```

Escribe `some View` cuando puedas. No dependas de la forma concreta que el builder genera internamente.

> **Migrando a Xcode 27.** Si actualizas un proyecto con *deployment target* iOS 18 a Xcode 27, los primeros errores de `ContentBuilder` aparecen donde antes habías dejado tipos concretos o ambigüedades que la restricción `View` resolvía por ti. TN3211 recoge, entre otros: ambigüedad en `.background`/`.overlay` con expresiones de `ShapeStyle` (`.overlay(Color.blue.opacity(0.3))` → usa la forma con *closure*), colisiones de nombres entre módulos (`Color.clear` cuando otro módulo declara `Color` → cualifica con `SwiftUI.`), contenido vacío en builders anidados con MapKit en scope (`Group { }` → `Group { EmptyContent() }`) y restricciones genéricas escritas con `TupleView`. La solución general es dejar que el compilador infiera el tipo mediante `some View` o, cuando necesitas un tipo concreto, adaptar la restricción a las disponibilidades del mínimo de despliegue.

Lo que sí merece la pena conservar como modelo mental es más estable que cualquiera de esos nombres:

1. El builder convierte el código declarativo en una estructura que SwiftUI puede reconciliar.
2. Las condiciones (`if`, `switch`) forman parte de esa estructura.
3. Los contenedores interpretan el contenido resultante como una colección de hijos que pueden medir, posicionar y actualizar.

### `Group` no es un contenedor de layout

`Group` agrupa contenido sin añadir su propia geometría.

```swift
HStack {
    Group {
        Text("Usuario:")
        Text("Javier")
    }
    .border(.blue)
}
```

El borde se aplica a cada miembro del `Group`, no a una caja alrededor del conjunto. Apple documenta precisamente que `Group` permite agrupar vistas sin afectar a su layout y que un modificador aplicado al grupo afecta a sus miembros.

Si quieres una caja común, necesitas una vista que tenga geometría propia:

```swift
VStack {
    Text("Usuario:")
    Text("Javier")
}
.border(.blue)
```

La confusión aparece porque un `Group` puede aparecer como contenido de otro contenedor y parecer visualmente "transparente". No hay un stack oculto. El layout lo decide el contenedor real.

## 2.4. Contenido condicional: la identidad también cambia

Considera:

```swift
HStack {
    Image(systemName: "person")

    if usuario.esPremium {
        Text("Premium")
    }
}
```

La rama condicional forma parte del tipo generado por el builder.

Cuando `usuario.esPremium` pasa de `false` a `true`, aparece un nuevo hijo.

Esto se vuelve más interesante con `if/else`:

```swift
if modoCompacto {
    FilaCompacta(item: item)
} else {
    FilaExpandida(item: item)
}
```

Aquí no tienes una única `Fila` con una configuración diferente. Tienes **dos ramas estructurales**.

Eso importa si alguna de las ramas tiene estado:

```swift
struct FilaExpandida: View {
    @State private var desplegada = false

    // ...
}
```

Al cambiar de rama, no debes esperar que ese estado pertenezca mágicamente a la otra.

Cuando una condición cambia mientras el usuario está interactuando con la UI, la pregunta útil no es solo qué componente se muestra, sino si realmente estás mostrando dos componentes diferentes o el mismo componente en dos configuraciones. Esa distinción determina qué estado puede conservarse.

## 2.5. Reconciliación: la pregunta que realmente importa

Cuando SwiftUI vuelve a evaluar una parte del árbol, necesita decidir qué puede conservar.

Una forma útil de pensar el proceso es:

```text
Nueva descripción
      ↓
¿Corresponde al mismo nodo?
   ↙           ↘
 sí             no
 ↓               ↓
actualizar      insertar/eliminar
 ↓               ↓
preservar       nuevo estado
estado
```

No interpretes esto como una especificación de la implementación interna. Es el modelo que necesitamos para razonar sobre el comportamiento observable.

La pregunta es:

> **¿Es esto la misma cosa que estaba aquí antes?**

Y aquí aparece la identidad.

## 2.6. Identidad estructural

SwiftUI obtiene una parte importante de la identidad de la **estructura del árbol**. Un ejemplo que sí ocurre en producción es hacer que la presencia de un modificador dependa de una condición:

```swift
extension View {
    @ViewBuilder
    func applyIf<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

Text(titulo)
    .applyIf(destacado) { $0.font(.headline) }
```

Cuando `destacado` cambia, no estás alternando un valor dentro de la misma composición: el builder construye dos ramas estructuralmente distintas, una con el modificador y otra sin él. En una vista con estado, esa diferencia hace que SwiftUI trate el subárbol como otra identidad.

El problema no es `font(.headline)`. El problema es esconder una bifurcación estructural en un *helper* y usarla sobre una vista cuyo estado quieres conservar. Es más predecible construir una sola estructura y variar sus parámetros:

```swift
Text(titulo)
    .font(destacado ? .headline : .body)
```

No interpretes esto como "cada diferencia de tipo destruye la pantalla". La regla útil es más concreta: **la estructura participa en cómo SwiftUI identifica y actualiza los nodos**, así que una condición que cambia la propia composición merece revisión de identidad y estado.

### Identidad explícita: `.id`

`.id(value)` hace explícita una parte de esa identidad:

```swift
DetailView(producto: producto)
    .id(producto.id)
```

Si cambia el valor que utilizas como identidad, SwiftUI puede tratar esa vista como una nueva identidad. Apple documenta que el cambio del valor de `id` reinicia la identidad de la vista y, con ella, su estado.

Esto hace que `.id` sea una herramienta poderosa y peligrosa.

Útil:

```swift
FormularioPedido(pedido: pedido)
    .id(pedido.id)
```

cuando quieres expresar explícitamente que cambiar de pedido debe reiniciar el formulario.

Peligroso:

```swift
SomeView()
    .id(UUID())
```

porque acabas de decirle a SwiftUI que la vista sea nueva cada vez.

> **Antipatrón.** No utilices `.id` para "arreglar" problemas de actualización que todavía no entiendes. Cambiar identidad también reinicia estado y puede romper animaciones.

### `ForEach`: identidad de los datos

`ForEach` identifica cada elemento mediante `Identifiable` o mediante el `id` que tú proporciones. Apple advierte expresamente que un cambio de `id` hace que el contenido generado pierda estado y animaciones.

Un caso especialmente peligroso es:

```swift
ForEach(items.indices, id: \.self) { index in
    FeedRow(item: items[index])
}
```

Si insertas o eliminas elementos, el índice deja de identificar el producto; identifica simplemente su posición.

Mucho mejor:

```swift
ForEach(items) { item in
    FeedRow(item: item)
}
```

si `Item.ID` es realmente estable y único.

Y absolutamente no:

```swift
ForEach(items, id: \.self) { item in
    // ...
}
```

si `Hashable` no representa una identidad estable.

## 2.7. Un detalle de Xcode 27 que merece conocer un senior

Hay otro cambio menos vistoso pero muy interesante.

Apple documenta que `List` y `LazyVStack` trabajan de forma perezosa con los elementos de `ForEach`. También documenta un *slow path* cuando cada elemento puede producir un número no constante de vistas. Por ejemplo:

```swift
ForEach(items) { item in
    if item.isVisible {
        Text(item.title)
    }
}
```

Para resolverlo, puedes hacer que cada elemento represente una cantidad constante de vistas:

```swift
ForEach(items) { item in
    VStack {
        if item.isVisible {
            Text(item.title)
        }
    }
}
```

Apple documenta además un argumento de lanzamiento para diagnosticar estos casos:

```text
-LogForEachSlowPath YES
```

En este libro lo tratamos como una herramienta del repositorio, no como una pieza de API sobre la que construir arquitectura: antes de incluirlo en el CI, la *build* de `Pulse` debe ejecutarlo en Xcode 27 y registrar el resultado observado.

Esto es exactamente el tipo de detalle que un senior puede convertir en una regla de code review:

> **En un `ForEach` perezoso, no pienses solo en qué muestra cada elemento. Piensa también en cuántas vistas produce cada elemento.**

## 2.8. Ciclo de vida en listas: no confundas lazy con caché

`List`, `LazyVStack` y `LazyVGrid` son perezosos: no necesitan construir todos sus hijos a la vez.

No conviertas eso en una regla falsa como:

> "Cuando una fila sale de pantalla, su `@State` siempre se destruye inmediatamente."

No tienes ese contrato.

Lo que sí tienes que aceptar como ingeniero es que **el lifecycle de una fila lazy no es un almacén fiable para estado de producto que deba sobrevivir al scrolling o a la reconstrucción del contenido**.

Si el usuario ha marcado un artículo como favorito, ha empezado a editarlo o ha expandido una noticia y esa información importa después, guarda ese estado en una fuente de verdad identificada por el `id` del elemento.

La fila debería proyectar ese estado; no inventárselo.

### `onAppear` y `onDisappear`

Son eventos de visibilidad y no deben utilizarse como equivalente a `init` y `deinit`.

Pueden aparecer muchas veces durante la interacción normal.

### `.task`

Cuando necesitas asociar trabajo asíncrono a una vista, `.task` proporciona una relación más clara con su lifecycle:

```swift
.task(id: item.id) {
    await modelo.cargarDetalle(item.id)
}
```

El sistema cancela la tarea cuando la vista deja de estar presente o cambia el valor que alimenta `id`. La cancelación sigue siendo **cooperativa**: el trabajo que ejecuta la tarea tiene que responder a ella.

## 2.9. Code review: la fila del feed que se colapsa sola

En `Pulse`, cada noticia puede desplegar un resumen.

El bug apareció después de introducir un ranking que puede promocionar una noticia mientras el usuario la está leyendo.

### El código que pasó la revisión

```swift
struct FeedRow: View {
    let articulo: Articulo
    @State private var desplegada = false

    var body: some View {
        if articulo.esDestacado {
            FilaDestacada(
                articulo: articulo,
                desplegada: $desplegada
            )
        } else {
            FilaNormal(
                articulo: articulo,
                desplegada: $desplegada
            )
        }
    }
}
```

A primera vista está bien.

El `@State` está en `FeedRow`, no en las ramas. Así que alguien podría revisar el código y pensar:

> "El estado está arriba. Perfecto."

### El primer bug

La noticia pasa de normal a destacada.

```text
FilaNormal
    ↓
articulo.esDestacado = true
    ↓
FilaDestacada
```

La rama estructural cambia.

`FeedRow` sigue existiendo, así que su `desplegada` puede conservarse. Pero cualquier estado interno que viva en `FilaNormal` o `FilaDestacada` pertenece a nodos diferentes.

Eso es justo lo que ocurre en `Pulse` con el cálculo de altura y la animación interna de la fila.

Resultado:

> El usuario no ha dejado de interactuar con la noticia, pero SwiftUI acaba de sustituir una parte de su subárbol por otra.

### El segundo bug

El equipo había colocado además parte del estado de edición dentro de la fila:

```swift
@State private var modoLectura = true
```

Eso era todavía peor.

Una fila lazy no es el lugar adecuado para convertir el lifecycle de una vista en la fuente de verdad de una interacción de producto.

El *scroll* puede hacer que una fila deje de participar en el contenido visible y posteriormente vuelva a aparecer. No necesitas prometer exactamente cuándo SwiftUI conserva o libera un nodo. Necesitas diseñar sin depender de ello.

### Cómo lo reproducimos

En la build de depuración de `Pulse` existe una acción:

```text
Debug → Feed → Promocionar artículo seleccionado
```

La vista contiene:

```swift
let _ = Self._printChanges()
```

En el caso problemático puedes observar cambios de identidad en las vistas que pertenecen a la rama sustituida.

`_printChanges()` es una herramienta de diagnóstico con guion bajo. Úsala para entender el problema, no como parte del código de producción.

### La solución

Primero eliminamos la bifurcación estructural:

```swift
struct FeedRow: View {
    let articulo: Articulo
    @Bindable var estado: EstadoFeed

    var body: some View {
        FilaArticulo(
            articulo: articulo,
            destacada: articulo.esDestacado,
            desplegada: estado.binding(
                desplegada: articulo.id
            )
        )
    }
}
```

Ahora tenemos una sola identidad estructural.

La diferencia entre una noticia normal y una destacada es **estado/configuración**, no una vista completamente distinta.

Segundo, el estado que pertenece al producto vive fuera de la fila:

```swift
@Observable
@MainActor
final class EstadoFeed {
    var desplegadas: Set<Articulo.ID> = []

    func binding(
        desplegada id: Articulo.ID
    ) -> Binding<Bool> {
        Binding(
            get: { self.desplegadas.contains(id) },
            set: { desplegada in
                if desplegada {
                    self.desplegadas.insert(id)
                } else {
                    self.desplegadas.remove(id)
                }
            }
        )
    }
}
```

Ahora el lifecycle de `FeedRow` deja de decidir si una noticia está desplegada.

La fila simplemente representa el estado.

### Las dos preguntas del revisor

Antes:

> ¿Qué vista tengo aquí?

Ahora:

> **¿Qué identidad debe conservarse?**

Y:

> **¿Dónde debe vivir el estado para que el lifecycle de la vista no pueda borrarlo?**

Esas dos preguntas evitan una cantidad sorprendente de bugs.

## 2.10. Un segundo code review: el `id` que parece inocente

Imagina que producto pide insertar una campaña promocional al principio del feed.

El código existente es:

```swift
ForEach(items.indices, id: \.self) { index in
    FeedRow(item: items[index])
}
```

Funciona durante meses.

Hasta que aparece una promoción al principio.

```text
Antes:
0 → artículo A
1 → artículo B
2 → artículo C

Después:
0 → promoción
1 → artículo A
2 → artículo B
3 → artículo C
```

Para SwiftUI, la identidad de la fila 0 no era "artículo A".

Era `0`.

Has desplazado todas las identidades.

El resultado puede ser:

- estado visual asociado al artículo equivocado;
- animaciones extrañas;
- focus perdido;
- scroll que se comporta de forma inesperada.

El código correcto es:

```swift
ForEach(items) { item in
    FeedRow(item: item)
}
```

siempre que `item.id` sea una identidad de producto estable.

La regla que sale de aquí cabe en una frase: **un `id` no describe dónde está un elemento. Describe quién es.**

## 2.11. El experimento del repositorio: índice frente a identidad estable

En `Pulse`, este caso no se queda en una advertencia editorial: es un test que falla con índices y pasa con identidad estable.

El truco para hacer visible la identidad es darle a cada fila una memoria de su propio nacimiento. La fila guarda en `@State` el título del artículo para el que se creó su nodo, asignado en el `init`:

```swift
struct FilaConMemoria: View {
    let articulo: Articulo
    @State private var nacidaPara: String

    init(articulo: Articulo) {
        self.articulo = articulo
        self.nacidaPara = articulo.titulo
    }
    // ...
}
```

Como una asignación en el `init` solo cuenta cuando el nodo nace (capítulo 3, §3.3), `nacidaPara` no cambia aunque la `struct` se reconstruya: si más tarde la fila muestra otro artículo, su nodo no se ha recreado, se ha **reutilizado** para un dato distinto. El test monta tres filas, inserta una promoción al principio y comprueba que ninguna muestre un artículo distinto del que la creó. Con `ForEach(items.indices, id: \.self)`, el resultado es:

```text
filas reutilizadas para otro artículo (nació para → muestra): ["A→Promoción", "B→A", "C→B"]
```

Cada nodo se ha quedado en su posición y ha recibido el artículo que antes tenía su vecino. Cualquier estado que esas filas guardaran —desplegada, con foco, a medio editar— viaja con el nodo, no con el artículo. Con `ForEach(items)` no hay ningún desajuste: la promoción nace como nodo nuevo y A, B y C conservan los suyos.

## 2.12. Identidad y reordenación en iOS 27

iOS 27 añade APIs de reordenación para listas, stacks, grids y layouts personalizados. Esto hace que la identidad sea todavía más importante: mover un elemento no debería convertirlo en otro elemento.

La pregunta durante una reordenación es muy simple:

```text
Artículo A
    ↓
sigue siendo Artículo A
    ↓
aunque cambie de posición
```

Por eso un identificador estable no es un detalle para satisfacer al compilador.

Es parte del modelo de datos.

## 2.13. Herramientas para investigar identidad

### `_printChanges()`

La forma rápida de investigar una vista durante desarrollo:

```swift
var body: some View {
    let _ = Self._printChanges()

    // ...
}
```

Xcode 27 sigue manteniendo esta herramienta y Apple continúa presentándola como ayuda rápida para entender qué causó una actualización. El guion bajo importa: no es una API pública estable sobre la que construir arquitectura.

### SwiftUI Instrument

Cuando el problema es más grande que una vista, usa el instrumento SwiftUI de Instruments.

El objetivo ya no es:

> "¿Se ejecuta `body` muchas veces?"

sino:

> **"¿Qué cambio de datos provoca estas actualizaciones y cuáles de ellas son realmente caras?"**

El instrumento tiene tres pistas (*Update Groups*, *Long View Body Updates* y *Cause & Effect Graph*) que relacionan el origen de una actualización con los `body` afectados. Se explican en 8.2; su uso para diagnosticar dependencias de estado, en 3.13.

## 2.14. Lo que debería recordar un senior

1. `View` es un valor; el estado que gestiona SwiftUI puede sobrevivir a la reconstrucción de ese valor.
2. La estructura de la vista participa en la identidad. Un `if/else` entre dos subárboles no es lo mismo que cambiar una configuración.
3. `.id` es una herramienta de identidad, no un parche de actualización.
4. `ForEach` necesita una identidad estable del dato, no una posición conveniente.
5. En contenedores lazy, el estado de UI efímero y el estado de producto no son la misma cosa.
6. `ContentBuilder` cambia la implementación de los builders en Xcode 27, pero no cambia la regla fundamental: la composición tiene estructura y esa estructura importa.

> **Regla de oro.** No preguntes primero "¿por qué se ha redibujado?". Pregunta **"¿qué identidad cree SwiftUI que tiene esta cosa?"**. Después pregunta quién posee su estado.

> **Siguiente paso.** Busca en tu proyecto tres cosas: `ForEach` basado en índices, `.id(` que recibe valores generados en tiempo de ejecución y `if/else` entre vistas que contienen `@State`. Esos tres patrones merecen una revisión manual.
