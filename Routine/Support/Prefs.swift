import SwiftUI
import UIKit

/// Settings kept on this iPhone only.
enum PrefKey {
    static let reminders = "remindersOn"
    static let badge = "badgeOn"
    static let appearance = "appearance"
    static let welcomeDone = "welcomeDone"
    static let legacyDone = "legacyImportDone"
    /// What Routine remembers to decide when to ask "Did you sleep?" (`SleepLog`, as JSON).
    static let sleepLog = "sleepLog"
    /// The latest time this iPhone's clock showed while Routine was open, to notice it being turned back.
    static let lastSeen = "lastSeen"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    /// Dark until you pick something else in Settings.
    static let standard: Appearance = .dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Switches every window at once, including sheets that are open (like Settings).
    func apply() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = interfaceStyle
            }
        }
    }
}

/// Settings that follow you to your other devices through iCloud.
struct SyncedSettings: Codable, Equatable {
    var currency: String = SyncedSettings.defaultCurrency
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)

    static var defaultCurrency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    enum CodingKeys: String, CodingKey {
        case currency, modifiedAt
    }
}

extension SyncedSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        currency = c.field(.currency, or: currency)
        modifiedAt = c.field(.modifiedAt, or: modifiedAt)
    }
}

enum AppTab: Hashable {
    case today, routines, money
}
