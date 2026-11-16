import SwiftUI

/// Settings kept on this iPhone only.
enum PrefKey {
    static let reminders = "remindersOn"
    static let badge = "badgeOn"
    static let appearance = "appearance"
    static let welcomeDone = "welcomeDone"
    static let legacyDone = "legacyImportDone"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

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
}

/// Settings that follow you to your other devices through iCloud.
struct SyncedSettings: Codable, Equatable {
    var currency: String = SyncedSettings.defaultCurrency
    /// Ask "Are you up?" if you haven't tapped "I'm up" by this time.
    var morningCheckIn: Bool = true
    var morningMinute: Int = 9 * 60
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)

    static var defaultCurrency: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    enum CodingKeys: String, CodingKey {
        case currency, morningCheckIn, morningMinute, modifiedAt
    }
}

extension SyncedSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        currency = c.field(.currency, or: currency)
        morningCheckIn = c.field(.morningCheckIn, or: morningCheckIn)
        morningMinute = min(max(c.field(.morningMinute, or: morningMinute), 0), 1439)
        modifiedAt = c.field(.modifiedAt, or: modifiedAt)
    }
}

enum AppTab: Hashable {
    case today, routines, money
}
