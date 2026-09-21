# Verificaciones antes de imprenta

Cada línea se cierra con un *commit* que enlaza la evidencia (captura de Instruments, salida de test, diff) o con un cambio en el texto del libro. Ninguna se cierra con "seguro que sí".

**Estado global:** el repositorio compila con Xcode 27 y sus tests pasan (evidencia en `docs/evidencia/`, generada sobre el árbol actual). Las verificaciones de abajo son las que exigen dispositivo, previews o Instruments, más las que dependen de comportamiento de APIs que no hemos podido confirmar. Las marcadas ☑ se cerraron durante la sesión de verificación; su resultado ya está incorporado al libro.

| # | Cap. | Qué verificar | Dónde | Estado |
| :--- | :--- | :--- | :--- | :--- |
| V1 | 2 | `-LogForEachSlowPath YES` en Xcode 27 con el `ForEach` de §2.7 | `PulseFeed/FeedList.swift`, esquema Debug | ☐ |
| V2 | 2 | Experimento `ForEach` por índice frente a `id` estable con inserción al principio | `PulseFeedTests/IdentidadTests.swift` | ☐ |
| V3 | 3 | Macro `@State`: ¿evita reevaluar el inicializador? | `PulseCheckoutTests/OwnershipTests.swift` | ☑ **Cerrada.** Con valor en línea: 1 construcción tras 5 reconstrucciones. Asignado en `init`: 6. El estado persiste en ambas. Incorporado a §3.3 y §3.4. |
| V4 | 3 | Las tres reglas de §3.3 producen los diagnósticos de TN3211 | `Tests/Compilacion/` (pendiente) | ☐ |
| V5 | 4 | `PriceRow` con `.accessibility5` y 320 pt en preview redimensionable | `PulseProduct/PriceRow.swift` | ☐ |
| V6 | 5 | `#expect(processExitsWith:)` sobre un `fatalError` de SwiftUI | `PulseCheckoutTests/FeatureFlagsTests.swift` | ⚠️ **Abierta (H9).** El exit test no contuvo el fallo: tumbó el bundle con SIGTRAP. Test deshabilitado con las dos causas en el archivo. El libro lo declara pendiente en §10.2. |
| V7 | 6 | Disponibilidad de `@Animatable` / `@AnimatableIgnored` con target iOS 18 | `PulseCart/AddToCartButton.swift` | ☐ |
| V8 | 6 | `.navigationTransition(.crossFade)` en `sheet` y `fullScreenCover` | pantalla de checkout | ☐ |
| V9 | 7 | Llamadas a `sizeThatFits` por pase antes/después de `Cache` (signpost) | `PulseSearch/FlowLayout.swift` | ☐ |
| V10 | 7 | `reorderable` / `reorderContainer` (iOS 27, *beta* al cierre) sobre `FlowLayout` | `PulseSearch/TagCloudView.swift` | ☐ |
| V11 | 8 | fps antes/después del caso §8.8 en dispositivo concreto, con captura de *hitches* | `cap8-bug` / `cap8-fix` | ☐ |
| V12 | 8 | `-warn-long-expression-type-checking=100` y el caso Charts de TN3211 con mínimo iOS 18 | `Package.swift` | ☐ |
| V13 | 9 | Nombre exacto de *Approachable Concurrency* en *build settings* de Xcode 27 y equivalencia con los flags de `Package.swift` | `Package.swift` | ☐ |
| V14 | 9 | El *stub* con latencia inversa reproduce el desorden de forma determinista | `PulseSearchTests/OrdenRespuestasTests.swift` | ☑ **Cerrada.** La primera versión fallaba en `bug` por prematuridad, no por desorden. Reescrita: `test-bug4.log` muestra `resultados = ["q-za"]`, es decir, la respuesta de la consulta anterior sobrescribe a la actual. Falla por la razón que §9.9 describe. |
| V15 | 9 | `async` en `defer` y `~Sendable` compilan en Swift 6.4 | `PulseCore/CatalogoService.swift` | ☐ |
| V16 | 10 | Versiones de ViewInspector y swift-snapshot-testing con Swift Testing en Xcode 27 | `Package.swift` | ☑ **Cerrada**, y fijadas a versión exacta tras H12: una versión posterior de ViewInspector se publicó con un manifiesto que no compila con Xcode 27. Versiones fijadas: ViewInspector 0.10.3, swift-snapshot-testing 1.19.5, swift-async-algorithms 1.1.5. |
| V17 | 10 | `distribuir` es `internal` y el test parametrizado compila | `PulseSearchTests/FlowLayoutTests.swift` | ☑ **Cerrada.** Pasa con los tres anchos. |
