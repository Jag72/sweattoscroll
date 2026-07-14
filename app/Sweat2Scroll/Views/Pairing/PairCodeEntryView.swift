// Views/Pairing/PairCodeEntryView.swift

import SwiftUI

struct PairCodeEntryView: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var digits = ["", "", "", "", "", ""]
    @FocusState private var focusIndex: Int?
    @State private var status: Status = .idle
    @State private var isSubmitting = false

    private enum Status: Equatable {
        case idle, success, error(String)
    }

    var body: some View {
        VStack(spacing: 28) {
            Text("Enter 6-digit code")
                .font(.display(22))
                .padding(.top, 32)

            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { i in
                    TextField("", text: Binding(
                        get: { digits[i] },
                        set: { new in
                            let v = new.filter(\.isNumber).prefix(1)
                            digits[i] = String(v)
                            if !v.isEmpty, i < 5 { focusIndex = i + 1 }
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.display(24))
                    .frame(width: 44, height: 52)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ringTrack, lineWidth: 2))
                    .focused($focusIndex, equals: i)
                }
            }

            switch status {
            case .idle:
                EmptyView()
            case .success:
                Label("Paired!", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.emeraldGreen)
            case .error(let msg):
                Text(msg).font(.caption).foregroundColor(.rose)
            }

            Button(action: submit) {
                if isSubmitting { ProgressView() }
                else { Text("Pair") }
            }
            .buttonStyle(.borderedProminent)
            .tint(.electricOrange)
            .disabled(isSubmitting || codeString.count != 6)

            Button("Cancel") { dismiss() }
                .foregroundColor(.muted)

            Spacer()
        }
        .padding()
        .onAppear { focusIndex = 0 }
    }

    private var codeString: String { digits.joined() }

    private func submit() {
        guard let uid = auth.currentAppleUserID else { return }
        isSubmitting = true
        status = .idle
        Task {
            do {
                let result = try await PairingService.shared.validateAndPair(
                    code: codeString,
                    userAppleUserID: uid,
                    userDisplayName: auth.userDisplayName)
                await MainActor.run {
                    isSubmitting = false
                    switch result {
                    case .success:
                        status = .success
                        Task {
                            await auth.refreshAfterPairing()
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            await MainActor.run { dismiss() }
                        }
                    case .invalid:
                        status = .error("Invalid code.")
                    case .expired:
                        status = .error("Code expired. Ask for a new one.")
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    status = .error(error.localizedDescription)
                }
            }
        }
    }
}
