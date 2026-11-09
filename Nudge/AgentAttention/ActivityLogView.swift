import SwiftUI

/// The last few agent requests and nudges, below the send view. Handled
/// entries recede; open ones keep full contrast so the eye finds them.
@MainActor
struct ActivityLogView: View {
    @ObservedObject var store: ActivityLogStore
    @ObservedObject var center: AgentAttentionCenter

    @Environment(\.displayScale) private var displayScale

    static let rowHeight: CGFloat = 32
    /// Extra air between the ping buttons and the log.
    static let topInset: CGFloat = 6

    /// Height the notch adds for the log, so it can size itself up front:
    /// the stack's 8pt spacing, the inset, the rows, minus 16pt of the send
    /// view's own centering slack so the notch doesn't end in a blank band.
    static func height(forEntryCount count: Int) -> CGFloat {
        count == 0 ? 0 : 8 + topInset + CGFloat(count) * rowHeight - 16
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                ForEach(Array(store.entries.enumerated()), id: \.element.id) { offset, entry in
                    if offset > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 1 / displayScale)
                            .padding(.leading, 38)
                    }
                    row(entry, now: context.date)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.top, Self.topInset)
        .animation(.easeOut(duration: 0.2), value: store.entries)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Letzte Meldungen")
    }

    private func row(_ entry: ActivityLogEntry, now: Date) -> some View {
        Button {
            open(entry)
        } label: {
            HStack(spacing: 10) {
                icon(for: entry)
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                trailing(for: entry, now: now)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight)
            .opacity(entry.isDimmed ? 0.42 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(AgentRowStyle())
        .accessibilityLabel(entry.title)
        .accessibilityValue(statusDescription(entry, now: now))
    }

    @ViewBuilder
    private func icon(for entry: ActivityLogEntry) -> some View {
        switch entry.kind {
        case .nudge:
            Circle()
                .fill(Color.effectiveAccent.opacity(0.9))
                .overlay(
                    Text(String((entry.sender ?? "?").prefix(1)))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                )
                .frame(width: 18, height: 18)
        case .completion, .question, .approval:
            if let image = AgentHostIcon.image(for: entry.host) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay(
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    )
                    .frame(width: 18, height: 18)
            }
        }
    }

    @ViewBuilder
    private func trailing(for entry: ActivityLogEntry, now: Date) -> some View {
        switch entry.status {
        case .pending:
            Text("Offen")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent)
        case let .handled(outcome):
            Text("\(outcome) · \(Self.relative(entry.date, now: now))")
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.62))
        case .unhandled:
            Text(Self.relative(entry.date, now: now))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private func open(_ entry: ActivityLogEntry) {
        switch entry.kind {
        case .nudge:
            store.settle(id: entry.id, outcome: "Gesehen")
        case .completion, .question, .approval:
            if entry.status == .pending, center.state.activeRequest?.id == entry.id {
                center.revealActiveRequest()
                return
            }
            if let host = entry.host {
                center.jump(to: host)
            }
            if !entry.isDimmed {
                store.settle(id: entry.id, outcome: "Geöffnet")
            }
        }
    }

    private func statusDescription(_ entry: ActivityLogEntry, now: Date) -> String {
        switch entry.status {
        case .pending: return "Offen"
        case let .handled(outcome): return "\(outcome), \(Self.relative(entry.date, now: now))"
        case .unhandled: return "Nicht erledigt, \(Self.relative(entry.date, now: now))"
        }
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "gerade eben" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
