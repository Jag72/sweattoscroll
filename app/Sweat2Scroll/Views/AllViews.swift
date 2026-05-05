// Views/OnboardingView.swift
import SwiftUI
import FamilyControls

struct OnboardingView: View {
    @EnvironmentObject var onboardingVM: OnboardingViewModel
    @EnvironmentObject var activityVM: ActivityViewModel

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            switch onboardingVM.currentStep {
            case .welcome:       WelcomeStepView()
            case .profile:       ProfileStepView()
            case .goalSetup:     GoalSetupStepView()
            case .appCuration:   AppCurationStepView()
            case .pairing:       PairingStepView()
            case .contractReview: ContractReviewStepView()
            case .complete:      OnboardingCompleteView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// Step 1: Welcome
struct WelcomeStepView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("SWEAT2SCROLL")
                .font(.system(size: 42, weight: .black, design: .default))
                .foregroundColor(Color.electricOrange)
            Text("Earn your screen time.\nMove first. Then scroll.")
                .multilineTextAlignment(.center)
                .foregroundColor(.muted)
                .font(.title3)
            Spacer()
            PrimaryButton(title: "Get Started") { vm.advance() }
        }
        .padding(32)
    }
}

// Step 2: Profile (HealthKit reads biometrics automatically)
struct ProfileStepView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Your Profile", subtitle: "We read your stats from Apple Health to compute a safe daily goal.")
            // HealthKit reads weight, height, age, sex automatically
            // Display what we found
            InfoCard(label: "Weight", value: "\(Int(vm.userProfile.weightKg)) kg")
            InfoCard(label: "Height", value: "\(Int(vm.userProfile.heightCm)) cm")
            InfoCard(label: "Age", value: "\(vm.userProfile.ageYears) years")
            Spacer()
            HStack {
                SecondaryButton(title: "Back") { vm.back() }
                PrimaryButton(title: "Continue") { vm.advance() }
            }
        }
        .padding(24)
    }
}

// Step 3: Goal Setup
struct GoalSetupStepView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    @State private var sliderValue: Double = 300

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Set Your Goal", subtitle: "Choose your daily activity currency and target.")

            // Currency picker
            Picker("Currency", selection: $vm.activityGoal.currency) {
                ForEach(GoalCurrency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            // Goal slider
            VStack {
                Text("\(Int(sliderValue)) \(vm.activityGoal.currency == .activeCalories ? "kcal" : "steps")")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(Color.electricOrange)
                Slider(value: $sliderValue, in: 50...vm.activityGoal.hardCap, step: 10)
                    .tint(Color.electricOrange)
                Text("Recommended: \(Int(vm.activityGoal.recommendedTarget)) — Hard cap: \(Int(vm.activityGoal.hardCap))")
                    .font(.caption)
                    .foregroundColor(.muted)
            }

            Spacer()
            HStack {
                SecondaryButton(title: "Back") { vm.back() }
                PrimaryButton(title: "Continue") {
                    vm.updateGoal(target: sliderValue)
                    vm.advance()
                }
            }
        }
        .padding(24)
    }
}

// Step 4: App Curation (FamilyActivityPicker)
struct AppCurationStepView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Lock Your Apps", subtitle: "Search and pick apps to shield until you earn them. Sweat2Scroll can't block itself — it's removed if selected.")

            Button("Select Apps") { showPicker = true }
                .buttonStyle(.borderedProminent)
                .tint(Color.electricOrange)
                .foregroundColor(.white)

            Text("\(vm.activitySelection.applicationTokens.count) apps selected")
                .foregroundColor(.muted)
                .font(.caption)

            Spacer()
            HStack {
                SecondaryButton(title: "Back") { vm.back() }
                PrimaryButton(title: "Continue") { vm.advance() }
            }
        }
        .padding(24)
        .familyActivityPicker(isPresented: $showPicker, selection: $vm.activitySelection)
        .onChange(of: vm.activitySelection) { newValue in
            vm.confirmAppSelection(newValue)
        }
    }
}

