// Views/Components/Components.swift
// Reusable UI components for Sweat2Scroll.
import SwiftUI
import CoreImage.CIFilterBuiltins
import AVFoundation

struct ProgressRingView: View {
    let progress: Double         // 0.0 to 1.0
    let current: Double
    let goal: Double
    let currency: GoalCurrency
    let isUnlocked: Bool

    private let ringWidth: CGFloat = 20
    private let ringSize: CGFloat  = 220

    var body: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(Color.ringTrack, lineWidth: ringWidth)
                .frame(width: ringSize, height: ringSize)

            // Progress arc — electric orange
            Circle()
                .trim(from: 0, to: min(progress, 1.0))
                .stroke(
                    isUnlocked ? Color.deepTeal : Color.electricOrange,
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: progress)

            // Center content
            VStack(spacing: 4) {
                Text("\(Int(current))")
                    .font(.display(48))
                    .foregroundColor(.ink)
                Text(currency == .activeCalories ? "kcal" : "steps")
                    .font(.capsLabel(14))
                    .foregroundColor(.muted)
            }
        }
    }
}

// MARK: - ShieldToggleView (sscrollBestUI style)
struct ShieldToggleView: View {
    let isActive: Bool
    let isUnlocked: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isActive ? "shield.fill" : "shield.slash")
                .font(.title3.weight(.semibold))
                .foregroundColor(isActive ? .electricOrange : .muted)
                .frame(width: 44, height: 44)
                .background(Circle().fill(isActive ? Color.electricOrange.opacity(0.12) : Color.muted.opacity(0.1)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Master Shield")
                    .font(.bodyMedium(15))
                    .foregroundColor(.ink)
                Text(isActive ? "Apps locked until goal met" : "Shield is disabled")
                    .font(.caption2)
                    .foregroundColor(.muted)
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isActive }, set: { onToggle($0) }))
                .tint(.electricOrange)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.thinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))
        )
        .padding(.horizontal)
    }
}

// Custom toggle style — kept for backward compat but now delegates to SwiftUI default
struct ShieldToggleStyle: ToggleStyle {
    let isUnlocked: Bool
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration).tint(.electricOrange)
    }
}

// MARK: - QRCodeGeneratorView
// Renders a QR code from an arbitrary string using CoreImage CIQRCodeGenerator.
// Styled with the app's lime accent on black background for maximum scan contrast.
struct QRCodeGeneratorView: View {
    let data: String
    let size: CGFloat

    /// Generates a UIImage QR code from a string using CoreImage.
    private var qrImage: UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        // Set the input data (UTF-8 encoded)
        filter.setValue(data.data(using: .utf8), forKey: "inputMessage")

        // Use high error correction (30% recovery) since phones scan at angles
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        // Scale up from the tiny CIImage to the requested display size
        let scaleX = size / ciImage.extent.width
        let scaleY = size / ciImage.extent.height
        let scaledImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Apply the app's lime accent color tint
        let coloredImage = applyColorTint(to: scaledImage)

        guard let cgImage = context.createCGImage(coloredImage, from: coloredImage.extent) else {
            return UIImage(systemName: "xmark.circle") ?? UIImage()
        }

        return UIImage(cgImage: cgImage)
    }

    /// Applies a lime-on-black color tint to the QR code for branding.
    private func applyColorTint(to image: CIImage) -> CIImage {
        // False Color filter maps black → color0, white → color1
        let falseColor = CIFilter.falseColor()
        falseColor.inputImage = image
        falseColor.color0 = CIColor(red: 1.0, green: 0.388, blue: 0.129, alpha: 1.0) // Electric orange #FF6321 (QR modules)
        falseColor.color1 = CIColor(red: 0.961, green: 0.949, blue: 0.929, alpha: 1.0) // Paper background #F5F2ED
        return falseColor.outputImage ?? image
    }

    var body: some View {
        Image(uiImage: qrImage)
            .interpolation(.none)  // Keep sharp pixel edges
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.electricOrange.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - QRCodeScannerView
// AVFoundation camera-based QR code scanner wrapped in a SwiftUI UIViewControllerRepresentable.
// Calls `onScanned` with the decoded string when a QR code is detected.
struct QRCodeScannerView: UIViewControllerRepresentable {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScanned = { code in
            onScanned(code)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

// MARK: - QRScannerViewController (AVFoundation)
class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScanned: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasScanned = false  // Prevent duplicate callbacks

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        captureSession = session

        // Get the back camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            showCameraError()
            return
        }

        guard session.canAddInput(input) else {
            showCameraError()
            return
        }
        session.addInput(input)

        // Set up metadata output for QR codes
        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            showCameraError()
            return
        }
        session.addOutput(metadataOutput)

        // Only detect QR codes
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        // Set up camera preview layer
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        // Add scanning overlay (finder frame)
        addScannerOverlay()

        // Start capture
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    private func addScannerOverlay() {
        // Semi-transparent overlay with a clear center cutout
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = .clear
        overlayView.isUserInteractionEnabled = false
        view.addSubview(overlayView)

        // Finder frame — lime-colored border around scan area
        let finderSize: CGFloat = 240
        let finderFrame = CGRect(
            x: (view.bounds.width - finderSize) / 2,
            y: (view.bounds.height - finderSize) / 2 - 40,
            width: finderSize,
            height: finderSize
        )

        let finderView = UIView(frame: finderFrame)
        finderView.layer.borderColor = UIColor(red: 1.0, green: 0.388, blue: 0.129, alpha: 0.8).cgColor
        finderView.layer.borderWidth = 3
        finderView.layer.cornerRadius = 16
        finderView.backgroundColor = .clear
        view.addSubview(finderView)

        // Instruction label
        let label = UILabel()
        label.text = "Point at your partner's QR code"
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: finderView.bottomAnchor, constant: 24)
        ])
    }

    private func showCameraError() {
        let label = UILabel()
        label.text = "Camera access required\nfor QR code scanning."
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        // Only process the first valid QR code, and only once
        guard !hasScanned,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let stringValue = object.stringValue else { return }

        hasScanned = true

        // Haptic feedback on successful scan
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Stop the session
        captureSession?.stopRunning()

        // Deliver result
        onScanned?(stringValue)
    }
}

