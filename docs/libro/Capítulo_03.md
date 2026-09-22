# Capítulo 3: Estado, ownership y `Binding`

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27. El recuadro de 3.4 y la sección 3.3 dependen de la macro `@State` de Xcode 27 (con *back-deploy*); 3.14 requiere iOS 26.

## 3.1. El ciclo de reconciliación

El capítulo anterior dejó el árbol de vistas como plano efímero y el grafo de atributos como memoria persistente, y la reconciliación como la pregunta que SwiftUI se hace en cada posición: ¿es esta la misma vista que había? Este capítulo trata de lo que vive en esa memoria, que es lo que hace que la pregunta importe: el estado.

Al ciclo del capítulo 2 solo le falta un paso por delante para quedar completo. **Evento**: algo cambia una fuente de estado que el grafo rastrea, un toque, una respuesta de red, un `Timer`. **Invalidación**: el nodo que depende de esa fuente se marca sucio, y solo ese. Desde ahí, construcción y reconciliación son ya lo conocido.

Tu trabajo es la construcción: describir la interfaz *dado* un estado. El resto lo hace el *framework*, y lo hace bien mientras no le mientas sobre dónde vive el estado o sobre quién es quién en el árbol.

> **Advertencia.** Un `body` que se ejecuta de más no es un error de corrección; es un error de rendimiento que solo se ve en Instruments. La sección 3.13 explica cómo verlo. Hasta entonces, la regla es sencilla: si no sabes por qué un `body` se ha ejecutado, tienes un problema aunque la app funcione.

### Tres generaciones de gestión de estado

| Etapa | Mecanismo | Estado en 2026 |
| :--- | :--- | :--- |
| iOS 13–16 | `ObservableObject` + `@Published` + `@StateObject` / `@ObservedObject` (Combine) | *Legacy*. Se mantiene en código pre-iOS 17 (secciones 3.8–3.10). |
| iOS 17+ | Macro `@Observable` (framework Observation), rastreo por propiedad | **Estándar.** Base de todo el libro. |
| iOS 26/27 | `Observations` (secuencia asíncrona sobre `@Observable`); `@State` como macro con inicialización perezosa de clases | Refinamientos sobre el modelo de iOS 17, no un modelo nuevo. |

Empezamos por `@State`, que es el fundamento de todo lo demás.

---

## 3.2. `@State`: memoria persistente para tipos de valor

`@State` declara estado **privado** de la vista que sobrevive a la reconstrucción de la `struct`. El valor no vive en la `struct` (efímera); vive en el nodo del grafo de atributos (persistente).

```swift
struct Contador: View {
    @State private var valor = 0

    var body: some View {
        Button("Incrementar: \(valor)") {
            valor += 1   // Mutación no-mutating: escribe en el nodo, no en la struct
        }
    }
}
```

Al ejecutar el `body`, SwiftUI registra una dependencia entre la **lectura** de `valor` y el nodo de `Contador`. Cuando `valor` cambia, ese nodo se invalida.

### Lo que hace el *property wrapper*

Puedes escribir a mano una aproximación de lo que hay detrás. `State(initialValue:)` es una API pública y sirve para verlo (con Xcode 27 la macro genera algo más elaborado, con evaluación perezosa; el contrato es el mismo):

```swift
struct Contador: View {
    private var _valor = State(initialValue: 0)

    private var valor: Int {
        get { _valor.wrappedValue }
        nonmutating set { _valor.wrappedValue = newValue }
    }
    // ...
}
```

El nombre `initialValue` es la pista importante: ese `0` se usa **una sola vez**, cuando el nodo se crea. En cada reconstrucción posterior de la `struct`, el `0` se ignora y `wrappedValue` lee del nodo.

### El flujo interno

| Momento | `struct` (plano) | Nodo (memoria) | Qué ocurre |
| :--- | :--- | :--- | :--- |
| Inicialización | `_valor.initialValue = 0` | — | Se construye la `struct`. Todavía no hay nodo. |
| Inserción en el grafo | El `initialValue` se copia al nodo | `valor = 0` | Se asigna memoria persistente. |
| `body` | Lee `valor` del nodo | `valor = 0` | Se registra la dependencia. |
| Mutación | El `setter` escribe en el nodo | `valor = 1` | Se invalida el nodo. |
| Reconstrucción | Nueva `struct`, `initialValue = 0` ignorado | `valor = 1` | `body` lee `1`. |

---

## 3.3. `@State` e identidad

