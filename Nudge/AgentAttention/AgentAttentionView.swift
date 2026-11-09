import AppKit
import SwiftUI

/// Reports the agent panel's natural height so the notch can hug its content.
struct AgentContentHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
struct AgentAttentionView: View {
    @ObservedObject var center: AgentAttentionCenter
    let focusController: AgentPanelFocusController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var completionHovered = false
    @FocusState private var freeformFocused: Bool
    @State private var textEntryActive = false

    var body: some View {
        ZStack(alignment: .top) {
            if center.state.visible {
                switch center.state.activeRequest {
                case let .question(questionSet):
                    questionView(questionSet)
                        .transition(stateTransition)
                case let .approval(approval):
                    approvalView(approval)
                        .transition(stateTransition)
                case nil:
                    if let completion = center.state.completion {
                        completionView(completion)
                            .transition(stateTransition)
                    }
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: AgentContentHeightPreference.self, value: proxy.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(stateAnimation, value: presentationID)
        .onDisappear {
            endTextEntry()
            restoreFocus()
        }
    }

    // MARK: - Completion

    private func completionView(_ completion: AgentCompletion) -> some View {
        Button {
            center.jumpOrHandoff()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                hostIcon(badge: .completion)

                VStack(alignment: .leading, spacing: 3) {
                    titleLine("\(sourceName) ist fertig", trailing: projectName)
                    if let message = condensed(completion.message) {
                        Text(message)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 12)

                jumpCapsule(highlighted: completionHovered)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AgentPressStyle())
        .onHover { completionHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: completionHovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sourceName) ist fertig. \(jumpLabel)")
    }

    // MARK: - Approval

    /// The rounded box that shows what an approval will run or touch.
    private func detailBox<Content: View>(_ content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
    }

    private func monospacedText(_ text: String, lineLimit: Int) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(lineLimit)
    }

    private func commandBox(_ command: String) -> some View {
        detailBox(monospacedText(command, lineLimit: 3).textSelection(.enabled))
    }

    /// One text per summary line, so a long value shortens in its middle
    /// instead of pushing the following arguments out of the box.
    private func summaryBox(_ summary: String) -> some View {
        let lines = summary.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return detailBox(
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    monospacedText(line, lineLimit: 2)
                        .truncationMode(.middle)
                }
            }
            .textSelection(.enabled)
        )
        .accessibilityElement(children: .ignore)
    }

    private func approvalView(_ approval: AgentApproval) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                hostIcon(badge: .approval)

                VStack(alignment: .leading, spacing: 3) {
                    titleLine("\(sourceName) möchte \(approval.toolName) nutzen", trailing: projectName)
                    if let description = approvalDescription(approval) {
                        Text(description)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                    }
                }
                .padding(.top, 1)

                Spacer(minLength: 12)

                jumpButton
            }

            if let command = approval.command, !command.isEmpty {
                commandBox(command)
                    .accessibilityLabel("Befehl: \(command)")
            } else if let summary = approval.inputSummary, !summary.isEmpty {
                summaryBox(summary)
                    .accessibilityLabel("Details: \(summary)")
            }

