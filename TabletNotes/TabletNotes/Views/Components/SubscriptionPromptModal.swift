import SwiftUI

struct SubscriptionPromptModal: View {
    let trialState: SubscriptionTrialState
    let onDismiss: () -> Void
    let onSubscribe: () -> Void

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)

                    Text("Your Trial Has Ended")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.adaptivePrimaryText)

                    Text("Continue enjoying premium features")
                        .font(.subheadline)
                        .foregroundColor(.adaptiveSecondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)
                .padding(.bottom, 24)

                Divider()

                // Features list
                VStack(alignment: .leading, spacing: 16) {
                    SubscriptionFeatureRow(
                        icon: "timer",
                        title: "90-Minute Recordings",
                        description: "Extended recording time for longer sermons"
                    )

                    SubscriptionFeatureRow(
                        icon: "infinity",
                        title: "Unlimited Recordings",
                        description: "Record as many sermons as you need"
                    )

                    SubscriptionFeatureRow(
                        icon: "icloud.fill",
                        title: "Cloud Sync",
                        description: "Access your sermons from any device"
                    )

                    SubscriptionFeatureRow(
                        icon: "waveform.path.ecg",
                        title: "AI Transcription & Summaries",
                        description: "Automatic transcription and smart summaries"
                    )
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 20)

                Divider()

                // Pricing
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        PricingOption(
                            period: "Monthly",
                            price: "$4.99",
                            isRecommended: false
                        )

                        PricingOption(
                            period: "Annual",
                            price: "$39.99",
                            savings: "Save 33%",
                            isRecommended: true
                        )
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 20)

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: onSubscribe) {
                        Text("Upgrade to Premium")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.adaptiveAccent)
                            .cornerRadius(12)
                    }

                    Button(action: onDismiss) {
                        Text("Continue with Free")
                            .font(.subheadline)
                            .foregroundColor(.adaptiveSecondaryText)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.adaptiveBackground)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Subscription Feature Row Component
private struct SubscriptionFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.adaptiveAccent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.adaptivePrimaryText)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.adaptiveSecondaryText)
            }
        }
    }
}

// MARK: - Pricing Option Component
struct PricingOption: View {
    let period: String
    let price: String
    var savings: String? = nil
    let isRecommended: Bool

    var body: some View {
        VStack(spacing: 8) {
            if isRecommended {
                Text("BEST VALUE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.adaptiveAccent)
                    .cornerRadius(4)
            } else {
                Spacer()
                    .frame(height: 20)
            }

            Text(period)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.adaptivePrimaryText)

            Text(price)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.adaptiveAccent)

            if let savings = savings {
                Text(savings)
                    .font(.caption)
                    .foregroundColor(.successGreen)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            isRecommended ?
                Color.adaptiveAccent.opacity(0.1) :
                Color.adaptiveSecondaryBackground
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isRecommended ? Color.adaptiveAccent : Color.clear,
                    lineWidth: 2
                )
        )
        .cornerRadius(12)
    }
}

#Preview {
    SubscriptionPromptModal(
        trialState: .trialExpired,
        onDismiss: {},
        onSubscribe: {}
    )
}
