> **SwiftUI por dentro: identidad, layout y concurrencia para ingenieros senior**
> iOS 27 · Swift 6.4 · 2026

# Capítulo 1: Introducción

> **Nota de versión.** Este capítulo está escrito con Xcode 27, Swift 6.4 y el SDK de iOS 27. El *deployment target* mínimo es iOS 18, con *Strict Concurrency* completo, aislamiento `@MainActor` por defecto y *Approachable Concurrency* activado. Las APIs que exigen iOS 26 o iOS 27 aparecen en recuadros marcados; el resto funciona en toda la ventana iOS 18–27.

## 1.1. El cambio de paradigma que todavía no hemos digerido

SwiftUI llegó en 2019 con iOS 13 y cambió la pregunta que te haces al escribir interfaz. En UIKit te preguntabas *qué hacer* cuando algo cambia: recargar la tabla, actualizar la etiqueta, animar la restricción. En SwiftUI te preguntas *qué debe verse* dado un estado, y el *framework* calcula el resto.

Siete años después, es fácil llevar tiempo escribiendo SwiftUI y seguir razonando sobre él con un modelo mental imperativo disfrazado. Se nota en los síntomas, y son los que traen a la mayoría de la gente a un libro como este: `@State` que se resetea sin motivo, `body` que se ejecuta cientos de veces por segundo, `GeometryReader` anidados para resolver un layout que un `frame` resolvería, y `DispatchQueue.main.async` sobreviviendo en *view models* marcados con `@MainActor`.

| Aspecto | UIKit (imperativo) | SwiftUI (declarativo) |
| :--- | :--- | :--- |
| **Fuente de la verdad** | Dispersa: vistas y controladores sincronizados a mano | Única: el estado dicta la vista |
| **Actualización** | `setNeedsLayout`, `reloadData` | Reconciliación automática sobre el grafo de atributos |
| **Identidad de una vista** | La instancia del objeto | La estructura del árbol (posición y tipo) o un `.id` / `ForEach` explícito; capítulo 2 |
| **Concurrencia** | Hilos y colas gestionados a mano | Aislamiento por actores; UI en `@MainActor` |
| **Flujo de datos** | Delegados, KVO, `NotificationCenter` | `Binding`, entorno y el *framework* Observation |
| **Observación de modelos** | KVO / Combine | Macro `@Observable`, granular por propiedad |

Cada fila de esa tabla es un capítulo de este libro.

## 1.2. Por qué este libro

La documentación de Apple ha mejorado mucho, y hay material abundante sobre fundamentos. Lo que cuesta más encontrar es la capa intermedia: **cómo funciona SwiftUI por dentro** con el detalle suficiente para diagnosticar un problema que no aparece en ningún tutorial. Por qué esa vista pierde el estado. Por qué ese `List` da tirones. Por qué ese `Layout` propio mide sesenta etiquetas una y otra vez.

Este libro no te enseña SwiftUI. Asume que llevas años con él y que has llegado al punto en que las respuestas de Stack Overflow ya no te bastan. El objetivo es que salgas con un **modelo mental preciso** de tres cosas: cómo se construye y reconcilia el árbol de vistas, cómo fluye el estado a través de él, y cómo todo eso convive con la concurrencia estricta de Swift 6.

## 1.3. El stack ha cambiado; los principios no

Si tu última puesta al día seria fue con iOS 17, cuando llegó `@Observable`, hay cuatro cambios que sí alteran cómo se escribe SwiftUI en 2026 y que este libro integra en lugar de tratar como apéndice:

- **El modelo de concurrencia de Swift 6.2+.** Aislamiento `@MainActor` por defecto en el módulo, funciones `nonisolated async` que heredan el actor del llamador y `@concurrent` para pedir explícitamente un hilo de fondo. "Todo es `MainActor` salvo que yo diga lo contrario" es ahora el modelo mental correcto; se desarrolla en los capítulos 3, 8 y 9.
- **`@State` como macro (Xcode 27, con *back-deploy*).** Las clases almacenadas en `@State` se inicializan de forma perezosa y SwiftUI evita reevaluar su inicializador. Se acaba el debate sobre el coste de `@State private var modelo = Modelo()` (capítulo 3).
- **`ContentBuilder` (Xcode 27).** El *result builder* que hay detrás de `ViewBuilder` cambia por dentro y mejora el *type-checking*. No cambia lo que escribes; cambia lo que el compilador construye, y eso afecta a cómo conviene explicar el árbol de vistas (capítulo 2).
- **`Observations` (iOS 26).** La secuencia asíncrona sobre un `@Observable` que jubila la mayoría de los usos de Combine para observar modelos fuera de SwiftUI (capítulos 3 y 9).

