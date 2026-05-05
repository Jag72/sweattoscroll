// ViewModels/OnboardingViewModel.swift
// Manages the multi-step onboarding flow:
// Step 1: Profile (HealthKit biometrics)
// Step 2: Goal setup (currency, target, hard cap display)
// Step 3: App curation (FamilyActivityPicker — up to 10 apps)
// Step 4: Device pairing (QR code or iMessage link)
// Step 5: Governance contract formation

import Foundation
import FamilyControls
import AVFoundation
import CryptoKit

@MainActor
class OnboardingViewModel: ObservableObject {

    // MARK: - Step Tracking
    enum OnboardingStep: Int, CaseIterable {
        case welcome = 0
        case profile
        case goalSetup
        case appCuration
        case pairing
        case contractReview
        case complete
    }

    @Published var currentStep: OnboardingStep = .welcome
    @Published var isOnboardingComplete: Bool = false
    @Published var userProfile: UserProfile = .placeholder
    @Published var activityGoal: ActivityGoal = .placeholder
    @Published var activitySelection: FamilyActivitySelection = FamilyActivitySelection()
    @Published var pairingMethod: PairingMethod = .qrCode
    @Published var qrCodeData: String = ""
    @Published var governanceContract: GovernanceContract?
    @Published var errorMessage: String?

    // MARK: - Pairing State
    enum PairingRole { case initiator, joiner }
    @Published var pairingRole: PairingRole = .initiator
    @Published var isPairingComplete: Bool = false
    @Published var isPairingInProgress: Bool = false
    @Published var isWaitingForPartner: Bool = false
    @Published var showScanner: Bool = false
    @Published var showShareSheet: Bool = false
    @Published var partnerDisplayName: String = ""
    @Published var pairingURL: URL?

    /// The ephemeral ECDH key pair generated for this pairing session.
    /// The private key is kept in memory only — never persisted.
    private var ephemeralPrivateKey: P256.KeyAgreement.PrivateKey?
    private var localUserID: String = UUID().uuidString
    private var pollingTask: Task<Void, Never>?

    // MARK: - Persistence key
    private let completedKey = "onboarding_complete"

    init() {
        isOnboardingComplete = UserDefaults.standard.bool(forKey: completedKey)
    }

    // MARK: - Navigation
    func advance() {
        let steps = OnboardingStep.allCases
        guard let index = steps.firstIndex(of: currentStep),
              index + 1 < steps.count else { return }
        currentStep = steps[index + 1]
    }

    func back() {
        let steps = OnboardingStep.allCases
        guard let index = steps.firstIndex(of: currentStep), index > 0 else { return }
        currentStep = steps[index - 1]
    }

    // MARK: - Goal Setup
    func updateGoal(target: Double) {
        let (isValid, reason) = CalorieEngine.validate(target: target, for: userProfile)
        if isValid {
            activityGoal.agreedTarget = target
        } else {
            errorMessage = reason
        }
    }

    // MARK: - App Selection (max 10 apps)
    func confirmAppSelection(_ selection: FamilyActivitySelection) {
        activitySelection = ScreenTimeService.shared.saveSelection(selection)
    }

