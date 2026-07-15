//
//  NudgePasswordPickerView.swift
//  Nudge
//

import SwiftUI

struct NudgePasswordPickerView: View {
    let onFinish: () -> Void

    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @State private var error: String?

    private var trimmed: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Team password")
                    .font(.title2.weight(.semibold))
                Text("Everyone on your team types the same password.\nIt encrypts your pings and decides who can reach you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 40)

            VStack(spacing: 10) {
                HStack {
                    Group {
                        if showPassword {
                            TextField("Team password", text: $password)
                        } else {
                            SecureField("Team password", text: $password)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit(confirm)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(showPassword ? "Hide password" : "Show password")
                }
                if let err = error {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 40)

            Button(action: confirm) {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .disabled(trimmed.count < 6)

            Spacer()

            Text("Stored only in your Mac's Keychain — never sent over the network. Change it any time in Settings.")
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
        if trimmed.count < 6 {
            error = "Please use at least 6 characters."
            return
        }
        NudgeTeamSecret.shared.setPassword(trimmed)
        NudgeViewCoordinator.shared.firstLaunch = false
        onFinish()
    }
}
