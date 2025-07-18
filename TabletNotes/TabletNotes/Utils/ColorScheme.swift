import SwiftUI

// MARK: - Custom Color Scheme
extension Color {
    
    // MARK: - Navy Dark Theme Colors
    static let navyDarkPrimary = Color(red: 0.07, green: 0.11, blue: 0.18)      // #121C2D - Deep navy
    static let navyDarkSecondary = Color(red: 0.10, green: 0.15, blue: 0.24)    // #1A2639 - Medium navy
    static let navyDarkTertiary = Color(red: 0.13, green: 0.20, blue: 0.31)     // #21334F - Lighter navy
    static let navyDarkQuaternary = Color(red: 0.16, green: 0.24, blue: 0.36)   // #28405C - Card background
    
    // MARK: - Accent Colors
    static let spiritualBlue = Color(red: 0.26, green: 0.54, blue: 0.96)        // #428AF6 - Primary blue
    static let spiritualTeal = Color(red: 0.20, green: 0.78, blue: 0.69)        // #33C7B0 - Teal accent
    static let spiritualGold = Color(red: 0.95, green: 0.77, blue: 0.28)        // #F2C445 - Gold accent
    
    // MARK: - Status Colors
    static let recordingRed = Color(red: 0.92, green: 0.34, blue: 0.34)         // #EA5757 - Recording red
    static let successGreen = Color(red: 0.20, green: 0.78, blue: 0.49)         // #33C77D - Success green
    static let warningOrange = Color(red: 0.95, green: 0.61, blue: 0.07)        // #F29C12 - Warning orange
    
    // MARK: - Text Colors
    static let navyTextPrimary = Color(red: 0.95, green: 0.96, blue: 0.98)      // #F2F4F8 - Primary text
    static let navyTextSecondary = Color(red: 0.70, green: 0.76, blue: 0.85)    // #B2C2D8 - Secondary text
    static let navyTextTertiary = Color(red: 0.50, green: 0.58, blue: 0.70)     // #8094B3 - Tertiary text
    
    // MARK: - Surface Colors
    static let navyCardBackground = Color(red: 0.14, green: 0.22, blue: 0.33)   // #24384D - Card background
    static let navyInputBackground = Color(red: 0.11, green: 0.17, blue: 0.26)  // #1C2B42 - Input background
    static let navyBorder = Color(red: 0.20, green: 0.29, blue: 0.42)           // #334A6B - Border color
    
    // MARK: - Adaptive Colors
    static var adaptiveBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyDarkPrimary) : UIColor.systemBackground
        })
    }
    
    static var adaptiveSecondaryBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyDarkSecondary) : UIColor.secondarySystemBackground
        })
    }
    
    static var adaptiveTertiaryBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyDarkTertiary) : UIColor.tertiarySystemBackground
        })
    }
    
    static var adaptiveCardBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyCardBackground) : UIColor.systemBackground
        })
    }
    
    static var adaptiveInputBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyInputBackground) : UIColor.systemGray6
        })
    }
    
    static var adaptivePrimaryText: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyTextPrimary) : UIColor.label
        })
    }
    
    static var adaptiveSecondaryText: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyTextSecondary) : UIColor.secondaryLabel
        })
    }
    
    static var adaptiveTertiaryText: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyTextTertiary) : UIColor.tertiaryLabel
        })
    }
    
    static var adaptiveBorder: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyBorder) : UIColor.separator
        })
    }
    
    static var adaptiveAccent: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(spiritualBlue) : UIColor.systemBlue
        })
    }
    
    // MARK: - Semantic Colors
    static var recordingBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyDarkSecondary) : UIColor.systemBackground
        })
    }
    
    static var transcriptionBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyDarkTertiary) : UIColor.systemGray6
        })
    }
    
    static var sermonCardBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyCardBackground) : UIColor.systemBackground
        })
    }
    
    static var navigationBackground: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? 
                UIColor(navyDarkPrimary) : UIColor.systemBackground
        })
    }
}

// MARK: - Color Scheme Environment
struct ColorSchemeEnvironment: EnvironmentKey {
    static let defaultValue = ColorScheme.light
}

extension EnvironmentValues {
    var customColorScheme: ColorScheme {
        get { self[ColorSchemeEnvironment.self] }
        set { self[ColorSchemeEnvironment.self] = newValue }
    }
}

// MARK: - Color Scheme Modifier
struct CustomColorSchemeModifier: ViewModifier {
    let scheme: ColorScheme?
    
    func body(content: Content) -> some View {
        content
            .environment(\.customColorScheme, scheme ?? .light)
            .preferredColorScheme(scheme)
    }
}

extension View {
    func customColorScheme(_ scheme: ColorScheme?) -> some View {
        modifier(CustomColorSchemeModifier(scheme: scheme))
    }
}

// MARK: - Gradient Definitions
extension LinearGradient {
    static let navyGradient = LinearGradient(
        gradient: Gradient(colors: [Color.navyDarkPrimary, Color.navyDarkSecondary]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let spiritualGradient = LinearGradient(
        gradient: Gradient(colors: [Color.spiritualBlue, Color.spiritualTeal]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let recordingGradient = LinearGradient(
        gradient: Gradient(colors: [Color.recordingRed.opacity(0.8), Color.recordingRed]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Shadow Definitions
extension View {
    func navyCardShadow() -> some View {
        self.shadow(
            color: Color.black.opacity(0.2),
            radius: 8,
            x: 0,
            y: 4
        )
    }
    
    func navyElevatedShadow() -> some View {
        self.shadow(
            color: Color.black.opacity(0.3),
            radius: 12,
            x: 0,
            y: 6
        )
    }
    
    func navyButtonShadow() -> some View {
        self.shadow(
            color: Color.spiritualBlue.opacity(0.3),
            radius: 8,
            x: 0,
            y: 4
        )
    }
}