// Step 5: Pairing
struct PairingStepView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    @EnvironmentObject var partnerVM: PartnerViewModel

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Pair with Partner", subtitle: "Connect with your accountability partner.")

            if !vm.isPairingComplete {
                // Method picker: QR (local) or iMessage (remote)
                Picker("Method", selection: $vm.pairingMethod) {
                    Text("QR Code").tag(PairingMethod.qrCode)
                    Text("iMessage").tag(PairingMethod.iMessageLink)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
            }

            if vm.isPairingComplete {
                // Pairing success state
                PairingSuccessCard(partnerName: vm.partnerDisplayName)
            } else if vm.pairingMethod == .qrCode {
                // QR code flow — role picker + initiator/joiner views
                Picker("Role", selection: $vm.pairingRole) {
                    Text("Show My Code").tag(OnboardingViewModel.PairingRole.initiator)
                    Text("Scan Partner").tag(OnboardingViewModel.PairingRole.joiner)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if vm.pairingRole == .initiator {
                    InitiatorPairingView()
                } else {
                    JoinerPairingView()
                }
            } else {
                // iMessage link flow
                iMessagePairingView()
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            HStack {
                SecondaryButton(title: "Back") { vm.back() }
                PrimaryButton(title: vm.isPairingComplete ? "Continue" : "Skip for Now") {
                    vm.advance()
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $vm.showScanner) {
            QRScannerSheet { scannedCode in
                vm.handleScannedQRCode(scannedCode)
            }
        }
        .sheet(isPresented: $vm.showShareSheet) {
            if let items = vm.iMessageShareItems() as? [String], let text = items.first {
                ShareSheet(activityItems: [text])
            }
        }
        // When pairing completes, persist the contract via PartnerViewModel
        .onChange(of: vm.isPairingComplete) { completed in
            if completed, let contract = vm.governanceContract {
                Task {
                    await partnerVM.saveContract(contract)
                }
            }
        }
    }
}

// MARK: - Initiator Pairing View (Device A — shows QR code)
private struct InitiatorPairingView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    @State private var hasGeneratedQR = false

    var body: some View {
        VStack(spacing: 16) {
            if vm.qrCodeData.isEmpty || !hasGeneratedQR {
                // Generate button
                Button(action: {
                    _ = vm.generatePairingQRCode()
                    hasGeneratedQR = true
                    vm.startPollingForResponse()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode")
                            .font(.title2)
                        Text("Generate Pairing Code")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.electricOrange)
                    .cornerRadius(14)
                }
            } else {
                // Display the generated QR code
                QRCodeGeneratorView(data: vm.qrCodeData, size: 220)
                    .shadow(color: Color.electricOrange.opacity(0.15), radius: 20)

                if vm.isWaitingForPartner {
                    // Waiting for Device B to scan and respond
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.electricOrange)
                            .scaleEffect(0.8)
                        Text("Waiting for partner to scan...")
                            .font(.caption)
                            .foregroundColor(.muted)
                    }
                    .padding(.top, 4)
                } else {
                    Text("Show this to your partner to scan.")
                        .font(.caption)
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                }

                // Regenerate option
                Button("Regenerate Code") {
                    vm.stopPolling()
                    _ = vm.generatePairingQRCode()
                    vm.startPollingForResponse()
                }
                .font(.caption)
                .foregroundColor(.muted)
            }
        }
        .onDisappear {
            vm.stopPolling()
        }
    }
}

// MARK: - Joiner Pairing View (Device B — scans QR code)
private struct JoinerPairingView: View {
    @EnvironmentObject var vm: OnboardingViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(Color.electricOrange.opacity(0.6))

            if vm.isPairingInProgress {
                ProgressView()
                    .tint(Color.electricOrange)
                Text("Completing key exchange...")
                    .font(.caption)
                    .foregroundColor(.muted)
            } else {
                Text("Scan your partner's QR code to\nexchange encryption keys.")
                    .font(.subheadline)
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)

                Button(action: { vm.showScanner = true }) {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2)
                        Text("Open Scanner")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.electricOrange)
                    .cornerRadius(14)
                }
            }
        }
    }
}

