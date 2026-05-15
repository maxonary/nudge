//
//  NudgeIdentityPickerView.swift
//  Nudge
//

import SwiftUI

struct NudgeIdentityPickerView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Welcome to Nudge")
                    .font(.title2.weight(.semibold))
                Text("Who are you?")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)

            VStack(spacing: 12) {
                ForEach(nudgeUsers, id: \.self) { user in
                    Button {
                        pick(user)
                    } label: {
                        HStack {
                            Text(user)
                                .font(.system(size: 18, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            Text("You can change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
        .frame(width: 400, height: 600)
    }

    private func pick(_ user: String) {
        NudgeIdentity.shared.setCurrent(user)
        Task {
            await NudgeNotifier.requestAuthorization()
        }
        // firstLaunch flips to false only after the team password is
        // also set (in NudgePasswordPickerView).
        onFinish()
    }
}