El estado está atado a la **identidad** del nodo (capítulo 2). Mientras el nodo exista, el estado persiste; si el nodo se destruye (cambio de rama en un `if`, cambio de `.id`, salida del *viewport* de retención de un contenedor perezoso), el estado se pierde y el siguiente nodo empieza con el `initialValue`.

De ahí que `@State` sea siempre `private`: nadie fuera de la vista puede razonar sobre cuándo ese nodo existe.

### Inicializar `@State` desde `init`

Es legítimo y a veces necesario. Con Xcode 27, `@State` es una macro y la propiedad se trata como cualquier otra propiedad almacenada, así que se asigna directamente:

```swift
struct Contador: View {
    let titulo: String
    @State private var valor: Int          // Sin valor en línea

    init(titulo: String, inicial: Int) {
        self.titulo = titulo               // (1) Primero el resto de propiedades
        self.valor = inicial               // (2) Después el @State
    }
}
```

Tres reglas que la nota técnica TN3211 de Apple fija para esta forma, y que el compilador de Xcode 27 hace cumplir:

1. **Todas las propiedades que no sean `@State` se inicializan antes** de asignar a un `@State`. Si no, el compilador reporta "`self` used before being initialized" sobre el almacenamiento sintetizado (`_valor`).
2. **Si el `@State` tiene valor en línea, la asignación en `init` se descarta.** `@State private var valor = 0` seguido de `self.valor = inicial` en `init` compila y el `body` ve `0`. Es silencioso. Si el valor debe venir del `init`, omite el valor en línea.
3. **Una `struct` con `@State` privado no recibe el inicializador *memberwise* sintetizado.** Si lo llamabas desde una extensión (`self.init(bar:baz:)`), ahora hay que escribirlo.

Lo que **no** hace este patrón es reaccionar a cambios de `inicial`. Si el padre pasa `5` y después `9`, el nodo sigue con el valor que tuviera. Si necesitas que la vista siga al padre, el parámetro no es estado: es una propiedad normal o un `Binding`.

> **Antipatrón.** `@State private var texto: String` inicializado desde `init` y "misteriosamente" desincronizado del padre. No es un *bug* de SwiftUI: es que has declarado como estado privado algo que pertenece al padre. Y su variante silenciosa en Xcode 27: `@State private var texto = ""` con `self.texto = inicial` en `init`, que compila y nunca usa `inicial`.

**El coste de esta forma.** Medido en el repositorio: una vista cuyo padre se redibuja cinco veces construye **seis** modelos y usa el primero. El `@State` hace su trabajo (el estado persiste), pero la evaluación perezosa de la macro (siguiente sección) no se aplica aquí: el inicializador corre en cada reconstrucción de la `struct`. Si el modelo es barato, da igual. Si abre una conexión, carga una plantilla o reserva memoria, no: pásale el valor por parámetro a un modelo creado en línea, o deja que lo cree el padre y recíbelo como propiedad normal.

---

## 3.4. `@Observable`: el modelo estándar

La macro `@Observable` (iOS 17) convierte las propiedades almacenadas de una clase en propiedades que **registran lecturas y notifican escrituras** a través de un `ObservationRegistrar`. No requiere Combine, no requiere `@Published` y rastrea **por propiedad**: una vista que lee `modelo.nombre` no se invalida cuando cambia `modelo.edad`.

```swift
@Observable @MainActor
final class ModeloContador {
    var valor = 0
}
```

`@MainActor` en el modelo no es opcional en Swift 6: el `body` se ejecuta en el `MainActor` y leer una propiedad mutable de una clase no aislada desde ahí es un error de aislamiento. Con el aislamiento por defecto de Xcode 27 la anotación es implícita en el módulo de la app; escribirla explícita en los modelos no cuesta nada y documenta la intención.

### Quién posee el objeto

Esta es la decisión que más estado pierde en producción. La `struct` de la vista se reconstruye cada vez que el padre ejecuta su `body`. Cualquier objeto que crees en una propiedad normal de la `struct` **se recrea con ella**:

```swift
struct Contador: View {
    private let modelo = ModeloContador()   // ❌ Nuevo objeto en cada reconstrucción
    // ...
}
```

Cada vez que el padre se redibuja, este `Contador` recibe un `ModeloContador` recién creado con `valor = 0`. El estado desaparece. No siempre se nota (si el padre no se redibuja, parece funcionar), que es lo que lo hace peligroso.

