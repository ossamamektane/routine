import SwiftUI
import UIKit

extension ItemColor {
    var color: Color {
        switch self {
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .brown: return .brown
        case .gray: return .gray
        }
    }

    var name: LocalizedStringKey {
        switch self {
        case .green: return "Green"
        case .mint: return "Mint"
        case .teal: return "Teal"
        case .cyan: return "Cyan"
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .brown: return "Brown"
        case .gray: return "Gray"
        }
    }
}

/// A thin ring that fills up, for hourly routines and goals.
struct ProgressRing: View {
    var fraction: Double
    var tint: Color
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// The round check button at the start of a row.
struct CheckButton: View {
    var state: EntryState
    var tint: Color
    var progress: Double? = nil
    /// Shown instead of a check for rows with nothing to check off.
    var infoSymbol: String = "checkmark.seal"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if state == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(tint)
                        .transition(.scale.combined(with: .opacity))
                } else if state == .skipped {
                    Image(systemName: "forward.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else if state == .info {
                    Image(systemName: infoSymbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if let progress, progress > 0 {
                    ProgressRing(fraction: progress, tint: tint)
                        .frame(width: 22, height: 22)
                } else if state == .waiting {
                    Image(systemName: "circle.dashed")
                        .font(.title2)
                        .foregroundStyle(Color(uiColor: .systemGray3))
                } else {
                    Image(systemName: "circle")
                        .font(.title2)
                        .foregroundStyle(Color(uiColor: .systemGray2))
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(state == .info)
        .accessibilityLabel(state == .done || state == .skipped ? Text("Undo") : Text("Mark as Completed"))
    }
}

/// A short line at the end of a list, like the count at the bottom of Notes or Files:
/// "12 Tasks" in Tasks, what your bills come to in Bills.
struct ListSummary: View {
    var text: String

    var body: some View {
        Section {
            Text(verbatim: text)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

struct FeatureRow: View {
    var symbol: String
    var color: Color
    var title: LocalizedStringKey
    var text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What the editor sheet should show.
struct EditorRequest: Identifiable {
    let id = UUID()
    var item: Item
    var isNew: Bool
    /// Bills have an amount and can be paid automatically; tasks have neither.
    var isBill: Bool

    static func new(_ item: Item = Item(), bill: Bool = false) -> EditorRequest {
        EditorRequest(item: item, isNew: true, isBill: bill || item.hasCost)
    }

    static func newBill() -> EditorRequest {
        new(billTemplate(), bill: true)
    }

    static func edit(_ item: Item) -> EditorRequest {
        EditorRequest(item: item, isNew: false, isBill: item.hasCost)
    }
}

/// A starting point for a bill: monthly, with a reminder the day before it's due.
func billTemplate() -> Item {
    var item = Item()
    item.symbol = "doc.text.fill"
    item.color = .blue
    item.schedule.unit = .month
    item.reminder = .dayBefore
    return item
}

/// "Now", "In 35m", "7h left", "2 days late": blue when it's time, red when it's late, gray otherwise.
struct CountdownLabel: View {
    var countdown: Countdown

    private var color: Color {
        switch countdown.tone {
        case .normal, .calm, .soon: return Color.secondary
        case .now: return Color.accentColor
        case .late: return Color.red
        }
    }

    private var weight: Font.Weight {
        switch countdown.tone {
        case .normal, .calm: return .regular
        case .now, .soon, .late: return .semibold
        }
    }

    var body: some View {
        Text(verbatim: countdown.text)
            .font(.subheadline)
            .fontWeight(weight)
            .foregroundStyle(color)
            .monospacedDigit()
            .lineLimit(1)
            .layoutPriority(1)
    }
}

/// The card at the top of each tab: an icon, a headline and a line under it.
/// "Up for 5h" on Today, what's done in Tasks, what's paid in Bills.
struct SummaryCard<Accessory: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var symbol: String
    var title: String
    var subtitle: String
    var accessory: Accessory

    init(symbol: String, title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .lineLimit(lines)
                    .minimumScaleFactor(0.8)
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(lines)
                        .minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 6)
            accessory
        }
        .padding(.vertical, 2)
    }

    /// One line each, so the cards on all three tabs are the same height. With larger text,
    /// they wrap instead of getting cut off.
    private var lines: Int {
        if typeSize.isAccessibilitySize { return 3 }
        return typeSize > .large ? 2 : 1
    }
}

extension SummaryCard where Accessory == EmptyView {
    init(symbol: String, title: String, subtitle: String) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Top left of a sheet: an "xmark" that leaves without saving. Plain glass, not blue, like
/// Apple's own sheets: only the button that saves is blue.
struct CancelButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .tint(Color.primary)
        .accessibilityLabel(Text("Cancel"))
    }
}

/// Closes a sheet whose changes are already saved, like Settings: an "xmark", as in Apple's
/// Home app.
struct CloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .tint(Color.primary)
        .accessibilityLabel(Text("Close"))
    }
}

/// Top right of a sheet: a checkmark that adds or saves, like Apple's own sheets.
struct ConfirmButton: View {
    var title: LocalizedStringKey
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(Text(title))
    }
}

/// Above the keyboard: hides it.
struct KeyboardDoneButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "keyboard.chevron.compact.down")
        }
        .accessibilityLabel(Text("Done"))
    }
}
