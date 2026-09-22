# Apéndice A: Índice de antipatrones

Extraído de los recuadros y los casos de los diez capítulos, más lo que la verificación en el repositorio añadió. Cada entrada: qué es, por qué parece bien, dónde se explica.

## Identidad y árbol (capítulo 2)

- **`if/else` entre dos vistas con estado propio.** Parece "dos variantes del mismo componente"; son dos nodos. §2.4, §2.9.
- **`applyIf` y cualquier modificador cuya presencia dependa de un booleano.** Parece un *helper* limpio; es una bifurcación de tipo escondida. §2.6.
- **`.id(UUID())` o `.id` como parche de actualización.** Parece que "fuerza el refresco"; destruye estado y animaciones. §2.6.
- **`ForEach(items.indices, id: \.self)` o `id: \.self` sobre tipos no únicos.** Parece inocuo hasta la primera inserción. §2.6, §2.11.
- **Estado de producto en una fila de contenedor perezoso.** Parece local; el *scroll* lo borra. §2.8, §2.9.
- **`ForEach` cuyos elementos producen un número variable de vistas.** Parece un `if` normal; activa el *slow path*. §2.7.

## Estado (capítulo 3)

- **`private let modelo = Modelo()` en una `struct` de vista.** Compila, funciona en el simulador, pierde estado cuando el padre se redibuja. §3.4, §3.7.
- **`@State` inicializado desde `init` esperando que siga al padre.** El `initialValue` se usa una vez. §3.3.
- **`@State` con valor en línea y asignación en `init`.** Con la macro de Xcode 27 la asignación se descarta en silencio. §3.3.
- **`@State` con el tipo declarado y asignación en el `init`, para un modelo caro.** El estado persiste, pero el objeto se construye y se descarta en cada reconstrucción de la vista: medido en el repositorio, seis construcciones para cinco actualizaciones del padre. La evaluación perezosa de la macro de Xcode 27 solo protege la forma con valor en línea. §3.3, §3.4.
- **Pasar el modelo raíz a cada fila y leer `raiz.items[i].campo`.** Cada fila depende de la colección entera. §3.6.
- **`$modelo.prop` sobre un `let` de un `@Observable` recibido, sin `@Bindable`.** No compila; y la "solución" de convertirlo en `@State` roba el ownership al padre. §3.12.
- **Esperar que reasignar un valor igual dispare una actualización, o al revés, no saber que Observation la suprime.** Un tipo sin `Equatable` notifica siempre aunque el contenido no cambie; uno con `Equatable` no notifica si el valor es igual. §3.5.

## Layout (capítulos 4 y 7)

- **`HStack { Text; Spacer(); Button }` para "uno a cada lado".** Sin `layoutPriority` ni `fixedSize`, el stack reparte a partes iguales entre cosas que no son iguales. §4.8.
- **`GeometryReader` como contenedor de contenido.** Ocupa todo lo propuesto y rompe el flujo; solo en `background`/`overlay`. §4.6, §7.4.
- **`UIScreen.main.bounds` para dimensionar.** Falso desde iPad; obvio desde iOS 27 con iPhone Duo y con iPhone redimensionable. §4.10.
- **`Circle()` esperando que rellene como `Ellipse()`.** Reporta un cuadrado. §4.4.
- **`.fixedSize()` para romper un bucle de layout.** Lo rompe matando la adaptabilidad; la solución es un `Layout`. §7.5.
- **`Cache` en un `Layout` "por si acaso".** Estado e invalidación a cambio de un ahorro no medido. §7.3, §7.9.
- **`replacingUnspecifiedDimensions()` sin `by:` en un layout que puede recibir `nil`.** Contenedor de 10 pt. §7.2.
- **Escribir en `@State` directamente desde `onPreferenceChange`.** Error de aislamiento en Swift 6. §7.5.
- **Leer un modelo `@Observable` o una `static` normal del módulo desde `sizeThatFits`/`placeSubviews`.** Estos métodos son `nonisolated` por el propio protocolo, incluso con aislamiento por defecto en `MainActor`; no pueden ver nada que viva en el `MainActor`. §7.2.

## Entorno (capítulo 5)

- **Clave de entorno para pasar un dato de padre a hijo directo.** Es un parámetro. §5.3.
- **`@Environment(Tipo?.self)` para leer opcionalmente.** No existe esa sobrecarga; la opcionalidad va en el tipo declarado de la propiedad (`@Environment(Tipo.self) var x: Tipo?`), no en el argumento. El error que produce no menciona la causa. §5.5.
- **`@Environment(Tipo.self)` sin garantizar la inyección en todos los *targets* y previews.** Crash. §5.5, §5.6.
- **Inyectar donde se lee, no donde se presenta.** Las *sheets* heredan del nodo que las presenta. §5.6.
- **`@Environment` en un *view model*.** Solo funciona en `View`; inyección por `init`. §5.7.
- **`actor` con `@Observable`.** No compila; dos capas. §5.7, §9.2.

