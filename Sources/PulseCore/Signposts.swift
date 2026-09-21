import os

// Libro: cap. 8, §8.3
//
// `nonisolated` es obligatorio: con Default Actor Isolation = MainActor, las propiedades estáticas
// del módulo quedan aisladas al MainActor, y estos signposters se leen desde contextos que NO lo están
// (los métodos del protocolo `Layout`, cap. 7, y las funciones `@concurrent`, cap. 8 §8.5).
// `OSSignposter` es `Sendable`, así que compartirlo entre contextos es seguro.
nonisolated public enum Signposts {
    public static let feed = OSSignposter(subsystem: "app.pulse", category: "Feed")
    public static let layout = OSSignposter(subsystem: "app.pulse", category: "Layout")
}
