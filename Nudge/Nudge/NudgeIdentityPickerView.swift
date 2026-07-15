//
//  NudgeIdentityPickerView.swift
//  Nudge
//

import SwiftUI

struct NudgeIdentityPickerView: View {
    let onFinish: () -> Void

    @State private var name: String = NudgeIdentity.shared.current ?? ""
    @State private var error: String?

    private var cleaned: String {
        NudgeIdentity.sanitize(name)
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Welcome to Nudge")
                    .font(.title2.weight(.semibold))
                Text("What's your name?")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 10) {
                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body))
                    .onSubmit(confirm)
                if let err = error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 40)

            Button(action: confirm) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .disabled(!NudgeIdentity.isValid(cleaned))

            Spacer()

            Text("Your teammates will see this name on their notch when you nudge them. You can change it later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 400, height: 600)
    }

    private func confirm() {
        guard NudgeIdentity.isValid(cleaned) else {
            error = "Please enter a name (1–\(nudgeMaxNameLength) characters, no colons)."
            return
        }
        NudgeIdentity.shared.setCurrent(cleaned)
        Task {
            await NudgeNotifier.requestAuthorization()
        }
        onFinish()
    }
}