## Animaciones (capítulo 6)

- **`if/else` dentro de un `label` con `withAnimation` fuera.** Anima una inserción y una eliminación, no una interpolación. §6.8.
- **`.transition` sin animación en el contenedor estable.** No se ejecuta. §6.6.
- **Animar `frame`/`padding`/`font` en muchas filas.** Invalida layout por *frame*; animar `scaleEffect`. §6.9.
- **Ignorar `accessibilityReduceMotion`.** Bug de accesibilidad, no preferencia. §6.9.

## Concurrencia (capítulos 8 y 9)

- **`DispatchQueue.main.async` en un modelo `@MainActor`.** Redundante y delata desconocimiento del actor actual. §9.2.
- **`Task { }` suelto disparado desde `onChange`.** Sin cancelación ni vida ligada a la vista. §9.9.
- **Escritura tras un `await` sin comprobar que la pregunta sigue vigente.** Respuestas fuera de orden. §9.9.
- **`do/catch` alrededor de `for await` sobre un publisher con `Failure == Never`.** Código muerto. §9.4.
- **`nonisolated async` como sinónimo de "en segundo plano".** Con *Approachable Concurrency* hereda el actor del llamador; `@concurrent` es la única forma explícita. §8.5, §9.1.
- **`AsyncStream` como bus multicast.** Un consumidor por secuencia. §9.5.
- **Marcar un tipo de datos solo como `Sendable` y esperar poder construirlo desde un `actor`.** Compila la declaración, falla la llamada: hace falta `nonisolated` además. §9.1, §9.2.
- **Un *logger*, formateador o constante `static` del módulo leído desde un `Layout`, un `@concurrent` o un `actor`.** El aislamiento por defecto los pone en el `MainActor` sin que lo escribas. §8.3, §9.1.

## Rendimiento (capítulo 8)

- **Optimizar sin decidir cuál de los tres problemas tienes.** `drawingGroup` sobre un problema de `sorted`. §8.1, §8.8.
- **Formatear, ordenar, filtrar o construir objetos en el `body`.** §8.4, §8.8.
- **`drawingGroup()` sobre texto o controles.** Rasteriza. §8.6.
- **Sombra o desenfoque por fila.** Candidato a investigar cuando la métrica de *hitches* señale composición. §8.6.
- **`body` de más de ~40 líneas o `if/else if` de muchas ramas en un builder.** Coste de compilación; extraer. §8.7.
- **Publicar en el modelo el *payload* del servidor tal cual.** Cualquier campo que el backend toque (contadores, marcas de tiempo, telemetría) invalida vistas que no lo muestran, aunque Observation ya suprima las reasignaciones idénticas. Publica la proyección que la interfaz consume, y compárala. §3.5, §8.2, §8.8.

## Testing (capítulo 10)

- **Muchos tests de vista.** Señal de lógica en las vistas. §10.1.
- **Snapshots sin propósito documentado ni tamaño fijo.** Se regeneran sin mirar. §10.5.
- **Tests de modelo como única cobertura de un bug de ownership.** El modelo funciona; la vista no. §10.6.
- **`var` local capturada y mutada dentro de una `Task`.** No compila bajo concurrencia estricta; el estado compartido de un test asíncrono necesita un tipo (una clase `@MainActor`). §10.2.
- **Afirmar sobre una cadena localizada completa.** Espacios duros y separadores de millares varían por locale, SO y versión; el informe de fallo muestra dos valores que parecen iguales. Afirma sobre la parte que controlas. §10.2.
- **Un test que pasa en las dos variantes del código (`bug` y `fix`).** No es un test frágil: está midiendo otra cosa. Todo test de "esto no ocurre" necesita un gemelo de "esto sí ocurre" que demuestre que el aparato de medida funciona. §10.3, §10.7.
- **Comparar identidades de objetos con la introspección de una vista sin hostearla (`ViewHosting`).** Cada inspección construye la `struct` de cero y lee el `@State` fuera de cualquier pase de render: el resultado no refleja persistencia real. §10.6.
- **Contar cuántas veces se ha construido un objeto para verificar ownership.** No distingue nada si la forma de escribir `@State` reconstruye y descarta el objeto en cada render (capítulo 3, §3.3). El criterio correcto es qué instancia usa la vista, no cuántas se han creado. §10.6.
- **Montar en un test un padre que no lee de verdad el dato que cambia.** El hijo se invalida pero la `struct` del padre no se reconstruye, y el bug que se quiere reproducir no aparece. §10.6.
