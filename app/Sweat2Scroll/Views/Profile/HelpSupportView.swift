// Views/Profile/HelpSupportView.swift
// In-app Help & Support and Privacy Policy screens, presented as sheets
// from ProfileScreen's "About" group. Support complaints route to
// coppersmith2222@gmail.com. Web mirrors live at sweattoscroll.com.

import SwiftUI

// MARK: - Shared constants

enum SupportInfo {
    static let email          = "coppersmith2222@gmail.com"
    static let supportURL     = URL(string: "https://sweattoscroll.com/support.html")!
    static let privacyURL     = URL(string: "https://sweattoscroll.com/privacy.html")!
    static let githubIssues   = URL(string: "https://github.com/Jag72/sweattoscroll/issues")!

    static var mailtoURL: URL {
        URL(string: "mailto:\(email)?subject=Sweat2Scroll%20Support%20(v\(appVersion))")!
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Help & Support

struct HelpSupportView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {

                    // Contact card
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Contact Us", systemImage: "envelope.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.ink)
                        Text("Log complaints, report bugs, or ask questions. Include your iOS version and a screenshot if possible — we aim to reply within 48 hours.")
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                        Link(destination: SupportInfo.mailtoURL) {
                            Text(SupportInfo.email)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.electricOrange)
                                )
                        }
                        Link("Or open an issue on GitHub →", destination: SupportInfo.githubIssues)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.deepTeal)
                    }
                    .padding(16)
                    .background(cardShape)

                    // FAQ
                    Text("FREQUENTLY ASKED")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.muted)
                        .tracking(0.8)
                        .padding(.leading, 4)

                    faqItem(
                        q: "My apps didn't unlock after I hit my goal",
                        a: "Progress is re-checked about every 15 minutes in the background. Open the app to force an immediate check, and confirm Health access in Settings → Privacy & Security → Health → Sweat2Scroll."
                    )
                    faqItem(
                        q: "I deleted the app but apps are still blocked",
                        a: "iOS removes all shields automatically when the app is deleted. If a rare iOS bug leaves one behind: reinstall and toggle the shield off, or turn Screen Time off and on in Settings, or restart your iPhone."
                    )
                    faqItem(
                        q: "What is Break-Glass?",
                        a: "An emergency override held by your accountability partner. Enter their current 6-digit code to unlock apps for 15 minutes. Every use is recorded in your signed audit log."
                    )
                    faqItem(
                        q: "My step or calorie data looks wrong",
                        a: "Sweat2Scroll mirrors Apple Health. If data is missing in the Health app it will be missing here. An Apple Watch gives the most accurate calories, HRV, and sleep data."
                    )
                    faqItem(
                        q: "Does my health data leave my phone?",
                        a: "No. All fitness data is processed in-memory, on-device. There are no Sweat2Scroll servers. See the Privacy Policy for details."
                    )
                    faqItem(
                        q: "How do I delete my data?",
                        a: "Sign out and delete the app to remove local data. For CloudKit records, email us with subject \"Data deletion\" or manage storage in Settings → Apple ID → iCloud."
                    )

                    // Version card
                    Text("ABOUT THIS VERSION")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.muted)
                        .tracking(0.8)
                        .padding(.leading, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        versionRow("Version", "\(SupportInfo.appVersion) (\(SupportInfo.buildNumber))")
                        Divider()
                        versionRow("Released", "July 2026")
                        Divider()
                        versionRow("Requires", "iOS 16.0 or later")
                        Divider()
                        Text("v1.0 — Initial release. Fitness-gated app blocking with HealthKit goals, Screen Time shields, on-device OPA/WASM policy engine, partner accountability with Break-Glass, and wellness dashboards.")
                            .font(.system(size: 12))
                            .foregroundColor(.muted)
                            .padding(.top, 2)
                    }
                    .padding(16)
                    .background(cardShape)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Help & Support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.electricOrange)
                }
            }
        }
    }

    private var cardShape: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.04), radius: 10, y: 2)
    }

    private func faqItem(q: String, a: String) -> some View {
        DisclosureGroup {
            Text(a)
                .font(.system(size: 13))
                .foregroundColor(.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } label: {
            Text(q)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.ink)
                .multilineTextAlignment(.leading)
        }
        .tint(.muted)
        .padding(14)
        .background(cardShape)
    }

    private func versionRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ink)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.muted)
        }
    }
}

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    // Summary banner
                    VStack(alignment: .leading, spacing: 8) {
                        Label("The Short Version", systemImage: "lock.shield.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.deepTeal)
                        Text("Your health data never leaves your phone. No servers, no analytics, no ads, nothing to sell. The only cloud storage is your own private iCloud container, which we cannot access.")
                            .font(.system(size: 13))
                            .foregroundColor(.muted)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.deepTeal.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.deepTeal.opacity(0.2), lineWidth: 1)
                            )
                    )

                    policySection("Data We Read",
                        "With your HealthKit authorization we read steps, active calories, workouts, heart rate, HRV, resting heart rate, respiratory rate, and sleep stages. This is processed in-memory on your device, never written to disk, and never transmitted anywhere.")

                    policySection("Data We Store",
                        "Your goal settings and blocked-app selections (opaque Apple tokens — we can't see which apps they are) stay on your device. Your partner-pairing contract and audit log live in your private CloudKit container, which belongs to your Apple ID.")

                    policySection("Screen Time Data",
                        "Blocking uses Apple's FamilyControls framework. We only receive anonymous tokens — never app names, usage history, or browsing activity. iOS automatically removes all shields if you delete the app.")

                    policySection("What We Don't Do",
                        "No selling or sharing of data. No advertising or tracking. No third-party analytics SDKs. No servers. HealthKit data is never used for marketing.")

                    policySection("Security",
                        "Partner pairing uses ECDH P-256 key exchange. Break-Glass codes are single-use TOTP (RFC 6238). Audit-log entries are cryptographically signed.")

                    policySection("Deletion",
                        "Deleting the app removes all local data. CloudKit records can be removed in Settings → Apple ID → iCloud, or by emailing a deletion request.")

                    policySection("Contact",
                        "Privacy questions or complaints: \(SupportInfo.email)")

                    Link("Read the full policy at sweattoscroll.com →", destination: SupportInfo.privacyURL)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.electricOrange)
                        .padding(.top, 4)

                    Text("Effective July 20, 2026 · Sweat2Scroll v\(SupportInfo.appVersion)")
                        .font(.system(size: 11))
                        .foregroundColor(.muted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundColor(.electricOrange)
                }
            }
        }
    }

    private func policySection(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.ink)
                .tracking(0.8)
            Text(body)
                .font(.system(size: 13))
                .foregroundColor(.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 10, y: 2)
        )
    }
}

#Preview("Help & Support") { HelpSupportView() }
#Preview("Privacy Policy") { PrivacyPolicyView() }