El patrón correcto para un objeto que la vista **posee** es `@State`:

```swift
struct Contador: View {
    @State private var modelo = ModeloContador()   // ✅ Vive en el nodo

    var body: some View {
        Button("Inc: \(modelo.valor)") {
            modelo.valor += 1
        }
    }
}
```

`@State` almacena la referencia en el nodo del grafo; las reconstrucciones de la `struct` reutilizan el mismo objeto.

> **Solo Xcode 27: `@State` es ahora una macro.** Hasta Xcode 26, `@State private var modelo = ModeloContador()` construía un `ModeloContador` en **cada** inicialización de la `struct` y lo descartaba en todas menos la primera (el *wrapper* recibía el valor, no un *autoclosure*). Era un coste real en listas grandes y un argumento clásico contra `@State` con clases. En Xcode 27, `@State` se implementa como macro y **el inicializador no se reevalúa**: en nuestras pruebas, cinco reconstrucciones de la vista produjeron una sola construcción del objeto. Se despliega hacia atrás (hasta iOS 17) al compilar con Xcode 27, así que aplica a toda la ventana de este libro.
>
> El ahorro tiene una condición que conviene conocer: vale para el **valor inicial en línea**, la forma de este ejemplo. Si en cambio declaras el tipo y asignas el valor en el `init` (sección anterior), el inicializador vuelve a ejecutarse en cada reconstrucción de la `struct`: el estado se conserva igual (la vista sigue usando la primera instancia), pero el coste de construir y descartar se paga entero. El patrón `@State` + `@Observable` sigue siendo el correcto; la forma en línea es la que además ahorra construcción.

Para un objeto que la vista **no posee** (lo crea el padre, un contenedor de dependencias o el entorno), no uses ningún *wrapper*: una propiedad normal basta, porque la observación la hace la macro, no la vista.

```swift
struct DetalleContador: View {
    let modelo: ModeloContador   // Referencia recibida; no la posee

    var body: some View {
        Text("\(modelo.valor)")  // Se invalida si cambia .valor
    }
}
```

---

## 3.5. Anatomía de la observación

Lo que hace la macro, conceptualmente:

1. **Rastreo.** SwiftUI ejecuta el `body` dentro de `withObservationTracking`.
2. **Registro.** Cada `get` de una propiedad observable llama a `registrar.access(self, keyPath:)`, que anota "este nodo depende de `\.valor`".
3. **Notificación.** Cada `set` llama a `registrar.withMutation(of:keyPath:)`, que avisa a los nodos registrados para ese *key path* **antes** de escribir.

De aquí sale la granularidad por propiedad y también dos consecuencias que conviene tener claras:

- **Solo se rastrea lo que se lee dentro del `body`** (o dentro del *closure* de `withObservationTracking`). Leer una propiedad en `init` o en un `Task` no crea dependencia.
- **Las colecciones se observan como un todo.** Si `items` es un `[Item]` y cambia un elemento, se invalidan todas las vistas que leen `items`. Para granularidad por elemento, los elementos deben ser a su vez `@Observable` y las filas deben leerlos directamente.

> **Observation compara antes de notificar.** Hay una cuarta consecuencia que no aparece en la documentación de Apple: el paso 3 (Notificación) solo ocurre si el valor **nuevo es distinto** del anterior. La comparación usa la igualdad del tipo (`Equatable`, o identidad para las referencias): `modelo.contador = 5` sobre un `5` no llega a notificar a nadie. Un tipo que **no** conforma a `Equatable` no se puede comparar, así que cada escritura notifica aunque el contenido sea idéntico. De ahí una regla poco intuitiva: **conformar tus modelos de datos a `Equatable` reduce invalidaciones**, y es de las optimizaciones más baratas que hay. El capítulo 8 tiene un caso completo construido sobre esta base.

---

## 3.6. Antipatrones de ciclo de vida

1. **Objeto poseído en `let`.** Visto en 3.4. Síntoma: el estado se resetea "a veces".
2. **`@State` alimentado desde `init` esperando que siga al padre.** Visto en 3.3. Síntoma: la vista muestra un valor antiguo.
3. **Modelo pesado leído entero cuando solo necesitas un campo.** Pasar `let item: Item` a una fila y leer `item.titulo` es correcto (la observación es por propiedad). Pasar el modelo raíz `let app: AppModel` a todas las filas y leer `app.items[i].titulo` no lo es: cada fila depende de `app.items` entero.
4. **Mutar un `@Observable` desde fuera del `MainActor`.** No compila en Swift 6; si lo consigues con `nonisolated(unsafe)`, tienes un *data race* con la UI.