// MARK: - iMessage Pairing View (Device A — share link remotely)
private struct iMessagePairingView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    @State private var hasGeneratedLink = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "message.fill")
                .font(.system(size: 48))
                .foregroundColor(Color.electricOrange.opacity(0.6))

            Text("Send a secure pairing link\nto your partner via iMessage.")
                .font(.subheadline)
                .foregroundColor(.muted)
                .multilineTextAlignment(.center)

            if !hasGeneratedLink {
                Button(action: {
                    _ = vm.generatePairingLink()
                    hasGeneratedLink = true
                    vm.startPollingForResponse()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "link.badge.plus")
                            .font(.title2)
                        Text("Generate Link")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.electricOrange)
                    .cornerRadius(14)
                }
            } else if let url = vm.pairingURL {
                // Link generated — show share button
                VStack(spacing: 12) {
                    // Compact URL preview
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(Color.electricOrange)
                            .font(.caption)
                        Text(url.host ?? "sweat2scroll.app")
                            .font(.caption.monospaced())
                            .foregroundColor(.muted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)

                    Button(action: {
                        vm.showShareSheet = true
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                            Text("Share via iMessage")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(Color.electricOrange)
                        .cornerRadius(14)
                    }
                }

                if vm.isWaitingForPartner {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(Color.electricOrange)
                            .scaleEffect(0.8)
                        Text("Waiting for partner to open link...")
                            .font(.caption)
                            .foregroundColor(.muted)
                    }
                    .padding(.top, 4)
                }

                Button("Generate New Link") {
                    vm.stopPolling()
                    _ = vm.generatePairingLink()
                    vm.startPollingForResponse()
                }
                .font(.caption)
                .foregroundColor(.muted)
            }
        }
        .onDisappear {
            vm.stopPolling()
        }
    }
}

// MARK: - UIActivityViewController Wrapper (Share Sheet)
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Pairing Success Card
private struct PairingSuccessCard: View {
    let partnerName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("Paired!")
                .font(.title2.bold())
                .foregroundColor(.ink)

            Text("Connected with \(partnerName.isEmpty ? "your partner" : partnerName)")
                .font(.subheadline)
                .foregroundColor(.muted)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(Color.electricOrange)
                    .font(.caption)
                Text("ECDH key exchange complete")
                    .font(.caption2)
                    .foregroundColor(.muted)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

// Step 6: Contract Review
struct ContractReviewStepView: View {
    @EnvironmentObject var vm: OnboardingViewModel
    @EnvironmentObject var activityVM: ActivityViewModel

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(title: "Your Contract", subtitle: "Review and confirm your governance agreement.")
            InfoCard(label: "Daily Goal", value: "\(Int(vm.activityGoal.agreedTarget)) \(vm.activityGoal.currency.rawValue)")
            InfoCard(label: "Hard Cap", value: "\(Int(vm.activityGoal.hardCap)) kcal max")
            InfoCard(label: "Apps Locked", value: "\(vm.activitySelection.applicationTokens.count) apps")
            Spacer()
            HStack {
                SecondaryButton(title: "Back") { vm.back() }
                PrimaryButton(title: "Accept & Start") {
                    activityVM.applyOnboardingGoal(vm.activityGoal)
                    vm.completeOnboarding()
                }
            }
        }
        .padding(24)
    }
}

// MARK: - SettingsView.swift
struct SettingsView: View {
    @ObservedObject private var auth = AuthManager.shared
    @EnvironmentObject var activityVM: ActivityViewModel
    @EnvironmentObject var onboardingVM: OnboardingViewModel
    @EnvironmentObject var partnerVM: PartnerViewModel
    @EnvironmentObject var screenTime: ScreenTimeService
    @Environment(\.dismiss) var dismiss

    private var screenTimeAuthLabel: String {
        switch screenTime.authorizationStatus {
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .notDetermined: return "Not determined"
        }
    }

    @State private var isEditingGoal = false
    @State private var editedTarget: Double = 300
    @State private var editedCurrency: GoalCurrency = .activeCalories
    @State private var showRepairSheet = false
    @State private var showUnpairConfirm = false
    @State private var morningReminder = true
    @State private var tamperAlerts = true
    @State private var partnerNotifications = true
    @State private var showBreakGlassSheet = false

