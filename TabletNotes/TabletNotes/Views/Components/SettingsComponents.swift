import SwiftUI

// MARK: - Settings Section Component
struct SettingsSection<Content: View>: View {
    let title: String
    let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(1.5)
                .foregroundStyle(Color.SV.onSurface.opacity(0.4))
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content()
            }
            .background(Color.SV.surfaceContainerLowest)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Settings Row Component
struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let content: () -> Content

    init(icon: String, title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.SV.primary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.SV.onSurface)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                        .lineLimit(2)
                }
            }

            Spacer()

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Color.SV.surfaceContainerLowest)
    }
}

// MARK: - Settings Toggle Component
struct SettingsToggle: View {
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.SV.primary)
        }
    }
}

// MARK: - Settings Picker Component
struct SettingsPicker<T: Hashable & RawRepresentable & CaseIterable>: View where T.RawValue == String {
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var selection: T

    var body: some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle) {
            Picker("", selection: $selection) {
                ForEach(Array(T.allCases), id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .tint(Color.SV.primary)
        }
    }
}

// MARK: - Settings Navigation Row Component
struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRow(icon: icon, title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Slider Component
struct SettingsSlider: View {
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let formatter: NumberFormatter

    init(icon: String, title: String, subtitle: String? = nil, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1.0) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step

        self.formatter = NumberFormatter()
        self.formatter.numberStyle = .decimal
        self.formatter.maximumFractionDigits = step < 1 ? 1 : 0
    }

    var body: some View {
        VStack(spacing: 8) {
            SettingsRow(icon: icon, title: title, subtitle: subtitle) {
                Text(formatter.string(from: NSNumber(value: value)) ?? "\(value)")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.SV.onSurface.opacity(0.5))
                    .frame(minWidth: 40)
            }

            HStack {
                Spacer()
                    .frame(width: 52)

                Slider(value: $value, in: range, step: step)
                    .tint(Color.SV.primary)

                Spacer()
                    .frame(width: 16)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Settings Divider Component
struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 52)
    }
}

// MARK: - Settings Info Row Component
struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?

    init(icon: String, title: String, value: String, subtitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        self.subtitle = subtitle
    }

    var body: some View {
        SettingsRow(icon: icon, title: title, subtitle: subtitle) {
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color.SV.onSurface.opacity(0.5))
        }
    }
}

// MARK: - Settings Button Component
struct SettingsButton: View {
    let icon: String
    let title: String
    let subtitle: String?
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle {
        case normal
        case destructive
        case prominent

        var foregroundColor: Color {
            switch self {
            case .normal:      return Color.SV.primary
            case .destructive: return Color.SV.error
            case .prominent:   return .white
            }
        }

        var backgroundColor: Color {
            switch self {
            case .normal:      return .clear
            case .destructive: return .clear
            case .prominent:   return Color.SV.primary
            }
        }
    }

    init(icon: String, title: String, subtitle: String? = nil, style: ButtonStyle = .normal, action: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(style.foregroundColor)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(style.foregroundColor)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(style.foregroundColor.opacity(0.7))
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(style.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: style == .prominent ? 12 : 0))
        }
        .buttonStyle(.plain)
    }
}