---

## 3.7. Code review: el checkout que pierde el formulario

Este es el caso que hace que todo lo anterior deje de ser teoría. Está en `Pulse`, la app del repositorio, en `Checkout/CheckoutView.swift`.

### El código que pasó la revisión

```swift
struct CheckoutView: View {
    let orderID: UUID
    private let modelo = CheckoutModel()          // (1)

    var body: some View {
        VStack {
            if promociones.hayBannerActivo {       // (2)
                PromoBanner()
            }
            PaymentForm(modelo: modelo)
        }
    }
}

@Observable @MainActor
final class CheckoutModel {
    var titular = ""
    var numeroTarjeta = ""
    var aceptaCondiciones = false
}
```

Nadie lo paró en revisión porque funciona: en el simulador rellenas el formulario, pulsas pagar, todo bien.

### El bug

En producción, un porcentaje pequeño de usuarios reportaba que "el formulario se vacía solo". Todos tenían algo en común: durante el checkout aparecía un banner de promoción cargado por red.

La secuencia:

1. `CheckoutView` se muestra. Su `struct` se construye una vez y crea `CheckoutModel()` en (1).
2. El usuario rellena titular y número de tarjeta. Escribe en el objeto creado en el paso 1.
3. Llega la respuesta de red y `promociones.hayBannerActivo` pasa a `true`. Esa propiedad la lee `CheckoutView` en (2), así que **el nodo de `CheckoutView` se invalida**.
4. Para ejecutar el `body` de `CheckoutView`, SwiftUI **vuelve a construir la `struct` `CheckoutView`**. Al construirla, la línea (1) se ejecuta otra vez: **`CheckoutModel()` nuevo, con todo vacío**.
5. `PaymentForm` recibe el objeto nuevo. El formulario aparece vacío.

El usuario no ha hecho nada. La app no ha crasheado. Ningún test unitario lo detecta, porque el modelo funciona perfectamente; lo que falla es quién lo posee.

### Reproducirlo en cinco minutos

En el repositorio, `CheckoutView` tiene un `let _ = Self._printChanges()` comentado. Descoméntalo, ejecuta, rellena un campo y activa el banner desde el menú de depuración. Verás en consola:

```
CheckoutView: @self changed.
```

`@self` significa "la `struct` entera es distinta". Es la huella exacta de este bug: la vista no ha cambiado de identidad (no verás `@identity`), pero la `struct` se ha reconstruido, y con ella todo lo que la `struct` creaba en sus propiedades.

### La solución

```swift
struct CheckoutView: View {
    let orderID: UUID
    @State private var modelo = CheckoutModel()   // Vive en el nodo, no en la struct
    // ...
}
```

Una palabra. Ahora el objeto se guarda en el nodo del grafo la primera vez, y las reconstrucciones posteriores de la `struct` reutilizan la misma instancia. Con Xcode 27, además, `CheckoutModel()` ni siquiera se vuelve a evaluar en esas reconstrucciones.

### Lo que el revisor tenía que haber preguntado

No "¿qué *wrapper* toca aquí?", sino dos preguntas en orden:

1. **¿Quién posee este objeto?** Si lo crea esta vista, `@State`. Si lo crea otro, propiedad normal.
2. **¿Quién necesita escribirlo?** Si un hijo, `@Bindable` en el hijo (3.12).

> **Antipatrón.** `private let modelo = Modelo()` en una `struct` que conforma a `View`. Compila, funciona en el simulador y pierde estado en producción exactamente cuando el padre se redibuja por una razón que no tiene que ver con el modelo.

---

## 3.8. *Legacy*: `ObservableObject`

Antes de iOS 17, la única forma de que SwiftUI observara un tipo de referencia era el protocolo `ObservableObject` de Combine. Lo necesitas si mantienes código que ya lo usa; no lo escribas nuevo.

El protocolo exige un *publisher* `objectWillChange` que emite **antes** de cada mutación. `@Published` es azúcar para llamar a `objectWillChange.send()` en el `willSet`:

```swift
final class Modelo: ObservableObject {
    @Published var valor = 0
}
```

La diferencia de fondo con `@Observable`: la notificación es **a nivel de objeto**. Cualquier vista suscrita se invalida ante cualquier `@Published` que cambie, lo lea o no.

---

