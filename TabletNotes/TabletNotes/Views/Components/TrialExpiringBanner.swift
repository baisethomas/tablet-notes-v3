import SwiftUI

struct TrialExpiringBanner: View {
    let daysLeft: Int
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 20))
                .foregroundColor(.warningOrange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Trial Ending Soon")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.adaptivePrimaryText)

                Text("\(daysLeft) day\(daysLeft == 1 ? "" : "s") remaining")
                    .font(.caption)
                    .foregroundColor(.adaptiveSecondaryText)
            }

            Spacer()

            Button(action: onUpgrade) {
                Text("Upgrade")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.adaptiveAccent)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.warningOrange.opacity(0.1))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.warningOrange.opacity(0.3)),
            alignment: .bottom
        )
    }
}

#Preview {
    VStack {
        TrialExpiringBanner(daysLeft: 2, onUpgrade: {})
        TrialExpiringBanner(daysLeft: 1, onUpgrade: {})
    }
}
