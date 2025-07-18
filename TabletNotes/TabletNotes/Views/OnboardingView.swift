import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    let totalPages = 4 // Increased to 4 pages
    @State private var isRecordingDemo = false
    @State private var showPermissionRequest = false
    @State private var selectedServiceTypes: Set<String> = []
    @State private var speakerName = ""
    
    var onComplete: (() -> Void)?
    var onSkip: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress bar at top
            HStack {
                ForEach(0..<totalPages, id: \.self) { index in
                    Rectangle()
                        .fill(index <= currentPage ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(height: 3)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            HStack {
                Spacer()
                Button("Skip") {
                    onSkip?()
                }
                .foregroundColor(.accentColor)
                .padding()
            }
            
            TabView(selection: $currentPage) {
                // Page 1: Welcome with animated logo
                WelcomePageView()
                .tag(0)
                
                // Page 2: Interactive recording demo
                RecordingDemoPageView(isRecordingDemo: $isRecordingDemo)
                .tag(1)
                
                // Page 3: AI Features showcase
                AIFeaturesPageView()
                    .tag(2)
                
                // Page 4: Personalization setup
                PersonalizationPageView(
                    selectedServiceTypes: $selectedServiceTypes,
                    speakerName: $speakerName
                )
                .tag(3)
            }
            .tabViewStyle(.automatic)
            
            // Custom page indicator with progress
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(currentPage == index ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(currentPage == index ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
                }
            }
            .padding(.bottom, 20)
            
            // Navigation buttons
            HStack {
                if currentPage > 0 {
                    Button("Previous") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage -= 1
                        }
                    }
                    .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                if currentPage < totalPages - 1 {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .background(.background)
    }
    
    private func completeOnboarding() {
        // Save user preferences
        UserDefaults.standard.set(Array(selectedServiceTypes), forKey: "preferredServiceTypes")
        UserDefaults.standard.set(speakerName, forKey: "defaultSpeakerName")
        
        onComplete?()
    }
}

// MARK: - Welcome Page
struct WelcomePageView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0
    @State private var textOffset: CGFloat = 20
    @State private var textOpacity: Double = 0.0
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animated app logo
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(logoScale)
                    
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }
                
                VStack(spacing: 12) {
                    Text("Welcome to TabletNotes")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .offset(y: textOffset)
                        .opacity(textOpacity)
                    
                    Text("Transform your sermon experience with AI-powered transcription and smart summaries")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .offset(y: textOffset)
                        .opacity(textOpacity)
                }
            }
            
            Spacer()
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                textOffset = 0
                textOpacity = 1.0
            }
        }
    }
}

// MARK: - Recording Demo Page
struct RecordingDemoPageView: View {
    @Binding var isRecordingDemo: Bool
    @State private var waveformHeights: [CGFloat] = Array(repeating: 4, count: 8)
    @State private var noteText = ""
    @State private var showNoteInput = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Text("Record & Take Notes")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                // Interactive recording demo
                VStack(spacing: 20) {
                    // Animated waveform
                    HStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: 6, height: waveformHeights[index])
                                .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(index) * 0.1), value: isRecordingDemo)
                        }
                    }
                    .frame(height: 40)
                    
                    // Demo recording button
                    Button(action: {
                        isRecordingDemo.toggle()
                        animateWaveform()
                        
                        if isRecordingDemo {
                            showNoteInput = true
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isRecordingDemo ? Color.red : Color.accentColor)
                                .frame(width: 80, height: 80)
                                .scaleEffect(isRecordingDemo ? 1.1 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: isRecordingDemo)
                            
                            if isRecordingDemo {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Text(isRecordingDemo ? "Recording... Tap to stop" : "Tap to try recording")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Demo note input
                    if showNoteInput {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a note:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("Key point from the sermon...", text: $noteText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                Text("Record sermons while taking notes in real-time. Everything is transcribed automatically.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
    
    private func animateWaveform() {
        if isRecordingDemo {
            for index in 0..<waveformHeights.count {
                waveformHeights[index] = CGFloat.random(in: 8...32)
            }
        } else {
            waveformHeights = Array(repeating: 4, count: 8)
        }
    }
}

// MARK: - AI Features Page
struct AIFeaturesPageView: View {
    @State private var showTranscript = false
    @State private var showSummary = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Text("AI-Powered Insights")
                    .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    // Transcript preview
                    Button(action: { showTranscript.toggle() }) {
                        HStack(spacing: 12) {
                            Image(systemName: "text.bubble.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Automatic Transcription")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Every word captured accurately")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    if showTranscript {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sample Transcript:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("\"Today we're exploring the parable of the lost sheep. Jesus tells us about a shepherd who leaves ninety-nine sheep to find the one that's lost...\"")
                                .font(.subheadline)
                                .padding()
                                .background(.background)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    
                    // Summary preview
                    Button(action: { showSummary.toggle() }) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Smart Summaries")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Key points and scripture references")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    
                    if showSummary {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sample Summary:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• God's relentless love for the lost")
                                Text("• The value of every individual soul")
                                Text("• Scripture: Luke 15:3-7")
                            }
                            .font(.subheadline)
                            .padding()
                            .background(.background)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            
            Spacer()
        }
        .animation(.easeInOut(duration: 0.3), value: showTranscript)
        .animation(.easeInOut(duration: 0.3), value: showSummary)
    }
}

// MARK: - Personalization Page
struct PersonalizationPageView: View {
    @Binding var selectedServiceTypes: Set<String>
    @Binding var speakerName: String
    
    let serviceTypes = ["Sunday Service", "Bible Study", "Prayer Meeting", "Youth Service", "Special Event"]
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                Text("Personalize Your Experience")
                    .font(.title2)
                    .fontWeight(.bold)
                .multilineTextAlignment(.center)
                
                VStack(spacing: 20) {
                    // Service types selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What types of services do you usually attend?")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(serviceTypes, id: \.self) { serviceType in
                                Button(action: {
                                    if selectedServiceTypes.contains(serviceType) {
                                        selectedServiceTypes.remove(serviceType)
                                    } else {
                                        selectedServiceTypes.insert(serviceType)
                                    }
                                }) {
                                    Text(serviceType)
                                        .font(.subheadline)
                                        .foregroundColor(selectedServiceTypes.contains(serviceType) ? .white : .accentColor)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selectedServiceTypes.contains(serviceType) ? Color.accentColor : Color.accentColor.opacity(0.1))
                                        .cornerRadius(20)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Speaker name input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pastor or Speaker Name (Optional)")
                            .font(.headline)
                            .foregroundColor(.primary)
        
                        TextField("Enter speaker name", text: $speakerName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                Text("We'll use these preferences to enhance your experience and provide better suggestions.")
                    .font(.caption)
                .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            }
            
            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
}