## 3.9. *Legacy*: `@StateObject`

Equivalente histórico de `@State` para clases. Hace dos cosas: **crea el objeto una sola vez** (el inicializador recibe un `@autoclosure` que se ejecuta cuando el nodo entra en el grafo) y **se suscribe** a `objectWillChange`.

| Momento | `struct` | Nodo | Qué ocurre |
| :--- | :--- | :--- | :--- |
| Inicialización | `_modelo` guarda el *autoclosure* `Modelo()` | — | No se ha creado ningún objeto. |
| Inserción | El *autoclosure* se ejecuta **una vez** | Almacena `Modelo()` | Persistencia garantizada. |
| `body` | Lee del objeto | Suscrito a `objectWillChange` | Dependencia a nivel de objeto. |

Regla: inicialízalo en la declaración (`@StateObject private var modelo = Modelo()`). Inicializarlo desde `init` es posible (`_modelo = StateObject(wrappedValue: ...)`) con las mismas limitaciones que `@State` en 3.3.

---

## 3.10. *Legacy*: `@ObservedObject`

Observa un objeto creado y mantenido **por otro**. No gestiona ciclo de vida: guarda una referencia fuerte al objeto (no lo posee, pero tampoco es `weak`) y se suscribe a su `objectWillChange`. Si en una reconstrucción recibe otro objeto, cancela la suscripción anterior y se suscribe al nuevo, sin destruir el nodo.

Ese comportamiento dinámico es útil: un `Picker` que cambia `habitacionSeleccionada` puede hacer que el mismo nodo `Contador` observe sucesivamente el modelo de "Salón" y el de "Cocina". El equivalente moderno es una propiedad normal con `@Observable` (3.4), que hace exactamente lo mismo sin *wrapper*.

---

## 3.11. `Binding`: flujo bidireccional

Un `Binding<T>` es un par `get`/`set` que permite a un hijo leer y escribir un estado que pertenece a otro. No copia el valor; apunta a la fuente de verdad.

De un `@State` se obtiene con `$`:

```swift
struct Formulario: View {
    @State private var nombre = ""

    var body: some View {
        CampoNombre(nombre: $nombre)   // Binding<String>
    }
}

struct CampoNombre: View {
    @Binding var nombre: String
    var body: some View { TextField("Nombre", text: $nombre) }
}
```

### Bindings a medida

`Binding(get:set:)` construye uno manualmente. Es la herramienta para adaptar tipos (un `Binding<Int?>` a `Binding<Int>` con valor por defecto), para interceptar escrituras con validación, o para exponer una propiedad computada con lógica en el `setter`:

```swift
var porcentaje: Binding<Double> {
    Binding(
        get: { modelo.fraccion * 100 },
        set: { modelo.fraccion = $0 / 100 }
    )
}
```

Con `@Observable`, un `Binding` manual sobre una propiedad computada funciona bien siempre que el `setter` acabe escribiendo en una propiedad almacenada observable: la notificación la dispara esa escritura.

---

## 3.12. `Binding` y `@Observable`: `@Bindable`

Para obtener un `Binding` a una propiedad de un objeto `@Observable` que tu vista **no posee**, necesitas **`@Bindable`**. No es opcional y no está deprecado: es la única forma de que el compilador sintetice `$objeto.propiedad` sobre una referencia que no es `@State`.

```swift
@Observable @MainActor
final class ModeloUsuario {
    var nombre = "Ana"
}

struct EdicionUsuario: View {
    @Bindable var usuario: ModeloUsuario   // Recibido del padre

    var body: some View {
        TextField("Nombre", text: $usuario.nombre)
    }
}
```

Si la vista **sí** posee el objeto con `@State`, `$modelo.propiedad` funciona directamente, porque `@State` ya proyecta un `Binding`:

```swift
struct Formulario: View {
    @State private var modelo = ModeloUsuario()
    var body: some View {
        TextField("Nombre", text: $modelo.nombre)   // Sin @Bindable
    }
}
```

Y si recibes el objeto del entorno, `@Bindable` se declara localmente dentro del `body`:

```swift
struct Ajustes: View {
    @Environment(ModeloUsuario.self) private var usuario

    var body: some View {
        @Bindable var usuario = usuario
        TextField("Nombre", text: $usuario.nombre)
    }
}
```