// MARK: - Onboarding Scaffold
/// Shared layout chrome for every onboarding / single-page flow:
/// paper background, locked light scheme, centered title block, scrolling content,
/// and a sticky bottom action bar with primary + optional secondary buttons.
struct OnboardingScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var stepIndex: Int? = nil
    var stepCount: Int? = nil
    /// When set, renders a circular chevron-back button in the top-leading area
    /// so the user can correct anything entered on a previous screen.
    var backAction: (() -> Void)? = nil
    var primaryTitle: String
    var primaryEnabled: Bool = true
    var primaryLoading: Bool = false
    let primaryAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            Circle()
                .fill(Color.electricOrange.opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 70)
                .offset(x: 130, y: -240)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                // Top bar: back arrow + step indicator. Both are optional and
                // share a single horizontal lane so the layout stays compact.
                if backAction != nil || (stepIndex != nil && stepCount != nil) {
                    HStack(spacing: 12) {
                        if let backAction {
                            Button(action: backAction) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.ink)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(Color.white)
                                            .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Back")
                        }

                        if let stepIndex, let stepCount, stepCount > 0 {
                            HStack(spacing: 6) {
                                ForEach(0..<stepCount, id: \.self) { i in
                                    Capsule()
                                        .fill(i <= stepIndex ? Color.electricOrange : Color.ringTrack)
                                        .frame(height: 4)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Spacer()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.display(26))
                            .foregroundColor(.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 15))
                                .foregroundColor(.muted)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 16) { content() }
                            .padding(.top, 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, (stepIndex == nil && backAction == nil) ? 32 : 4)
                    .padding(.bottom, 24)
                }

                VStack(spacing: 10) {
                    Button(action: primaryAction) {
                        HStack(spacing: 10) {
                            if primaryLoading { ProgressView().tint(.white) }
                            Text(primaryTitle).fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            primaryEnabled
                                ? LinearGradient(colors: [.electricOrange, Color(hex: "#FF9A62")],
                                                 startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [Color.muted.opacity(0.25), Color.muted.opacity(0.2)],
                                                 startPoint: .leading, endPoint: .trailing)
                        )
                        .foregroundColor(primaryEnabled ? .white : .muted)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: primaryEnabled ? Color.electricOrange.opacity(0.25) : .clear,
                                radius: 12, y: 4)
                    }
                    .disabled(!primaryEnabled || primaryLoading)

                    if let secondaryTitle, let secondaryAction {
                        Button(secondaryTitle, action: secondaryAction)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.muted)
                            .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(.light)
    }
}

