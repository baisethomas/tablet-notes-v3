import SwiftUI

struct SplashView: View {
    @State private var isLoading = true
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Adaptive background gradient for dark/light mode
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark ? [Color.navyDarkPrimary, Color.navyDarkSecondary] : [Color.adaptiveBackground, Color.adaptiveSecondaryBackground]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // App Logo
                VStack(spacing: 20) {
                    ZStack {
                        // Enhanced logo background (adaptive)
                        Circle()
                            .fill(Color.adaptiveCardBackground)
                            .frame(width: 140, height: 140)
                            .shadow(color: .black.opacity(0.1), radius: 15, x: 0, y: 8)
                        
                        Circle()
                            .fill(Color.adaptiveAccent.opacity(0.05))
                            .frame(width: 130, height: 130)
                        
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                    .frame(maxWidth: 140, maxHeight: 140) // Prevent stretching
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    
                    // App Name
                    Text("Tablet Notes")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.adaptivePrimaryText)
                        .opacity(textOpacity)
                    
                    // Tagline
                    Text("AI-Powered Sermon Transcription")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.adaptiveSecondaryText)
                        .opacity(textOpacity)
                        .multilineTextAlignment(.center)
                }
                
                Spacer()
                
                // Loading indicator
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .adaptiveAccent))
                        .scaleEffect(1.2)
                        .opacity(textOpacity)
                    
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.adaptiveSecondaryText)
                        .opacity(textOpacity)
                }
                .padding(.bottom, 50)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Logo entrance animation
        withAnimation(.easeOut(duration: 0.8)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        // Text and loading indicator fade in
        withAnimation(.easeIn(duration: 0.6).delay(0.3)) {
            textOpacity = 1.0
        }
        
        // Complete splash screen after total duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) {
                onComplete()
            }
        }
    }
}

// MARK: - Alternative Minimal Splash View
struct MinimalSplashView: View {
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0.0
    
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.navyDarkPrimary : Color.adaptiveBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                ZStack {
                    // Simple background for logo (adaptive)
                    RoundedRectangle(cornerRadius: 25)
                        .fill(Color.adaptiveCardBackground)
                        .frame(width: 110, height: 110)
                    
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 90, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .frame(maxWidth: 110, maxHeight: 110) // Prevent stretching
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                Text("TabletNotes")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundColor(.adaptivePrimaryText)
                    .opacity(logoOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onComplete()
            }
        }
    }
}

// MARK: - Brand-Focused Splash View (Smaller Logo)
struct BrandSplashView: View {
    @State private var logoOffset: CGFloat = -50
    @State private var logoOpacity: Double = 0.0
    @State private var textOffset: CGFloat = 30
    @State private var textOpacity: Double = 0.0
    @State private var backgroundOpacity: Double = 0.0
    
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            // Adaptive radial gradient for dark/light mode
            RadialGradient(
                gradient: Gradient(colors: colorScheme == .dark ? [Color.navyDarkPrimary.opacity(0.9), Color.navyDarkSecondary.opacity(0.7), Color.navyDarkPrimary] : [Color.adaptiveBackground, Color.adaptiveSecondaryBackground, Color.adaptiveBackground]),
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .opacity(backgroundOpacity)
            .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Logo with slide-in animation - Much smaller and proportional
                ZStack {
                    // Subtle background circle if image doesn't load
                    Circle()
                        .fill(Color.adaptiveCardBackground)
                        .frame(width: 70, height: 70)
                        .overlay(
                            Circle()
                                .stroke(Color.adaptiveAccent.opacity(0.2), lineWidth: 1)
                        )
                    
                    // App Logo - Reduced from 100x100 to 60x60
                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(maxWidth: 70, maxHeight: 70) // Prevent stretching
                .offset(y: logoOffset)
                .opacity(logoOpacity)
                .shadow(color: .adaptiveAccent.opacity(0.2), radius: 8, x: 0, y: 4)
                
                // Brand text
                VStack(spacing: 8) {
                    Text("TabletNotes")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.adaptivePrimaryText)
                        .offset(y: textOffset)
                        .opacity(textOpacity)
                    
                    Rectangle()
                        .fill(Color.adaptiveAccent)
                        .frame(width: 40, height: 2)
                        .cornerRadius(1)
                        .opacity(textOpacity)
                    
                    Text("Record • Transcribe • Summarize")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.adaptiveSecondaryText)
                        .tracking(1)
                        .offset(y: textOffset)
                        .opacity(textOpacity)
                }
            }
        }
        .onAppear {
            startBrandAnimations()
        }
    }
    
    private func startBrandAnimations() {
        // Background fade in
        withAnimation(.easeIn(duration: 0.5)) {
            backgroundOpacity = 1.0
        }
        
        // Logo slide in from top
        withAnimation(.spring(response: 0.8, dampingFraction: 0.7).delay(0.2)) {
            logoOffset = 0
            logoOpacity = 1.0
        }
        
        // Text slide up from bottom
        withAnimation(.easeOut(duration: 0.7).delay(0.5)) {
            textOffset = 0
            textOpacity = 1.0
        }
        
        // Complete after animations
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            onComplete()
        }
    }
}

// MARK: - Clean Spinner-Only Splash View
struct SpinnerSplashView: View {
    @State private var spinnerOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    
    let onComplete: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Clean background
            (colorScheme == .dark ? Color.navyDarkPrimary : Color.adaptiveBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // App name only
                Text("TabletNotes")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.adaptivePrimaryText)
                    .opacity(textOpacity)
                
                // Clean loading spinner
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .adaptiveAccent))
                    .scaleEffect(1.3)
                    .opacity(spinnerOpacity)
                
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundColor(.adaptiveSecondaryText)
                    .opacity(textOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) {
                textOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.6).delay(0.2)) {
                spinnerOpacity = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                onComplete()
            }
        }
    }
}

#Preview("Default Splash") {
    SplashView(onComplete: {})
}

#Preview("Minimal Splash") {
    MinimalSplashView(onComplete: {})
}

#Preview("Brand Splash") {
    BrandSplashView(onComplete: {})
}

#Preview("Spinner Splash") {
    SpinnerSplashView(onComplete: {})
}

// Debug version to check logo loading
struct DebugSplashView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Logo Debug Test")
                .font(.title)
            
            // Test different ways to load the logo
            VStack(spacing: 10) {
                Text("Method 1: Image(\"AppLogo\")")
                    .font(.caption)
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .border(Color.red, width: 1)
                
                Text("Method 2: UIImage check")
                    .font(.caption)
                if let logoImage = UIImage(named: "AppLogo") {
                    Image(uiImage: logoImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .border(Color.green, width: 1)
                    Text("✅ Logo loaded successfully")
                        .foregroundColor(.green)
                } else {
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 80, height: 80)
                        .overlay(Text("❌ Logo not found"))
                    Text("❌ Logo failed to load")
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
    }
}

#Preview("Debug Logo") {
    DebugSplashView()
}
