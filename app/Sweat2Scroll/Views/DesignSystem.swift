import SwiftUI

// MARK: - Theme tokens

enum S2STheme {
    // Backgrounds
    static let background    = Color(red: 0.961, green: 0.949, blue: 0.929)  // #F5F2ED cream/paper
    static let surface       = Color.white
    static let surfaceStrong = Color.white
    static let border        = Color(red: 0.90, green: 0.90, blue: 0.90)

    // Text
    static let text          = Color(red: 0.102, green: 0.102, blue: 0.102)  // #1A1A1A ink
    static let muted         = Color(red: 0.557, green: 0.557, blue: 0.557)  // #8E8E8E

    // Accents
    static let primary       = Color(red: 1.0,   green: 0.388, blue: 0.129)  // #FF6321 electric orange
    static let orange        = Color(red: 1.0,   green: 0.388, blue: 0.129)  // alias
    static let teal          = Color(red: 0.059, green: 0.298, blue: 0.361)  // #0F4C5C deep teal
    static let emerald       = Color(red: 0.063, green: 0.725, blue: 0.506)  // #10B981 green
    static let ringTrack     = Color(red: 0.894, green: 0.894, blue: 0.906)  // #E4E4E7
    static let danger        = Color(red: 0.957, green: 0.247, blue: 0.384)

    // Tile backgrounds (pastel tints)
    static let purpleTile    = Color(red: 0.933, green: 0.918, blue: 1.0)
    static let mintTile      = Color(red: 0.867, green: 0.976, blue: 0.961)
    static let pinkTile      = Color(red: 1.0,   green: 0.910, blue: 0.910)
    static let yellowTile    = Color(red: 1.0,   green: 0.980, blue: 0.867)
}

// MARK: - Typography helpers

extension Font {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }
    static func bodyMedium(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }
    static func capsLabel(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold)
    }
}

// MARK: - GlassCard

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 24
    @ViewBuilder var content: Content

    init(padding: CGFloat = 18,
         cornerRadius: CGFloat = 24,
         @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 3)
            )
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = S2STheme.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(configuration.isPressed ? 0.80 : 1.0),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(S2STheme.ringTrack.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(S2STheme.text)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Convenience Button Views

/// Filled primary CTA button with the brand orange background.
struct PrimaryButton: View {
    let title: String
    var color: Color = S2STheme.primary
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(PrimaryButtonStyle(color: color))
    }
}

/// Subtle secondary CTA button with a neutral background.
struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(SecondaryButtonStyle())
    }
}

// MARK: - Progress card ring (used on dark teal card)

struct GaugeRingView: View {
    let progress: Double
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 16)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.white,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 100, height: 100)
    }
}

// MARK: - Recovery ring (Progress tab)

struct RecoveryRingView: View {
    let fraction: Double
    let value: String
    let unit: String
    let label: String
    let color: Color
    var ringSize: CGFloat = 200
    var lineWidth: CGFloat = 18

    @State private var animated = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(S2STheme.ringTrack, lineWidth: lineWidth)
                .frame(width: ringSize, height: ringSize)
            Circle()
                .trim(from: 0, to: animated ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 1.0), value: animated)
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: ringSize * 0.28, weight: .black, design: .rounded))
                        .foregroundStyle(S2STheme.text)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: ringSize * 0.11, weight: .semibold))
                            .foregroundStyle(S2STheme.muted)
                    }
                }
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: ringSize * 0.09, weight: .semibold))
                        .foregroundStyle(S2STheme.muted)
                        .textCase(.uppercase)
                        .tracking(1.5)
                }
            }
        }
        .onAppear { animated = true }
    }
}

// MARK: - Metric Tile (2×2 stat grid)

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = S2STheme.primary
    var backgroundColor: Color = Color.white

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(S2STheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(S2STheme.muted)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Shield Status Banner

struct ShieldStatusBanner: View {
    let isUnlocked: Bool
    let kcalRemaining: Int
    let progressPercent: Int

    private var bannerBg: Color {
        isUnlocked
            ? S2STheme.emerald.opacity(0.12)
            : Color(red: 1.0, green: 0.90, blue: 0.90)
    }
    private var accentColor: Color {
        isUnlocked ? S2STheme.emerald : S2STheme.danger
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: isUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isUnlocked ? "Apps unlocked" : "Apps blocked")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accentColor)
                Text(isUnlocked
                     ? "You've earned your scroll time today!"
                     : "\(kcalRemaining) kcal to go")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(S2STheme.muted)
            }
            Spacer()
            Text("\(progressPercent)%")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(accentColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(bannerBg)
        )
    }
}

// MARK: - App Background

struct AppBackground: View {
    var body: some View {
        S2STheme.background.ignoresSafeArea()
    }
}

// MARK: - Settings row helper

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String = ""
    var chevron: Bool = true

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(S2STheme.text)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(S2STheme.muted)
                }
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(S2STheme.muted.opacity(0.6))
            }
        }
    }
}