| Cómo llega el objeto | Cómo obtienes `$` |
| :--- | :--- |
| Lo posee la vista (`@State`) | Directo: `$modelo.prop` |
| Parámetro del padre | `@Bindable var modelo: Modelo` |
| Entorno (`@Environment(Modelo.self)`) | `@Bindable var m = modelo` dentro del `body` |
| *Legacy* (`@ObservedObject` / `@StateObject`) | Directo: `$modelo.prop` |

---

## 3.13. Diagnóstico: por qué se ha ejecutado este `body`

### En consola: `_printChanges` y `_logChanges`

`Self._printChanges()` sigue existiendo y sigue siendo la forma más rápida de saber qué ha invalidado una vista. Se llama dentro del `body` con `let _ =`:

```swift
var body: some View {
    let _ = Self._printChanges()
    // ...
}
```

Imprime `@self` (cambió la `struct` entera: algún parámetro), `@identity` (nodo nuevo) o el nombre de la propiedad (`_valor`) que disparó la invalidación. Desde iOS 17.1 existe `Self._logChanges()`, que escribe a `os_log` en lugar de a la consola y se filtra en Console.app o en Instruments. Ambas son APIs con guion bajo: no las dejes en *release*.

### En Instruments: el instrumento SwiftUI

Para problemas que no se explican con una línea de consola, la herramienta es la plantilla **SwiftUI** de Instruments (Xcode 26+). Sus tres pistas (*Update Groups*, *Long View Body Updates* y *Cause & Effect Graph*) se explican en 8.2; para diagnosticar dependencias de estado, la que importa es la tercera: al seleccionar una actualización muestra el grafo desde el cambio de dato que la originó hasta cada `body` afectado. Es la respuesta a "¿por qué esta vista?": ves la propiedad exacta y la cadena de dependencias.

Xcode 27 añade el **Memory Graph** con el grafo de estado de SwiftUI, útil para localizar objetos `@Observable` retenidos por nodos que creías destruidos.

> **Pro Tip para Seniors.** El orden de diagnóstico correcto es: `_printChanges` para confirmar la propiedad culpable → *Cause & Effect Graph* para ver quién la escribe → *Long View Body Updates* para decidir si el problema es que el `body` se ejecuta de más o que es demasiado caro. Son problemas distintos con soluciones distintas: el primero se arregla en el modelo (granularidad), el segundo en la vista (mover el cálculo fuera del `body`).

---

## 3.14. Más allá de la vista: `Observations`

**Solo iOS 26+ (Swift 6.2).** Hasta aquí la observación la consumía SwiftUI. `Observations` es una `AsyncSequence` que emite cada vez que cambia lo que lee su *closure*, con semántica **transaccional**: todos los cambios síncronos hasta el siguiente `await` se agrupan en una emisión.

```swift
import Observation   // Observations vive aquí; SwiftUI no lo reexporta

let modelo = ModeloContador()

Task {
    for await valor in Observations({ modelo.valor }) {
        print("valor ahora es \(valor)")
    }
}
```

Es la pieza que faltaba para observar un `@Observable` desde un servicio, un `Task` o un test sin pasar por Combine. El capítulo 9 la usa para reemplazar la mayoría de los *pipelines* de `ObservableObject`.

---

## 3.15. Resumen

| Necesidad | Solución (iOS 18+) | *Legacy* (pre-iOS 17) |
| :--- | :--- | :--- |
| Estado local de valor | `@State private var` | — |
| Objeto que la vista posee | `@State private var modelo = Modelo()` con clase `@Observable @MainActor` | `@StateObject` |
| Objeto recibido de fuera | Propiedad normal (`let modelo: Modelo`) | `@ObservedObject` |
| `Binding` a objeto recibido | `@Bindable` | `$` directo sobre `@ObservedObject` |
| Objeto global / servicio | `.environment(modelo)` + `@Environment(Modelo.self)` (capítulo 5) | `@EnvironmentObject` |
| Observar fuera de SwiftUI | `Observations` (iOS 26+) | `objectWillChange` / `$prop` de Combine |

> **Regla de oro.** `@State` para todo lo que la vista posee, sea valor o clase. Propiedad normal para lo que recibe. `@Bindable` para escribir en lo que recibe. Y nunca un `let modelo = Modelo()` en una `struct` de vista.

> **Siguiente paso.** Busca en tu proyecto `let .* = .*ViewModel()` y `let .* = .*Model()` dentro de `struct`s que conformen a `View`. Cada resultado es estado que se está perdiendo o un objeto que se está recreando de más. Cámbialos a `@State` y compila con Xcode 27.