    // MARK: - QR Code Generation (Initiator — Device A)
    /// Generates an ECDH key pair and encodes the public key + metadata as a QR code payload.
    /// The partner scans this QR code, performs their side of the ECDH exchange, and
    /// responds with their public key (via CloudKit or iMessage link).
    func generatePairingQRCode() -> String {
        pairingRole = .initiator

        // Generate a fresh ephemeral ECDH key pair for this pairing session
        let privateKey = P256.KeyAgreement.PrivateKey()
        ephemeralPrivateKey = privateKey
        let publicKey = privateKey.publicKey

        // Build the QR code payload
        let payload = PairingQRPayload(
            app: "sweat2scroll",
            version: "1.0",
            userID: localUserID,
            displayName: userProfile.displayName,
            publicKey: publicKey.rawRepresentation.base64EncodedString(),
            goalCurrency: activityGoal.currency.codeName,
            dailyTarget: activityGoal.agreedTarget,
            hardCap: activityGoal.hardCap
        )

        // Encode to JSON
        qrCodeData = (try? JSONEncoder().encode(payload)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? ""

        return qrCodeData
    }

    // MARK: - iMessage Pairing Link (Initiator — Device A, remote)
    /// Generates the same ECDH key pair as the QR flow, but encodes the payload
    /// as a Universal Link URL that can be shared via iMessage.
    /// The partner taps the link → app opens → handleScannedQRCode runs.
    func generatePairingLink() -> URL? {
        // Reuse the QR code generation to create the ECDH key pair + payload
        let jsonPayload = generatePairingQRCode()
        guard !jsonPayload.isEmpty else { return nil }

        let url = DeepLinkService.constructPairingURL(from: jsonPayload)
        pairingURL = url
        pairingMethod = .iMessageLink
        return url
    }

    /// Constructs the share items for UIActivityViewController / ShareLink.
    func iMessageShareItems() -> [Any] {
        guard let url = pairingURL else { return [] }
        let message = DeepLinkService.constructiMessageBody(
            from: url,
            displayName: userProfile.displayName
        )
        return [message]
    }

    // MARK: - Handle Incoming Universal Link (Joiner — Device B)
    /// Called from the app's onOpenURL handler when a pairing link is tapped.
    /// Decodes the payload and runs the same ECDH exchange as the QR scanner.
    func handleIncomingPairingURL(_ url: URL) {
        guard DeepLinkService.isPairingURL(url) else {
            errorMessage = "Not a valid Sweat2Scroll link."
            return
        }

        guard let jsonPayload = DeepLinkService.parsePairingURL(url) else {
            errorMessage = "Could not decode pairing link. It may have expired or been corrupted."
            return
        }

        // Set role to joiner and run the same exchange
        pairingRole = .joiner
        pairingMethod = .iMessageLink
        handleScannedQRCode(jsonPayload)
    }

    // MARK: - QR Code Scanning (Joiner — Device B)
    /// Called when Device B scans Device A's QR code.
    /// Performs the ECDH key exchange, derives the shared secret, stores it,
    /// and creates the governance contract.
    func handleScannedQRCode(_ scannedData: String) {
        isPairingInProgress = true
        errorMessage = nil

        guard let data = scannedData.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PairingQRPayload.self, from: data) else {
            errorMessage = "Invalid QR code. Make sure your partner is showing a Sweat2Scroll pairing code."
            isPairingInProgress = false
            return
        }

        // Validate app identifier
        guard payload.app == "sweat2scroll" else {
            errorMessage = "This QR code is not from Sweat2Scroll."
            isPairingInProgress = false
            return
        }

        // Decode partner's public key
        guard let partnerKeyData = Data(base64Encoded: payload.publicKey) else {
            errorMessage = "Could not decode partner's public key."
            isPairingInProgress = false
            return
        }

        do {
            // Perform ECDH key exchange — derives and stores shared secret in Keychain
            let myPublicKeyData = try TOTPService.performECDHExchange(withPartnerPublicKeyData: partnerKeyData)

            // Get the shared secret fingerprint for the governance contract
            let fingerprint = try TOTPService.fingerprint()

            // Create the governance contract
            let contract = GovernanceContract(
                controlledUserID: localUserID,
                controlledDisplayName: userProfile.displayName,
                controllerUserID: payload.userID,
                controllerDisplayName: payload.displayName,
                goalCurrency: GoalCurrency.fromCodeName(payload.goalCurrency),
                agreedDailyTarget: payload.dailyTarget,
                hardCap: payload.hardCap,
                pairedAt: Date(),
                sharedSecretFingerprint: fingerprint
            )

            governanceContract = contract
            partnerDisplayName = payload.displayName
            pairingRole = .joiner

            // Send our public key back to Device A via CloudKit
            let response = PairingResponse.create(
                initiatorUserID: payload.userID,
                responderUserID: localUserID,
                responderDisplayName: userProfile.displayName,
                responderPublicKey: myPublicKeyData.base64EncodedString(),
                goalCurrency: payload.goalCurrency,
                agreedTarget: payload.dailyTarget,
                fingerprint: fingerprint
            )

            Task {
                do {
                    try await CloudKitService.shared.sendPairingResponse(response)
                    isPairingComplete = true
                    print("[Pairing] ECDH exchange complete. Response sent to Device A.")
                } catch {
                    errorMessage = "Paired locally, but failed to notify partner: \(error.localizedDescription)"
                    // Still mark as complete — the ECDH exchange itself succeeded
                    isPairingComplete = true
                }
            }

        } catch {
            errorMessage = "Pairing failed: \(error.localizedDescription)"
        }

        isPairingInProgress = false
    }

