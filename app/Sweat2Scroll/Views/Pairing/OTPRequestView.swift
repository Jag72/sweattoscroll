// OTPRequestView.swift — PRD §6B (user enters partner OTP to unlock apps)

import SwiftUI

struct OTPRequestView: View {
    var partnerName: String = "your partner"
    var onSuccess: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var digits = Array(repeating: "", count: 6)
    @State private var enteredCode = ""
    @State private var status: VerifyStatus = .idle
    @FocusState private var focusedField: Int?

    enum VerifyStatus { case idle, success, failure }

    // PRD §6B: accept "1234" dev code (matches OTPGeneratorView DEBUG output prefix)
    private func verify(_ code: String) {
        #if DEBUG
        let valid = code.hasPrefix("1234")
        #else
        // Production: validate against partner-generated TOTP (future CloudKit lookup)
        let valid = false
        #endif
        withAnimation {
            status = valid ? .success : .failure
        }
        if valid {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onSuccess?()
                dismiss()
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {

                VStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.electricOrange)
                    Text("Enter Unlock Code")
                        .font(.display(22))
                        .foregroundColor(.ink)
                    Text("Ask \(partnerName) to generate a 6-digit code and enter it below.")
                        .font(.bodyMedium(14))
                        .foregroundColor(.muted)
                        .multilineTextAlignment(.center)
                }

                // 6-digit OTP input boxes
                HStack(spacing: 10) {
                    ForEach(0..<6, id: \.self) { i in
                        OTPBox(
                            digit: $digits[i],
                            isFocused: focusedField == i,
                            status: status
                        )
                        .focused($focusedField, equals: i)
                        .onChange(of: digits[i]) { val in
                            if val.count > 1 {
                                digits[i] = String(val.last!)
                            }
                            if !val.isEmpty && i < 5 {
                                focusedField = i + 1
                            }
                            enteredCode = digits.joined()
                            if enteredCode.count == 6 {
                                verify(enteredCode)
                            }
                        }
                    }
                }
                .onAppear { focusedField = 0 }

                // Status feedback
                switch status {
                case .idle:
                    EmptyView()
                case .success:
                    Label("Correct! Unlocking…", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.emeraldGreen)
                        .font(.bodyMedium(15))
                        .transition(.opacity)
                case .failure:
                    VStack(spacing: 4) {
                        Label("Incorrect code. Try again.", systemImage: "xmark.circle.fill")
                            .foregroundColor(.rose)
                            .font(.bodyMedium(15))
                        Button("Clear") {
                            digits = Array(repeating: "", count: 6)
                            enteredCode = ""
                            withAnimation { status = .idle }
                            focusedField = 0
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.electricOrange)
                    }
                    .transition(.opacity)
                }

                Text("Note: Push notifications from your partner will be added in a future update.")
                    .font(.caption)
                    .foregroundColor(.muted)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(24)
            .background(Color.paper.ignoresSafeArea())
            .navigationTitle("Unlock Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Single digit box

private struct OTPBox: View {
    @Binding var digit: String
    var isFocused: Bool
    var status: OTPRequestView.VerifyStatus? = nil

    private var borderColor: Color {
        switch status {
        case .success: return .emeraldGreen
        case .failure: return .rose
        default: return isFocused ? .electricOrange : .ringTrack
        }
    }

    var body: some View {
        TextField("", text: $digit)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.system(size: 28, weight: .bold, design: .monospaced))
            .foregroundColor(.ink)
            .frame(width: 44, height: 56)
            .background(Color.white.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(borderColor, lineWidth: isFocused ? 2 : 1)
            )
    }
}

#Preview {
    OTPRequestView(partnerName: "Alex")
}
