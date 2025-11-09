import SwiftUI

// MARK: - Skeleton Loader Base Component
struct SkeletonView: View {
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.adaptiveSecondaryBackground,
                        Color.adaptiveSecondaryBackground.opacity(0.6),
                        Color.adaptiveSecondaryBackground
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .opacity(isAnimating ? 0.6 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

// MARK: - Skeleton Text Lines
struct SkeletonText: View {
    let lines: Int
    let lineHeight: CGFloat
    let spacing: CGFloat
    
    init(lines: Int = 1, lineHeight: CGFloat = 16, spacing: CGFloat = 8) {
        self.lines = lines
        self.lineHeight = lineHeight
        self.spacing = spacing
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<lines, id: \.self) { index in
                SkeletonView()
                    .frame(height: lineHeight)
                    .frame(maxWidth: index == lines - 1 ? 0.7 : 1.0)
            }
        }
    }
}

// MARK: - Skeleton Sermon Card
struct SkeletonSermonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and date row
            HStack(alignment: .top) {
                SkeletonView()
                    .frame(height: 20)
                    .frame(maxWidth: 0.6)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    SkeletonView()
                        .frame(width: 80, height: 12)
                    SkeletonView()
                        .frame(width: 20, height: 12)
                }
            }
            
            // Service type badge
            SkeletonView()
                .frame(width: 100, height: 24)
                .cornerRadius(8)
            
            // Key points preview
            VStack(alignment: .leading, spacing: 6) {
                SkeletonView()
                    .frame(width: 80, height: 12)
                SkeletonText(lines: 3, lineHeight: 14, spacing: 4)
            }
            
            // Status badges
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    SkeletonView()
                        .frame(width: 60, height: 20)
                        .cornerRadius(6)
                    SkeletonView()
                        .frame(width: 60, height: 20)
                        .cornerRadius(6)
                }
            }
        }
        .padding(16)
        .background(Color.sermonCardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.adaptiveBorder, lineWidth: 1)
        )
    }
}

// MARK: - Skeleton Note Card
struct SkeletonNoteCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SkeletonView()
                    .frame(width: 60, height: 20)
                    .cornerRadius(4)
                
                Spacer()
                
                HStack(spacing: 8) {
                    SkeletonView()
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                    SkeletonView()
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                }
            }
            
            SkeletonText(lines: 3, lineHeight: 16, spacing: 6)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Enhanced Progress Indicator
struct EnhancedProgressView: View {
    let title: String?
    let subtitle: String?
    let progress: Double?
    let style: ProgressStyle
    
    enum ProgressStyle {
        case circular
        case linear
        case pulsing
    }
    
    init(
        title: String? = nil,
        subtitle: String? = nil,
        progress: Double? = nil,
        style: ProgressStyle = .circular
    ) {
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.style = style
    }
    
    var body: some View {
        VStack(spacing: 16) {
            switch style {
            case .circular:
                CircularProgressIndicator(progress: progress)
            case .linear:
                LinearProgressIndicator(progress: progress ?? 0)
            case .pulsing:
                PulsingProgressIndicator()
            }
            
            if let title = title {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.adaptivePrimaryText)
            }
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.adaptiveSecondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Circular Progress Indicator
struct CircularProgressIndicator: View {
    let progress: Double?
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack(alignment: .center) {
            // Background circle
            Circle()
                .stroke(Color.adaptiveTertiaryText.opacity(0.2), lineWidth: 4)
                .frame(width: 60, height: 60)
            
            if let progress = progress {
                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.adaptiveAccent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)
            } else {
                // Indeterminate spinner
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        Color.adaptiveAccent,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(rotation))
                    .animation(
                        Animation.linear(duration: 1.0).repeatForever(autoreverses: false),
                        value: rotation
                    )
            }
        }
        .frame(width: 60, height: 60)
        .onAppear {
            if progress == nil {
                rotation = 360
            }
        }
    }
}

// MARK: - Linear Progress Indicator
struct LinearProgressIndicator: View {
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.adaptiveTertiaryText.opacity(0.2))
                    .frame(height: 8)
                
                // Progress bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.adaptiveAccent,
                                Color.adaptiveAccent.opacity(0.8)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(progress), height: 8)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 8)
    }
}

// MARK: - Pulsing Progress Indicator
struct PulsingProgressIndicator: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.adaptiveAccent.opacity(0.3))
                .frame(width: 60, height: 60)
                .scaleEffect(scale)
                .opacity(opacity)
            
            Circle()
                .fill(Color.adaptiveAccent)
                .frame(width: 30, height: 30)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: false)
            ) {
                scale = 1.5
                opacity = 0.0
            }
        }
    }
}

// MARK: - Loading State View with Skeleton
struct LoadingStateView: View {
    let title: String
    let subtitle: String?
    let style: LoadingStyle
    
    enum LoadingStyle {
        case progress
        case skeletonList
        case skeletonCards(count: Int)
    }
    
    init(
        title: String,
        subtitle: String? = nil,
        style: LoadingStyle = .progress
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
    }
    
    var body: some View {
        VStack(spacing: 24) {
            switch style {
            case .progress:
                EnhancedProgressView(
                    title: title,
                    subtitle: subtitle,
                    style: .circular
                )
                
            case .skeletonList:
                VStack(spacing: 16) {
                    EnhancedProgressView(
                        title: title,
                        subtitle: subtitle,
                        style: .circular
                    )
                    .padding(.top, 40)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<5, id: \.self) { _ in
                                SkeletonNoteCard()
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                }
                
            case .skeletonCards(let count):
                VStack(spacing: 16) {
                    EnhancedProgressView(
                        title: title,
                        subtitle: subtitle,
                        style: .circular
                    )
                    .padding(.top, 20)
                    
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(0..<count, id: \.self) { _ in
                                SkeletonSermonCard()
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.adaptiveBackground)
    }
}

// MARK: - Shimmer Effect Modifier
struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.3),
                            Color.clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                }
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5).repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Progress Bar with Percentage
struct ProgressBarView: View {
    let progress: Double
    let title: String?
    let showPercentage: Bool
    
    init(
        progress: Double,
        title: String? = nil,
        showPercentage: Bool = true
    ) {
        self.progress = min(max(progress, 0), 1)
        self.title = title
        self.showPercentage = showPercentage
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = title {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.adaptivePrimaryText)
                    
                    Spacer()
                    
                    if showPercentage {
                        Text("\(Int(progress * 100))%")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.adaptiveAccent)
                    }
                }
            }
            
            LinearProgressIndicator(progress: progress)
        }
    }
}

// MARK: - Loading Overlay
struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String?
    
    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .blur(radius: isLoading ? 2 : 0)
            
            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    EnhancedProgressView(
                        title: message,
                        style: .circular
                    )
                    .padding(24)
                    .background(Color.adaptiveCardBackground)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
            }
        }
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, message: message))
    }
}

