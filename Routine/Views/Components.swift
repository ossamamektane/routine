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
                    Image(systemName: "checkmark.seal")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if let progress, progress > 0 {
                    ProgressRing(fraction: progress, tint: tint)
                        .frame(width: 22, height: 22)
                } else if state == .waiting {
                    Image(systemName: "circle.dashed")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                } else {
                    Image(systemName: "circle")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .disabled(state == .info)
        .accessibilityLabel(state == .done || state == .skipped ? Text("Undo") : Text("Mark as done"))
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

/// A starting point for a bill: monthly, no reminder until you turn one on.
func billTemplate() -> Item {
    var item = Item()
    item.symbol = "doc.text.fill"
    item.color = .blue
    item.schedule.unit = .month
    item.reminder = .off
    return item
}
