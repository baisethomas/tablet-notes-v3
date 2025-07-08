import SwiftUI

struct AppLogoView: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    
    init(size: CGFloat = 90, cornerRadius: CGFloat = 18) {
        self.size = size
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Group {
            if let _ = UIImage(named: "AppLogo") {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                // Fallback logo using SF Symbols
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.accentColor)
                        .frame(width: size, height: size)
                    
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: size * 0.4, weight: .medium))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AppLogoView()
        AppLogoView(size: 60, cornerRadius: 12)
        AppLogoView(size: 120, cornerRadius: 24)
    }
    .padding()
}