No vamos a estudiar estas APIs como novedades. Vamos a estudiar qué problemas de ingeniería resuelven mejor que lo que teníamos. Cuando una API de iOS 26 o iOS 27 aparezca en el libro, será porque en ese punto es la mejor respuesta a un problema real, y estará marcada como tal.

## 1.4. Recorrido del libro

El orden no es arbitrario: cada capítulo asume el modelo mental del anterior.

| Cap. | Tema | La pregunta que responde |
| :--- | :--- | :--- |
| 2 | Árboles de vistas y grafo de atributos | ¿Qué es "la misma vista" para SwiftUI y cuándo deja de serlo? |
| 3 | Estado, ownership y `Binding` | ¿Dónde vive el estado y por qué se pierde? |
| 4 | Layout | ¿Quién decide el tamaño de cada cosa? |
| 5 | Entorno | ¿Cómo inyecto configuración y servicios sin acoplar? |
| 6 | Animaciones | ¿Qué se interpola, qué transiciona y qué hace saltar? |
| 7 | Layout avanzado | ¿Cuándo un `Layout` propio y cuándo `GeometryReader`? |
| 8 | Rendimiento | ¿Por qué va lenta y cómo lo mido? |
| 9 | Concurrencia y datos reactivos | ¿Cómo llegan los datos a la vista sin *data races*? |
| 10 | Testing | ¿Cómo demuestro que no lo rompo al arreglarlo? |

Del capítulo 2 en adelante, cada uno termina con una **Regla de oro** y un **Siguiente paso**: lo mínimo que puedes aplicar a tu código el lunes.

Todo el código del libro está en el repositorio de ejemplos (`Pulse`), compila con Xcode 27 y tiene tests en Swift Testing. Conviene que sepas qué cubren esos tests y qué no. Los casos de *code review* existen en el repositorio en dos variantes, con y sin el bug, para que puedas ejecutar las dos y comparar. Seis de ellos —los de los capítulos 2, 3, 5, 7, 8 y 9— van además con un test que **falla en la variante con el bug y pasa en la corregida**, que es el criterio que nos hemos impuesto y hacia el que van los demás. Lo que los tests no cubren, porque exige dispositivo e instrumentación, son las mediciones de rendimiento: donde el libro da una cifra dice dónde se midió, y donde no la hemos medido todavía, lo dice también.

## 1.5. Cómo leer este libro

Léelo con Xcode abierto. Cada vez que el texto diga "esto pierde el estado" o "esto se mide dos veces", reprodúcelo. La teoría de este libro se olvida en una semana; lo que hayas visto en Instruments con tus propios ojos, no.

> **Regla de oro.** Si no sabes explicar por qué el `body` de una vista se ha vuelto a ejecutar, todavía no controlas SwiftUI. Este libro existe para que siempre lo sepas. (Y si la palabra que te venía a la cabeza era "redibujar": ejecutar un `body`, reconciliar el árbol, recalcular el layout y dibujar en pantalla son cuatro cosas distintas. Separarlas es buena parte de lo que viene a continuación.)

> **Siguiente paso.** Abre los *build settings* de tu proyecto y mira cuatro ajustes: *Swift Language Version*, *Strict Concurrency Checking*, *Approachable Concurrency* y *Default Actor Isolation*. El libro asume Swift 6, `Complete`, `YES` y `MainActor`. No des por hecho que ya los tienes: un proyecto recién creado en Xcode 27 trae los dos últimos activados, pero viene con **Swift 5** y comprobación **`Minimal`**, así que compila sin quejarse de casi nada de lo que los capítulos 8 y 9 enseñan a detectar. Cambiar esos dos ajustes es el primer trabajo, y probablemente te devuelva una lista de errores de aislamiento: el capítulo 9 explica cómo leerlos.
