import SwiftUI

// MARK: - Sacred Vellum Design Tokens
// Light-only palette. Do not use adaptive/dark variants here.
// See ColorScheme.swift for the existing adaptive (dark-mode) color system.
extension Color {
    enum SV {
        // Surfaces — layered like paper on a desk
        static let surface            = Color(hex: "faf9f7") // base "paper"
        static let surfaceContainerLow = Color(hex: "f4f4f1") // secondary context
        static let surfaceContainerLowest = Color.white       // active cards / pop

        // Primary — Ink Blue
        static let primary    = Color(hex: "4f6174")
        static let primaryDim = Color(hex: "435568")

        // Text — near-black ink, never pure black
        static let onSurface = Color(hex: "303331")

        // Tertiary — soft purple, used for recording indicator
        static let tertiary = Color(hex: "5d5a84")

        // Error — reserved for destructive/critical actions
        static let error = Color(hex: "a83836")
    }
}
