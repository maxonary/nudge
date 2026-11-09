import SwiftUI

@MainActor
struct AgentAttentionView: View {
    @ObservedObject var center: AgentAttentionCenter
    let focusController: AgentPanelFocusController

    @FocusState private var freeformFocused: Bool
    @State private var textEntryActive = false

    var body: some View {
        Group {
            if center.state.visible {
                switch center.state.activeRequest {
                case let .question(questionSet):
                    questionView(questionSet)
                case let .approval(approval):
                    approvalView(approval)
                case nil:
                    if let completion = center.state.completion {
                        completionView(completion)
                    }
                }
            }
        }
        .onDisappear {
            endTextEntry()
            focusController.restorePreviousApplication()
        }
    }

    @ViewBuilder
    private func questionView(_ questionSet: AgentQuestionSet) -> some View {
        if questionSet.questions.indices.contains(center.state.questionIndex) {
            let index = center.state.questionIndex
            let question = questionSet.questions[index]

            VStack(alignment: .leading, spacing: 8) {
                header(eyebrow: sourceName, title: questionSet.header) {
                    HStack(spacing: 8) {
                        handoffButton()
                        questionDots(questionSet)
                    }
                }

                Text(question.prompt)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                if !question.choices.isEmpty {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 7
                    ) {
                        ForEach(question.choices, id: \.label) { choice in
                            optionButton(choice, question: question, index: index)
                        }
                    }
                }

                HStack(spacing: 8) {
                    TextField("Eigene Antwort…", text: freeformBinding(at: index))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .focused($freeformFocused)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(controlBackground(isSelected: isTextDraft(at: index)))
                        .overlay(controlBorder(isSelected: isTextDraft(at: index)))
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if !isTextDraft(at: index) {
                                    center.answer(.text(""), at: index)
                                }
                                startTextEntry()
                                freeformFocused = true
                            }
                        )
                        .onChange(of: freeformFocused) { _, focused in
                            if focused {
                                startTextEntry()
                            } else {
                                endTextEntry()
                            }
                        }
                        .accessibilityLabel("Eigene Antwort für Frage \(index + 1)")

                    if index == questionSet.questions.index(before: questionSet.questions.endIndex) {
                        Button("Antworten") {
                            endTextEntry()
                            center.submitQuestion()
                            focusController.restorePreviousApplication()
                        }
                        .agentPrimaryButton()
                        .disabled(center.state.answersForSubmission() == nil)
                        .accessibilityLabel("Alle Antworten senden")
                    } else {
                        Button("Weiter") {
                            endTextEntry()
                            center.moveQuestion(to: index + 1)
                        }
                        .agentPrimaryButton()
                        .disabled(!isDraftValid(question: question, at: index))
                        .accessibilityLabel("Zur nächsten Frage")
                    }
                }
            }
        }
    }

    private func optionButton(
        _ choice: AgentQuestionChoice,
        question: AgentQuestion,
        index: Int
    ) -> some View {
        let selected = isSelected(choice.label, question: question, at: index)
        return Button {
            endTextEntry()
            if question.multiSelect {
                toggle(choice.label, question: question, at: index)
            } else {
                center.answer(.single(choice.label), at: index)
                if case let .question(questionSet) = center.state.activeRequest,
                   index < questionSet.questions.count - 1 {
                    center.moveQuestion(to: index + 1)
                }
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selectionSymbol(selected: selected, multiple: question.multiSelect))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.effectiveAccent : .white.opacity(0.6))
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(choice.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !choice.description.isEmpty {
                        Text(choice.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(controlBackground(isSelected: selected))
            .overlay(controlBorder(isSelected: selected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(choice.label). \(choice.description)")
        .accessibilityValue(selected ? "Ausgewählt" : "Nicht ausgewählt")
    }

    private func questionDots(_ questionSet: AgentQuestionSet) -> some View {
        HStack(spacing: 7) {
            ForEach(questionSet.questions.indices, id: \.self) { index in
                Button {
                    endTextEntry()
                    center.moveQuestion(to: index)
                } label: {
                    Circle()
                        .fill(index == center.state.questionIndex
                            ? Color.effectiveAccent
                            : Color.white.opacity(0.28))
                        .frame(width: index == center.state.questionIndex ? 8 : 6,
                               height: index == center.state.questionIndex ? 8 : 6)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Frage \(index + 1) bearbeiten")
                .accessibilityValue(index == center.state.questionIndex ? "Aktuell" : "")
            }
        }
    }

    private func approvalView(_ approval: AgentApproval) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(eyebrow: sourceName, title: "\(approval.toolName) möchte Zugriff") {
                handoffButton()
            }

            Text(approval.detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            if let locationContext {
                Label(locationContext, systemImage: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let command = approval.command, !command.isEmpty {
                Text(command)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button("Ablehnen") {
                    center.resolveApproval(.denied)
                }
                .agentSecondaryButton()
                .accessibilityLabel("Anfrage ablehnen")

                Button("Einmal erlauben") {
                    center.resolveApproval(.approvedOnce)
                }
                .agentPrimaryButton()
                .accessibilityLabel("Einmal erlauben")

                if approval.source == .claudeCode && approval.allowsClaudeSessionRule {
                    Button("Für Session") {
                        center.resolveApproval(.approvedForSession)
                    }
                    .agentSecondaryButton()
                    .accessibilityLabel("Für diese Claude-Code-Session erlauben")
                }
            }
        }
    }

    private func completionView(_ completion: AgentCompletion) -> some View {
        Button {
            center.jumpOrHandoff()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                header(eyebrow: sourceName, title: completion.title)

                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.effectiveAccent.opacity(0.2))
                            .frame(width: 42, height: 42)
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color.effectiveAccent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        if let message = completion.message, !message.isEmpty {
                            Text(message)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(2)
                        }
                        Text(completion.context)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                        if let locationContext, locationContext != completion.context {
                            Label(locationContext, systemImage: "folder")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 5) {
                        Text(jumpLabel)
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(completion.title). \(jumpLabel)")
    }

    private func handoffButton() -> some View {
        Button {
            endTextEntry()
            // Clear any stored focus restoration before requesting the origin app.
            focusController.restorePreviousApplication()
            center.jumpOrHandoff()
        } label: {
            HStack(spacing: 4) {
                Text(jumpLabel)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(jumpLabel). Anfrage im Agent fortsetzen")
    }

    private func header<Trailing: View>(
        eyebrow: String,
        title: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Text(eyebrow.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: true, vertical: false)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func header(eyebrow: String, title: String) -> some View {
        header(eyebrow: eyebrow, title: title) { EmptyView() }
    }

    private var sourceName: String {
        switch center.presentedEnvelope?.source {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case nil:
            return "Agent"
        }
    }

    private var jumpLabel: String {
        guard let host = center.presentedEnvelope?.host else { return "Zum Agent" }
        return center.jumpLabel(for: host)
    }

    private var locationContext: String? {
        guard let envelope = center.presentedEnvelope else { return nil }
        if let project = envelope.project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            return project
        }

        let cwd = envelope.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        return cwd.isEmpty ? nil : cwd
    }

    private func freeformBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard center.state.drafts.indices.contains(index),
                      case let .text(text)? = center.state.drafts[index] else {
                    return ""
                }
                return text
            },
            set: { center.answer(.text($0), at: index) }
        )
    }

    private func isTextDraft(at index: Int) -> Bool {
        guard center.state.drafts.indices.contains(index),
              case .text? = center.state.drafts[index] else {
            return false
        }
        return true
    }

    private func isSelected(_ label: String, question: AgentQuestion, at index: Int) -> Bool {
        guard center.state.drafts.indices.contains(index), let draft = center.state.drafts[index] else {
            return false
        }
        switch draft {
        case let .single(selected):
            return !question.multiSelect && selected == label
        case let .multiple(selected):
            return question.multiSelect && selected.contains(label)
        case .text:
            return false
        }
    }

    private func toggle(_ label: String, question: AgentQuestion, at index: Int) {
        let existing: [String]
        if center.state.drafts.indices.contains(index),
           case let .multiple(labels)? = center.state.drafts[index] {
            existing = labels
        } else {
            existing = []
        }

        let selected = Set(existing)
        let updated = question.choices.compactMap { choice -> String? in
            if choice.label == label {
                return selected.contains(label) ? nil : label
            }
            return selected.contains(choice.label) ? choice.label : nil
        }
        center.answer(.multiple(updated), at: index)
    }

    private func isDraftValid(question: AgentQuestion, at index: Int) -> Bool {
        guard center.state.drafts.indices.contains(index), let draft = center.state.drafts[index] else {
            return false
        }
        switch draft {
        case let .single(label):
            return question.choices.contains(where: { $0.label == label })
        case let .multiple(labels):
            return !labels.isEmpty
        case let .text(text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func endTextEntry() {
        guard textEntryActive else { return }
        textEntryActive = false
        freeformFocused = false
        center.endEditing()
        focusController.endTextEntry()
    }

    private func startTextEntry() {
        guard !textEntryActive else { return }
        textEntryActive = true
        focusController.beginTextEntry()
        center.beginEditing()
    }

    private func selectionSymbol(selected: Bool, multiple: Bool) -> String {
        if multiple {
            return selected ? "checkmark.square.fill" : "square"
        }
        return selected ? "largecircle.fill.circle" : "circle"
    }

    private func controlBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(isSelected ? Color.effectiveAccent.opacity(0.18) : Color.white.opacity(0.09))
    }

    private func controlBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(
                isSelected ? Color.effectiveAccent.opacity(0.75) : Color.white.opacity(0.08),
                lineWidth: 1
            )
    }
}

private extension View {
    func agentPrimaryButton() -> some View {
        buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.effectiveAccent)
            )
    }

    func agentSecondaryButton() -> some View {
        buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.11))
            )
    }
}