    var body: some View {
        NavigationStack {
            List {
                // MARK: Goal Section
                Section {
                    if isEditingGoal {
                        GoalEditorView(
                            target: $editedTarget,
                            currency: $editedCurrency,
                            hardCap: activityVM.activityGoal.hardCap,
                            recommendedTarget: activityVM.activityGoal.recommendedTarget,
                            onSave: {
                                activityVM.updateGoal(target: editedTarget, currency: editedCurrency)
                                isEditingGoal = false
                            },
                            onCancel: { isEditingGoal = false }
                        )
                    } else {
                        LabeledContent("Daily Target", value: "\(Int(activityVM.activityGoal.agreedTarget)) \(activityVM.activityGoal.currency == .activeCalories ? "kcal" : "steps")")
                        LabeledContent("Hard Cap", value: "\(Int(activityVM.activityGoal.hardCap)) kcal")
                        LabeledContent("Currency", value: activityVM.activityGoal.currency.rawValue)
                        Button("Edit Goal") {
                            editedTarget = activityVM.activityGoal.agreedTarget
                            editedCurrency = activityVM.activityGoal.currency
                            isEditingGoal = true
                        }
                    }
                } header: {
                    Text("Goal")
                }

                // MARK: Screen Time + Shield
                Section {
                    LabeledContent("Screen Time API", value: screenTimeAuthLabel)
                    if screenTime.authorizationStatus != .approved {
                        Text("Sweat2Scroll needs Screen Time permission to block selected apps until you meet your goal. If you denied access, enable it in Settings → Screen Time.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Toggle("Master Shield", isOn: Binding(
                        get: { activityVM.isShieldActive },
                        set: { activityVM.toggleShield(enabled: $0) }
                    ))
                    .disabled(screenTime.authorizationStatus != .approved)
                    LabeledContent("Status", value: activityVM.isUnlocked ? "Unlocked" : "Locked")
                } header: {
                    Text("Shield")
                }

                // MARK: Partner Section
                Section {
                    if partnerVM.isPartnerPaired {
                        LabeledContent("Partner", value: partnerVM.partnerDisplayName)
                        if let contract = partnerVM.contract {
                            LabeledContent("Paired Since", value: contract.pairedAt.formatted(date: .abbreviated, time: .omitted))
                            LabeledContent("Contract ID", value: String(contract.id.uuidString.prefix(8)) + "...")
                        }
                        Button("Re-Pair Device") { showRepairSheet = true }
                        Button("Unpair Partner", role: .destructive) { showUnpairConfirm = true }
                    } else {
                        Text("No partner connected")
                            .foregroundColor(.secondary)
                        Button("Pair with Partner") { showRepairSheet = true }
                    }
                } header: {
                    Text("Partner")
                }

                // MARK: Notifications Section
                Section {
                    Toggle("Morning Progress Summary", isOn: $morningReminder)
                    Toggle("Tamper Detection Alerts", isOn: $tamperAlerts)
                    Toggle("Partner Activity Updates", isOn: $partnerNotifications)
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Tamper alerts notify your partner when HealthKit or Screen Time permissions are revoked.")
                }

                // MARK: Data & Privacy Section
                Section {
                    Button("Break-Glass tools") {
                        showBreakGlassSheet = true
                    }
                    NavigationLink("View Audit Log") {
                        AuditLogView()
                    }
                    LabeledContent("Health Data", value: "On-device only")
                    LabeledContent("Policy Engine", value: "OPA Wasm (local)")
                } header: {
                    Text("Data & Privacy")
                }

                // MARK: Account Section
                Section {
                    if auth.currentAppleUserID != nil {
                        LabeledContent("Signed in", value: "Apple ID")
                    }
                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                        dismiss()
                    }
                    Button("Reset Onboarding", role: .destructive) {
                        UserDefaults.standard.removeObject(forKey: "onboarding_complete")
                        onboardingVM.isOnboardingComplete = false
                    }
                    LabeledContent("Version", value: "1.0 (Build 1)")
                } header: {
                    Text("Account")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRepairSheet) {
                RepairSheet()
            }
            .sheet(isPresented: $showBreakGlassSheet) {
                BreakGlassView()
            }
            .alert("Unpair Partner?", isPresented: $showUnpairConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Unpair", role: .destructive) {
                    partnerVM.unpair()
                }
            } message: {
                Text("This will remove the shared encryption key. You'll need to re-pair with a new QR code. Break-Glass codes will stop working.")
            }
        }
    }
}

