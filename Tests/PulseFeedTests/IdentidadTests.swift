import Testing
import SwiftUI
import PulseCore
@testable import PulseFeed
#if canImport(ViewInspector)
import ViewInspector
#endif

// Libro: cap. 2, §2.10–2.11 (V2). cap2-bug falla, cap2-fix pasa.
// (El tag `.bug` ya está declarado en FeedModelTests.swift, en este mismo módulo.)
@Suite("Identidad en ForEach", .tags(.bug), .serialized)
@MainActor
struct IdentidadTests {

    #if canImport(ViewInspector)
    @Test("Insertar al principio no mueve el estado de una fila a otra")
    func insertarNoMueveEstado() async throws {
        RegistroIdentidad.reiniciar()
        let modelo = ModeloIdentidad(items: ["A", "B", "C"].map { Articulo(titulo: $0) })
        ViewHosting.host(view: IdentidadDemo(modelo: modelo))
        defer { ViewHosting.expel() }
        try await Task.sleep(for: .milliseconds(80))

        // Control 1: antes de tocar nada, cada fila muestra el artículo para el que nació.
        #expect(RegistroIdentidad.desajustes.isEmpty, "desajustes antes de insertar: la sonda está mal montada")

        RegistroIdentidad.reiniciar()
        modelo.items.insert(Articulo(titulo: "Promoción"), at: 0)
        try await Task.sleep(for: .milliseconds(80))

        // Control 2: la inserción tiene que haber provocado evaluaciones; si no, "sin desajustes"
        // significaría "no se ha medido nada" (§10.3, §10.7).
        #expect(RegistroIdentidad.evaluaciones > 0, "la inserción no provocó ninguna evaluación de fila")

        // El caso: ninguna fila puede mostrar un artículo distinto del que la creó.
        #expect(RegistroIdentidad.desajustes.isEmpty,
                "filas reutilizadas para otro artículo (nació para → muestra): \(RegistroIdentidad.desajustes.map { "\($0.nacidaPara)→\($0.mostrado)" })")
    }
    #endif
}