            HStack(spacing: 8) {
                Button("Ablehnen") {
                    center.resolveApproval(.denied)
                }
                .buttonStyle(AgentCapsuleStyle(role: .secondary, fill: true))
                .accessibilityLabel("Anfrage ablehnen")

                if approval.source == .claudeCode && approval.allowsClaudeSessionRule {
                    Button("Für Session erlauben") {
                        center.resolveApproval(.approvedForSession)
                    }
                    .buttonStyle(AgentCapsuleStyle(role: .secondary, fill: true))
                    .accessibilityLabel("Für diese Claude-Code-Session erlauben")
                }

                Button("Einmal erlauben") {
                    center.resolveApproval(.approvedOnce)
                }
                .buttonStyle(AgentCapsuleStyle(role: .primary, fill: true))
                .accessibilityLabel("Einmal erlauben")
            }
        }
    }

    // MARK: - Question

    @ViewBuilder
    private func questionView(_ questionSet: AgentQuestionSet) -> some View {
        if questionSet.questions.indices.contains(center.state.questionIndex) {
            let index = center.state.questionIndex
            let question = questionSet.questions[index]
            let isLast = index == questionSet.questions.index(before: questionSet.questions.endIndex)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    hostIcon(badge: .question)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(question.prompt)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(sourceAndProject)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    .padding(.top, 1)
                    .id("\(question.id)-prompt")
                    .transition(contentTransition)

                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    ForEach(Array(question.choices.enumerated()), id: \.element.label) { offset, choice in
                        if offset > 0 { rowSeparator }
                        optionRow(choice, question: question, index: index)
                    }
                    if !question.choices.isEmpty { rowSeparator }
                    freeformRow(at: index)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .id("\(question.id)-choices")
                .transition(contentTransition)

                HStack(spacing: 12) {
                    jumpButton
                    Spacer(minLength: 0)
                    if questionSet.questions.count > 1 {
                        pageIndicator(questionSet)
                    }
                    if isLast {
                        Button("Antworten") {
                            endTextEntry()
                            center.submitQuestion()
                            restoreFocus()
                        }
                        .buttonStyle(AgentCapsuleStyle(role: .primary, fill: false))
                        .disabled(center.state.answersForSubmission() == nil)
                        .accessibilityLabel("Alle Antworten senden")
                    } else {
                        Button("Weiter") {
                            endTextEntry()
                            center.moveQuestion(to: index + 1)
                        }
                        .buttonStyle(AgentCapsuleStyle(role: .primary, fill: false))
                        .disabled(!isDraftValid(question: question, at: index))
                        .accessibilityLabel("Zur nächsten Frage")
                    }
                }
            }
            .animation(contentAnimation, value: index)
        }
    }

    private func optionRow(
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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.88))
                        .lineLimit(1)
                    if !choice.description.isEmpty {
                        Text(choice.description)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                selectionMark(selected: selected, multiple: question.multiSelect)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: choice.description.isEmpty ? 36 : 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AgentRowStyle())
        .accessibilityLabel(choice.description.isEmpty ? choice.label : "\(choice.label). \(choice.description)")
        .accessibilityValue(selected ? "Ausgewählt" : "Nicht ausgewählt")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func freeformRow(at index: Int) -> some View {
        let isDraft = isTextDraft(at: index)
        return HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(isDraft ? 0.8 : 0.5))
            TextField(
                "",
                text: freeformBinding(at: index),
                prompt: Text("Eigene Antwort").foregroundStyle(.white.opacity(0.5))
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .focused($freeformFocused)
            .onSubmit {
                guard case let .question(questionSet) = center.state.activeRequest,
                      questionSet.questions.indices.contains(index) else { return }
                if index == questionSet.questions.count - 1 {
                    guard center.state.answersForSubmission() != nil else { return }
                    endTextEntry()
                    center.submitQuestion()
                    restoreFocus()
                } else if isDraftValid(question: questionSet.questions[index], at: index) {
                    endTextEntry()
                    center.moveQuestion(to: index + 1)
                }
            }
            .onChange(of: freeformFocused) { _, focused in
                if focused {
                    startTextEntry()
                } else {
                    endTextEntry()
                }
            }
            .accessibilityLabel("Eigene Antwort für Frage \(index + 1)")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                if !isTextDraft(at: index) {
                    center.answer(.text(""), at: index)
                }
                startTextEntry()
                freeformFocused = true
            }
        )
    }

    private func selectionMark(selected: Bool, multiple: Bool) -> some View {
        let symbol = multiple ? (selected ? "checkmark.circle.fill" : "circle") : "checkmark"
        return Image(systemName: symbol)
            .font(.system(size: multiple ? 16 : 13, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                selected ? Color.white : Color.white.opacity(0.28),
                selected ? Color.effectiveAccent : Color.clear
            )
            .opacity(multiple || selected ? 1 : 0)
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selected)
            .frame(width: 18)
            .accessibilityHidden(true)
    }

    private var rowSeparator: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1 / displayScale)
            .padding(.leading, 14)
    }

    private func pageIndicator(_ questionSet: AgentQuestionSet) -> some View {
        HStack(spacing: 5) {
            ForEach(questionSet.questions.indices, id: \.self) { index in
                let current = index == center.state.questionIndex
                Button {
                    endTextEntry()
                    center.moveQuestion(to: index)
                } label: {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(current ? 0.95 : 0.3))
                        .frame(width: current ? 14 : 6, height: 6)
                        .frame(height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Frage \(index + 1) bearbeiten")
                .accessibilityValue(current ? "Aktuell" : "")
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: center.state.questionIndex)
    }

    // MARK: - Shared pieces

    private func hostIcon(badge: AgentBadgedIcon.Badge) -> some View {
        AgentBadgedIcon(host: center.presentedEnvelope?.host, badge: badge)
    }

    private func titleLine(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(title)
                .foregroundStyle(.white)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let trailing {
                Text(trailing)
                    .foregroundStyle(.white.opacity(0.5))
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .lineLimit(1)
    }

    private var jumpLabelContent: some View {
        HStack(spacing: 5) {
            Text(jumpLabel)
                .lineLimit(1)
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 10.5, weight: .bold))
        }
    }

    /// The completion row's visual capsule; the whole row is the button.
    private func jumpCapsule(highlighted: Bool) -> some View {
        jumpLabelContent
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Capsule(style: .continuous).fill(Color.white.opacity(highlighted ? 0.17 : 0.12)))
    }

    private var jumpButton: some View {
        Button {
            endTextEntry()
            // Clear any stored focus restoration before requesting the origin app.
            restoreFocus()
            center.jumpOrHandoff()
        } label: {
            jumpLabelContent
        }
        .buttonStyle(AgentCapsuleStyle(role: .secondary, fill: false))
        .accessibilityLabel("\(jumpLabel). Anfrage im Agent fortsetzen")
    }

    // MARK: - Sizing

    /// A close guess of the panel's height, used to open the notch before the
    /// panel has measured itself, so it never opens at a generic height first.
    static func estimatedHeight(for state: AgentAttentionState) -> CGFloat {
        let verticalPadding: CGFloat = 10
        let header: CGFloat = 40
        let gap: CGFloat = 14
        let buttonRow: CGFloat = 32
        switch state.activeRequest {
        case let .question(questionSet):
            let index = state.questionIndex
            let choices = questionSet.questions.indices.contains(index) ? questionSet.questions[index].choices : []
            let rows = choices.reduce(CGFloat(38)) { $0 + ($1.description.isEmpty ? 36 : 44) }
            return verticalPadding + header + gap + rows + gap + buttonRow
        case let .approval(approval):
            let details: CGFloat
            if approval.command?.isEmpty == false {
                details = 38 + gap
            } else if let summary = approval.inputSummary, !summary.isEmpty {
                // One 15pt line per summary line plus 2pt between; long values wrap to a second line.
                let lines = summary.split(separator: "\n", omittingEmptySubsequences: false).count
                details = 21 + CGFloat(lines) * 17 + gap
            } else {
                details = 0
            }
            return verticalPadding + header + gap + details + buttonRow
        case nil:
            return verticalPadding + header + 8
        }
    }

    // MARK: - Motion

    /// Identifies what the panel shows, so swapping states animates once.
    private var presentationID: String {
        switch center.state.activeRequest {
        case let .question(questionSet): return "q-\(questionSet.id)"
        case let .approval(approval): return "a-\(approval.id)"
        case nil: return center.state.completion.map { "c-\($0.id)" } ?? "none"
        }
    }

    private var stateTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace).combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private var contentTransition: AnyTransition {
        reduceMotion ? .opacity : AnyTransition(.blurReplace)
    }

    private var stateAnimation: Animation {
        .spring(response: 0.36, dampingFraction: 0.86)
    }

    private var contentAnimation: Animation {
        .easeOut(duration: 0.22)
    }

    // MARK: - Content

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

    private var projectName: String? {
        guard let envelope = center.presentedEnvelope else { return nil }
        if let project = envelope.project?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            return project
        }
        let cwd = envelope.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private var sourceAndProject: String {
        projectName.map { "\(sourceName) · \($0)" } ?? sourceName
    }

    private func approvalDescription(_ approval: AgentApproval) -> String? {
        let detail = approval.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty,
              detail != approval.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              detail != approval.toolName else {
            return nil
        }
        return detail
    }

    /// Agent messages are often multi-line markdown; show them as one flowing line.
    private func condensed(_ message: String?) -> String? {
        guard let message else { return nil }
        let flattened = message
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return flattened.isEmpty ? nil : flattened
    }

    // MARK: - Drafts

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

    private func restoreFocus() {
        focusController.restorePreviousApplication { center.willRestoreFocus(to: $0) }
    }

    private func startTextEntry() {
        guard !textEntryActive else { return }
        textEntryActive = true
        focusController.beginTextEntry()
        center.beginEditing()
    }
}