// MARK: - Goal Editor (inline in Settings)
private struct GoalEditorView: View {
    @Binding var target: Double
    @Binding var currency: GoalCurrency
    let hardCap: Double
    let recommendedTarget: Double
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Currency", selection: $currency) {
                ForEach(GoalCurrency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("\(Int(target))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(currency == .activeCalories ? "kcal" : "steps")
                    .foregroundColor(.secondary)
            }
            Slider(value: $target, in: 50...hardCap, step: 10)
                .tint(Color.electricOrange)
            Text("Recommended: \(Int(recommendedTarget)) · Max: \(Int(hardCap))")
                .font(.caption2)
                .foregroundColor(.secondary)

            HStack {
                Button("Cancel", action: onCancel)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Save Goal", action: onSave)
                    .fontWeight(.semibold)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Re-Pair Sheet
private struct RepairSheet: View {
    @EnvironmentObject var onboardingVM: OnboardingViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                StepHeader(title: "Re-Pair Device", subtitle: "Generate a new QR code or scan your partner's code.")
                PairingStepView()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - BreakGlassView.swift
struct BreakGlassView: View {
    @EnvironmentObject var policyVM: PolicyViewModel
    @EnvironmentObject var activityVM: ActivityViewModel
    @Environment(\.dismiss) var dismiss
    @State private var mode: BreakGlassMode = .enter

    enum BreakGlassMode { case enter, generate }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Picker("Mode", selection: $mode) {
                    Text("Enter Code").tag(BreakGlassMode.enter)
                    Text("Generate Code").tag(BreakGlassMode.generate)
                }.pickerStyle(.segmented).padding()

                if mode == .enter {
                    // Partner A — enter TOTP code
                    VStack(spacing: 16) {
                        Text("Enter the 6-digit code from your partner.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        TextField("000000", text: $policyVM.breakGlassCode)
                            .keyboardType(.numberPad)
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .multilineTextAlignment(.center)
                        if let error = policyVM.breakGlassError {
                            Text(error).foregroundColor(.red).font(.caption)
                        }
                        Button("Unlock (15 min)") {
                            Task { await policyVM.submitBreakGlassCode(activityVM: activityVM) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(policyVM.isValidatingCode || policyVM.breakGlassCode.count != 6)
                    }
                } else {
                    // Partner B — generate TOTP code
                    VStack(spacing: 16) {
                        Text("Share this code with your partner.")
                            .foregroundColor(.secondary)
                        Text(policyVM.generateCodeForPartner())
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundColor(Color.electricOrange)
                        Text("Expires in 30 seconds").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .navigationTitle("Break-Glass")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AuditLogView.swift
struct AuditLogView: View {
    @EnvironmentObject var partnerVM: PartnerViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Group {
                if partnerVM.auditLog.isEmpty {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "list.bullet.clipboard")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No events yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Shield engagements, break-glass overrides, and tamper detections will appear here.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.6))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                        Spacer()
                    }
                } else {
                    List(partnerVM.auditLog) { event in
                        HStack(spacing: 12) {
                            // Event type icon
                            Circle()
                                .fill(colorForEvent(event.eventType))
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(event.eventType.rawValue)
                                    .font(.caption.bold())
                                    .foregroundColor(colorForEvent(event.eventType))
                                Text(event.agentDisplayName)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(event.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .refreshable {
                        await partnerVM.refreshPartnerData()
                    }
                }
            }
            .navigationTitle("Audit Log")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    func colorForEvent(_ type: AuditEventType) -> Color {
        switch type {
        case .tamperHealthKit, .tamperScreenTime, .timeDrift: return .red
        case .breakGlass, .selfRegBypass: return .orange
        case .gracePeriod: return .yellow
        case .calorieUnlock, .stepUnlock, .shieldDisengaged: return .green
        default: return .secondary
        }
    }
}

// MARK: - Shared UI Components
struct StepHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.largeTitle.bold()).foregroundColor(.ink)
            Text(subtitle).font(.subheadline).foregroundColor(.muted).multilineTextAlignment(.center)
        }.padding(.top, 32)
    }
}

struct InfoCard: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundColor(.muted)
            Spacer()
            Text(value).foregroundColor(.ink).fontWeight(.medium)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

// PrimaryButton and SecondaryButton are defined in DesignSystem.swift
