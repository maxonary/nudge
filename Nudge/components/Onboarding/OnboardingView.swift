//
//  OnboardingView.swift
//  Nudge
//

import SwiftUI

enum OnboardingStep {
    case identity
    case password
    case finished
}

struct OnboardingView: View {
    @State var step: OnboardingStep = .identity
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .identity:
                NudgeIdentityPickerView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        step = .password
                    }
                }
                .transition(.opacity)
            case .password:
                NudgePasswordPickerView {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        step = .finished
                    }
                }
                .transition(.opacity)
            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }
}
