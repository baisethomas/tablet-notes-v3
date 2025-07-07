import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    let totalPages = 3
    var onComplete: (() -> Void)?
    var onSkip: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") {
                    onSkip?()
                }
                .foregroundColor(.blue)
                .padding()
            }
            
            TabView(selection: $currentPage) {
                OnboardingPageView(
                    imageName: "mic.fill",
                    title: "Welcome to TabletNotes",
                    description: "Record sermons, take notes, and get AI-powered transcriptions and summaries to help you revisit and reflect on spiritual content.",
                    pageIndex: 0
                )
                .tag(0)
                
                OnboardingPageView(
                    imageName: "waveform.and.mic",
                    title: "Record & Take Notes",
                    description: "Tap 'Start Recording' to begin. Take notes in real-time during the sermon using the floating '+' button. Your audio is transcribed automatically.",
                    pageIndex: 1
                )
                .tag(1)
                
                OnboardingPageView(
                    imageName: "doc.text.magnifyingglass",
                    title: "AI Summaries & Review",
                    description: "Get AI-generated summaries with scripture references. Review past sermons anytime from your home screen. Export notes as PDF or text.",
                    pageIndex: 2
                )
                .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            // Custom page indicator
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentPage)
                }
            }
            .padding(.bottom, 20)
            
            // Navigation buttons
            HStack {
                if currentPage > 0 {
                    Button("Previous") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .foregroundColor(.blue)
                }
                
                Spacer()
                
                if currentPage < totalPages - 1 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        onComplete?()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(Color(UIColor.systemBackground))
    }
}

struct OnboardingPageView: View {
    let imageName: String
    let title: String
    let description: String
    let pageIndex: Int
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: imageName)
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(.bottom, 16)
            
            // Title
            Text(title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Description
            Text(description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
                .lineSpacing(4)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingView()
}