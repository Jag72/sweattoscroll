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
    static let emerald       = Color(red: 0.098, green: 0.722, blue: 0.533)  // #19B888 green
    static let ringTrack     = Color(red: 0.925, green: 0.918, blue: 0.894)  // #ECEAE4 cream track
    static let danger        = Color(red: 0.878, green: 0.341, blue: 0.310)  // #E0574F

    // Per-metric accents (clean-minimal: one accent per card)
    static let recovery      = Color(red: 0.098, green: 0.722, blue: 0.533)  // #19B888
    static let strain        = Color(red: 1.0,   green: 0.388, blue: 0.129)  // #FF6321
    static let sleep         = Color(red: 0.545, green: 0.498, blue: 0.839)  // #8B7FD6
    static let hrv           = Color(red: 0.302, green: 0.553, blue: 0.941)  // #4D8DF0

    // Navigation
    static let navBar        = Color(red: 0.086, green: 0.086, blue: 0.102)  // #16161A dark pill
    static let navInactive   = Color(red: 0.482, green: 0.482, blue: 0.510)  // #7B7B82

    // Soft tile tint backgrounds (kept for compatibility)
    static let purpleTile    = Color(red: 0.941, green: 0.933, blue: 0.973)  // #F0EEF8
    static let mintTile      = Color(red: 0.937, green: 0.965, blue: 0.949)  // #EFF6F2
    static let pinkTile      = Color(red: 1.0,   green: 0.953, blue: 0.925)  // #FFF3EC
    static let yellowTile    = Color(red: 1.0,   green: 0.980, blue: 0.867)
}

// MARK: - Reusable card surface (clean-minimal: white, no border, soft layered float)

extension View {
    /// Standard clean-minimal card background: white, no border, soft layered shadow.
    func s2sCard(cornerRadius: CGFloat = 22) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.045), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.04),  radius: 3,  x: 0, y: 1)
        )
    }
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
            .s2sCard(cornerRadius: cornerRadius)
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
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .background(S2STheme.background.opacity(configuration.isPressed ? 0.7 : 1),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
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
//
// Clean-minimal: no grey circle behind the icon, the glyph sits directly on the
// white card in its tint colour, with an OPTIONAL mini progress ring top-right.
// `progress` defaults to nil so every existing call site keeps compiling.

struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = S2STheme.primary
    var backgroundColor: Color = Color.white
    var progress: Double? = nil          // optional mini-ring, 0...1

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Spacer()
                if let p = progress {
                    ZStack {
                        Circle().stroke(tint.opacity(0.15), lineWidth: 3.5)
                        Circle()
                            .trim(from: 0, to: min(max(p, 0), 1))
                            .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 34, height: 34)
                }
            }
            Spacer(minLength: 14)
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(S2STheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(S2STheme.muted)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .s2sCard(cornerRadius: 22)
    }
}

// MARK: - Shield Status Banner
//
// Clean-minimal: white card, soft float, a rounded-square accent icon chip and a
// small progress ring on the right. Semantic colour (emerald unlocked / orange
// locked) is preserved. Same initialiser as before.

struct ShieldStatusBanner: View {
    let isUnlocked: Bool
    let kcalRemaining: Int
    let progressPercent: Int

    private var accentColor: Color {
        isUnlocked ? S2STheme.emerald : S2STheme.primary
    }

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 42, height: 42)
                Image(systemName: isUnlocked ? "lock.open.fill" : "shield.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(isUnlocked ? "Apps unlocked" : "Apps locked")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(S2STheme.text)
                Text(isUnlocked
                     ? "You've earned your scroll time"
                     : "\(kcalRemaining) kcal to unlock your scroll")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(S2STheme.muted)
            }
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .stroke(S2STheme.ringTrack, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(Double(progressPercent) / 100, 0), 1))
                    .stroke(accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(progressPercent)")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(S2STheme.text)
            }
            .frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .s2sCard(cornerRadius: 22)
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
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
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
