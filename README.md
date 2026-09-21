# Pulse

App de referencia del libro *SwiftUI por dentro*. Cada capítulo tiene un caso de producción en esta app. El código de esos casos, y el de los listados que enseñan una API o un patrón, está aquí marcado con `// Libro: cap. N, §X`. Los fragmentos breves de ilustración (dos o tres líneas para mostrar el orden de unos modificadores, por ejemplo) no se duplican en el repositorio.

## Estado

**Compila y pasa sus tests con Xcode 27.** Evidencia en `docs/evidencia/`, generada sobre el árbol actual: `build6.log` (compilación), `test-fix6.log` y `test-bug7.log` (tests, con los seis casos discriminantes). Las dependencias están fijadas a versión exacta y `Package.resolved` está en el repositorio (H12), así que una compilación limpia debería reproducir esos mismos resultados.

Lo que **sí** está verificado: que el árbol construye, que la variante correcta pasa en verde y que la variante con bug (`-DPULSE_BUG`) falla exactamente en las suites esperadas.

Lo que **no** está verificado todavía: las comprobaciones que exigen dispositivo, previews o Instruments. Están en `docs/VERIFICACIONES.md` con su estado, y son la razón por la que algunas afirmaciones del libro dicen explícitamente "pendiente de verificación". Ningún test está deshabilitado.

## Estructura

| Módulo | Casos |
| :--- | :--- |
| `PulseCore` | `Producto`, `Articulo`, `FeatureFlags` (cap. 5), `CatalogoService` (cap. 9), signposts (cap. 8) |
| `PulseFeed` | `FeedRow` (cap. 2), `FeedList`/`FeedModel` (cap. 8), `EstadoFeed` |
| `PulseSearch` | `FlowLayout`/`TagCloudLayout` (cap. 7), `SearchModel` (cap. 9) |
| `PulseProduct` | `PriceRow` (cap. 4) |
| `PulseCart` | `Carrito`, `AddToCartButton` (cap. 6) |
| `PulseCheckout` | `CheckoutModel`, `CheckoutView` (cap. 3), `PromoBanner` (cap. 5) |
| `PulseLegacy` | `ObservableObject` y `.values` (cap. 3 §3.8–3.10, cap. 9 §9.4). Único módulo con `import Combine` |
| `PulseDebug` | Menú de depuración con los disparadores de cada bug |

La app (`PulseApp.xcodeproj`, no incluida aquí) es un *target* fino que compone estos paquetes y añade `PulseDebug` solo en Debug.

## Bug / fix

Cada caso tiene las dos variantes en el mismo archivo bajo `#if PULSE_BUG`. Las etiquetas `capN-bug` / `capN-fix` que cita el libro se crean con `scripts/tag-cases.sh`, que compila con y sin `-DPULSE_BUG` y etiqueta el *commit* correspondiente. Los tests marcados `.tags(.bug)` deben **fallar** con `PULSE_BUG` y pasar sin él.

```sh
swift test                              # variante fix: todo verde
swift test -Xswiftc -DPULSE_BUG         # variante bug: fallan los tests .bug
```

Los tests de vista (ViewInspector, snapshots) necesitan un *host* de tests en Xcode; en SwiftPM puro se saltan con `#if canImport(UIKit)`.

## Configuración de concurrencia

Fijada en `Package.swift`: Swift 6, aislamiento `MainActor` por defecto, `NonisolatedNonsendingByDefault` (Approachable Concurrency). Es la que asume el libro; no la cambies sin cambiar el libro.