// MARK: - Badged app icon

/// The originating app's icon with a small status badge, like a macOS
/// notification. Shared by the agent panel and the activity log.
struct AgentBadgedIcon: View {
    enum Badge {
        case completion, approval, question

        var symbol: String {
            switch self {
            case .completion: return "checkmark"
            case .approval: return "hand.raised.fill"
            case .question: return "questionmark"
            }
        }

        var color: Color {
            switch self {
            case .completion: return Color(nsColor: .systemGreen)
            case .approval: return Color(nsColor: .systemOrange)
            case .question: return Color.effectiveAccent
            }
        }
    }

    let host: AgentHost?
    let badge: Badge

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon = AgentHostIcon.image(for: host) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                        .overlay(
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        )
                        .padding(2)
                }
            }
            .frame(width: 36, height: 36)

            Circle()
                .fill(badge.color)
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: badge.symbol)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.white)
                )
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
                .offset(x: 3, y: 3)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

// MARK: - Host icons

@MainActor
enum AgentHostIcon {
    private static var cache: [String: NSImage] = [:]

    /// The originating app's own icon, the way macOS notifications show it.
    static func image(for host: AgentHost?) -> NSImage? {
        guard let bundleID = host?.bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}

// MARK: - Button styles

/// Capsule buttons in the notch. Primary is the white default action.
private struct AgentCapsuleStyle: ButtonStyle {
    enum Role { case primary, secondary }

    let role: Role
    /// Fill the row width in equal shares, like an alert's button row.
    let fill: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: 32)
            .background(Capsule(style: .continuous).fill(background(pressed: configuration.isPressed)))
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onHover { hovering = $0 }
    }

    private var foreground: Color {
        switch role {
        case .primary:
            return isEnabled ? Color.black.opacity(0.88) : Color.white.opacity(0.35)
        case .secondary:
            return Color.white.opacity(isEnabled ? 0.92 : 0.35)
        }
    }

    private func background(pressed: Bool) -> Color {
        switch role {
        case .primary:
            guard isEnabled else { return Color.white.opacity(0.1) }
            return Color.white.opacity(pressed ? 0.78 : (hovering ? 0.9 : 1))
        case .secondary:
            return Color.white.opacity(pressed ? 0.2 : (hovering ? 0.17 : 0.12))
        }
    }
}

/// Rows in the grouped choice list: hover tint and a quick press.
struct AgentRowStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.09 : (hovering ? 0.05 : 0)))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// Whole-surface buttons (the completion row, the jump capsule): press feedback only.
private struct AgentPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
