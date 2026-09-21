import SwiftUI

// Libro: cap. 5, §5.6 — feature flags con valor por defecto explícito
@Observable @MainActor
public final class FeatureFlags {
    public var bannerPromo: Bool

    public init(bannerPromo: Bool) { self.bannerPromo = bannerPromo }

    public static let porDefecto = FeatureFlags(bannerPromo: false)
    public static var preview: FeatureFlags { FeatureFlags(bannerPromo: true) }
}

public extension EnvironmentValues {
    /// Libro: cap. 5, §5.3 — clave propia con @Entry
    @Entry var colorDeMarca: Color = .indigo
}