    // MARK: - Complete Pairing for Initiator (Device A)
    /// Called when Device A receives Device B's public key response.
    /// Completes the ECDH exchange on the initiator's side.
    func completePairingAsInitiator(partnerPublicKeyBase64: String, partnerUserID: String, partnerDisplayName: String) {
        isPairingInProgress = true
        errorMessage = nil

        guard let partnerKeyData = Data(base64Encoded: partnerPublicKeyBase64) else {
            errorMessage = "Invalid partner key data."
            isPairingInProgress = false
            return
        }

        do {
            // Perform ECDH on initiator side
            _ = try TOTPService.performECDHExchange(withPartnerPublicKeyData: partnerKeyData)
            let fingerprint = try TOTPService.fingerprint()

            let contract = GovernanceContract(
                controlledUserID: localUserID,
                controlledDisplayName: userProfile.displayName,
                controllerUserID: partnerUserID,
                controllerDisplayName: partnerDisplayName,
                goalCurrency: activityGoal.currency,
                agreedDailyTarget: activityGoal.agreedTarget,
                hardCap: activityGoal.hardCap,
                pairedAt: Date(),
                sharedSecretFingerprint: fingerprint
            )

            governanceContract = contract
            self.partnerDisplayName = partnerDisplayName
            isPairingComplete = true

            print("[Pairing] Initiator ECDH complete. Fingerprint: \(fingerprint)")
        } catch {
            errorMessage = "Pairing failed: \(error.localizedDescription)"
        }

        isPairingInProgress = false
    }

    // MARK: - Start Polling for Partner Response (Device A)
    /// Called after Device A generates and displays the QR code.
    /// Polls CloudKit every 3 seconds for up to 10 minutes, waiting for Device B's response.
    func startPollingForResponse() {
        guard pairingRole == .initiator else { return }
        stopPolling()
        isWaitingForPartner = true

        pollingTask = Task { [weak self] in
            let maxAttempts = 200      // 200 × 3s = 10 minutes
            var attempt = 0

            while attempt < maxAttempts, !Task.isCancelled {
                attempt += 1

                if let response = await CloudKitService.shared.pollForPairingResponse(
                    initiatorUserID: self?.localUserID ?? ""
                ) {
                    // Found a response — complete the ECDH exchange on Device A's side
                    await MainActor.run {
                        self?.completePairingAsInitiator(
                            partnerPublicKeyBase64: response.responderPublicKey,
                            partnerUserID: response.responderUserID,
                            partnerDisplayName: response.responderDisplayName
                        )
                        self?.isWaitingForPartner = false
                    }

                    // Clean up the pairing response record
                    await CloudKitService.shared.deletePairingResponse(
                        initiatorUserID: self?.localUserID ?? ""
                    )
                    return
                }

                // Wait 3 seconds before next poll
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }

            // Timed out after 10 minutes
            await MainActor.run {
                self?.isWaitingForPartner = false
                self?.errorMessage = "Partner didn't respond within 10 minutes. Try generating a new code."
            }
        }
    }

    /// Stops the active polling task.
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isWaitingForPartner = false
    }

    // MARK: - Complete Onboarding
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: completedKey)
        isOnboardingComplete = true
        ScreenTimeService.shared.startDailyMonitoring()
    }
}

// MARK: - Pairing QR Code Payload
/// The JSON payload encoded in the QR code during device pairing.
/// Contains the ECDH public key and goal parameters for contract formation.
struct PairingQRPayload: Codable {
    let app: String                 // "sweat2scroll" — validates the QR belongs to this app
    let version: String             // Protocol version for forward compatibility
    let userID: String              // Unique device/user identifier
    let displayName: String         // Human-readable name for the governance contract
    let publicKey: String           // Base64-encoded P256 ECDH public key (raw representation)
    let goalCurrency: String        // "activeCalories" or "steps"
    let dailyTarget: Double         // Agreed daily target
    let hardCap: Double             // CDC safety cap for age cohort
}

// MARK: - PolicyViewModel.swift
// Exposes the current OPA policy state and override controls to the UI.
@MainActor
class PolicyViewModel: ObservableObject {
    @Published var currentResult: PolicyResult = .denied
    @Published var overrideState: OverrideState = .inactive
    @Published var breakGlassCode: String = ""
    @Published var breakGlassError: String?
    @Published var isValidatingCode: Bool = false

    func submitBreakGlassCode(activityVM: ActivityViewModel) async {
        isValidatingCode = true
        breakGlassError = nil
        let success = await activityVM.validateBreakGlassCode(breakGlassCode)
        if !success {
            breakGlassError = "Invalid or expired code. Ask your partner to regenerate."
        }
        breakGlassCode = ""
        isValidatingCode = false
    }