// MARK: - Auth Form Input
/// Polished text field for auth / onboarding forms with a leading icon, visible
/// placeholder, and focus-aware accent border. Always renders against paper.
struct AuthFormField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var disableAutocorrection: Bool = true
    var isSecure: Bool = false
    var showSecure: Binding<Bool>? = nil
    var accentColor: Color = .electricOrange
    /// Set for UI tests / accessibility (applied to the text field).
    var accessibilityFieldID: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isFocused ? accentColor : .muted)
                .frame(width: 18)

            Group {
                if isSecure, let showSecure, !showSecure.wrappedValue {
                    SecureField("", text: $text,
                                prompt: Text(placeholder).foregroundColor(.muted.opacity(0.85)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.ink)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(disableAutocorrection)
                        .focused($isFocused)
                        .modifier(OptionalAccessibilityIdentifier(id: accessibilityFieldID))
                } else {
                    TextField("", text: $text,
                              prompt: Text(placeholder).foregroundColor(.muted.opacity(0.85)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.ink)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(disableAutocorrection)
                        .focused($isFocused)
                        .modifier(OptionalAccessibilityIdentifier(id: accessibilityFieldID))
                }
            }

            if let showSecure {
                Button { showSecure.wrappedValue.toggle() } label: {
                    Image(systemName: showSecure.wrappedValue ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isFocused ? accentColor.opacity(0.55) : Color.ringTrack, lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.18), value: isFocused)
    }
}

/// Applies `accessibilityIdentifier` only when `id` is non-nil (keeps production trees clean).
private struct OptionalAccessibilityIdentifier: ViewModifier {
    let id: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

// MARK: - Sweat2Scroll Logo
/// Premium brand mark used across launch, auth, and dashboard headers.
/// A charcoal "shield" badge with a partial activity ring (gradient orange) and
/// a centered bolt — represents earned energy. Scales from 24 pt favicons up
/// to 200 pt hero displays.
struct Sweat2ScrollLogo: View {
    var size: CGFloat = 72
    /// When true, removes the dark badge background — useful on dark hero screens
    /// where the ring + bolt should "float" against the existing background.
    var transparentBackground: Bool = false
    /// Drives the ring trace and bolt entry on first appear.
    var animated: Bool = false

    @State private var ringTrim: CGFloat = 0.78   // Final trim
    @State private var ringRotation: Double = 0
    @State private var boltScale: CGFloat = 1
    @State private var boltOpacity: Double = 1

    private var cornerRadius: CGFloat { size * 0.26 }
    private var ringSize: CGFloat { size * 0.66 }
    private var ringWidth: CGFloat { size * 0.085 }

    var body: some View {
        ZStack {
            if !transparentBackground {
                badgeBackground
            }
            activityRing
            boltMark
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: Color.electricOrange.opacity(0.22),
                radius: size * 0.18, y: size * 0.06)
        .accessibilityLabel("Sweat2Scroll")
        .onAppear {
            guard animated else { return }
            ringTrim = 0
            boltScale = 0.4
            boltOpacity = 0
            withAnimation(.easeOut(duration: 1.0)) {
                ringTrim = 0.78
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.65).delay(0.45)) {
                boltScale = 1
                boltOpacity = 1
            }
            withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    // MARK: - Components

    /// Charcoal "shield" rounded rectangle with subtle inner highlight.
    private var badgeBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "#1A1A1F"),
                            Color(hex: "#0E0E12"),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Inner highlight — gives a subtle glassy dome
            RoundedRectangle(cornerRadius: cornerRadius * 0.85, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: size * 0.018
                )
                .padding(size * 0.06)

            // Faint orange aura behind ring
            Circle()
                .fill(Color.electricOrange.opacity(0.18))
                .frame(width: ringSize * 1.05, height: ringSize * 1.05)
                .blur(radius: size * 0.18)
        }
    }

    /// Apple-Activity-style ring: orange→amber gradient on a dim track.
    private var activityRing: some View {
        ZStack {
            // Track
            Circle()
                .stroke(
                    Color.white.opacity(transparentBackground ? 0.12 : 0.08),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)

            // Filled arc
            Circle()
                .trim(from: 0, to: max(0.001, ringTrim))
                .stroke(
                    AngularGradient(
                        colors: [
                            Color(hex: "#FF8A3D"),
                            Color(hex: "#FF6321"),
                            Color(hex: "#FF3F33"),
                            Color(hex: "#FFB347"),
                            Color(hex: "#FF8A3D"),
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .frame(width: ringSize, height: ringSize)
                .rotationEffect(.degrees(-90 + ringRotation))
        }
    }

    /// Centered lightning bolt mark — symbolizes "earned" screen time.
    private var boltMark: some View {
        Image(systemName: "bolt.fill")
            .font(.system(size: size * 0.30, weight: .heavy))
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.white, Color(hex: "#FFF1E6")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: Color.electricOrange.opacity(0.35),
                    radius: size * 0.05, y: 1)
            .scaleEffect(boltScale)
            .opacity(boltOpacity)
    }
}

/// Typographic wordmark used alongside the badge on splash, landing, and auth.
struct Sweat2ScrollWordmark: View {
    var size: CGFloat = 24
    var dark: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text("SWEAT")
                .foregroundColor(dark ? Color.white : Color.ink)
            Text("2")
                .foregroundColor(.electricOrange)
            Text("SCROLL")
                .foregroundColor(dark ? Color.white : Color.ink)
        }
        .font(.system(size: size, weight: .black, design: .rounded))
        .tracking(size * 0.05)
        .accessibilityLabel("Sweat2Scroll")
    }
}

// MARK: - QR Scanner SwiftUI Wrapper with Sheet Presentation
// A full-screen scanner sheet with a close button overlay.
struct QRScannerSheet: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            QRCodeScannerView { code in
                onScanned(code)
                dismiss()
            }
            .ignoresSafeArea()

            // Close button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(16)
            }
        }
    }
}