    func generateCodeForPartner() -> String {
        return (try? TOTPService.generateCode()) ?? "------"
    }
}

// MARK: - PartnerViewModel.swift
// Manages the peer-to-peer partner connection and progress monitoring.
@MainActor
class PartnerViewModel: ObservableObject {
    @Published var partnerDisplayName: String = "Partner"
    @Published var partnerCalories: Double = 0
    @Published var partnerSteps: Int = 0
    @Published var partnerGoal: Double = 300
    @Published var partnerGoalCurrency: GoalCurrency = .activeCalories
    @Published var isPartnerPaired: Bool = false
    @Published var contract: GovernanceContract?
    @Published var auditLog: [AuditEvent] = []
    @Published var lastPartnerSync: Date?
    @Published var isSyncing: Bool = false

    private let cloudKit = CloudKitService.shared
    private let contractKey = "governance_contract"

    var partnerProgressFraction: Double {
        guard partnerGoal > 0 else { return 0 }
        switch partnerGoalCurrency {
        case .activeCalories:
            return min(partnerCalories / partnerGoal, 1.0)
        case .steps:
            return min(Double(partnerSteps) / partnerGoal, 1.0)
        }
    }

    /// One-line progress for UI (Home / dashboard partner cards).
    var partnerProgressSummaryLine: String {
        let current = partnerGoalCurrency == .activeCalories ? Int(partnerCalories) : partnerSteps
        let unit = partnerGoalCurrency == .activeCalories ? "kcal" : "steps"
        let met = partnerProgressFraction >= 1.0 ? "Goal met" : "In progress"
        return "\(current) / \(Int(partnerGoal)) \(unit) • \(met)"
    }

    /// True if partner data is older than 10 minutes
    var isPartnerDataStale: Bool {
        guard let lastSync = lastPartnerSync else { return true }
        return Date().timeIntervalSince(lastSync) > 600
    }

    // MARK: - Initialize from Persisted Contract
    func loadPersistedState() async {
        // Try loading contract from CloudKit first, fall back to UserDefaults cache
        if let cloudContract = await cloudKit.loadContract() {
            applyContract(cloudContract)
        } else if let data = UserDefaults.standard.data(forKey: contractKey),
                  let cached = try? JSONDecoder().decode(GovernanceContract.self, from: data) {
            applyContract(cached)
        }
    }

    // MARK: - Apply Contract (sets partner state from contract)
    func applyContract(_ newContract: GovernanceContract) {
        contract = newContract
        partnerDisplayName = newContract.controllerDisplayName
        partnerGoal = newContract.agreedDailyTarget
        partnerGoalCurrency = newContract.goalCurrency
        isPartnerPaired = true

        // Cache locally for fast cold start
        if let encoded = try? JSONEncoder().encode(newContract) {
            UserDefaults.standard.set(encoded, forKey: contractKey)
        }
    }

    // MARK: - Refresh Partner Data (CloudKit fetch)
    func refreshPartnerData() async {
        isSyncing = true

        // 1. Load contract if we don't have one yet
        if contract == nil {
            await loadPersistedState()
        }

        // 2. Fetch partner's live progress from CloudKit
        if let progress = await cloudKit.fetchPartnerProgress() {
            partnerCalories = progress.calories
            partnerSteps = progress.steps
            partnerGoal = progress.goal
            partnerGoalCurrency = GoalCurrency(rawValue: progress.currency) ?? .activeCalories
            lastPartnerSync = progress.lastUpdated
        }

        // 3. Refresh audit log
        await cloudKit.fetchAuditLog()
        auditLog = cloudKit.auditLog

        isSyncing = false
    }

    // MARK: - Save New Contract (after pairing completes)
    func saveContract(_ newContract: GovernanceContract) async {
        applyContract(newContract)
        await cloudKit.saveContract(newContract)
        // Register the tamper-alert CKDatabaseSubscription now that we have a partner.
        // Idempotent — safe to call multiple times.
        await cloudKit.setupTamperAlertSubscription()
    }

    // MARK: - Unpair
    func unpair() {
        contract = nil
        isPartnerPaired = false
        partnerDisplayName = "Partner"
        partnerCalories = 0
        partnerSteps = 0
        partnerGoal = 300
        lastPartnerSync = nil
        UserDefaults.standard.removeObject(forKey: contractKey)
    }
}
