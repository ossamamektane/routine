import Foundation

struct StoredData: Codable {
    var version: Int = 1
    var items: [Item] = []
    /// Wake-up time per day: "2025-11-04" → minutes after midnight.
    var wakes: [String: Int] = [:]
    /// When you went to sleep, under the day it ended: minutes after that day's midnight (1500 is 1:00 the next night).
    var sleeps: [String: Int] = [:]
    /// The last change to wake-up or sleep times, so the newest one wins in iCloud.
    var wakesModifiedAt: Date = Date(timeIntervalSince1970: 0)
    var settings: SyncedSettings = SyncedSettings()

    enum CodingKeys: String, CodingKey {
        case version, items, wakes, sleeps, wakesModifiedAt, settings
    }
}

extension StoredData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        version = c.field(.version, or: 1)
        let lossy: [Lossy<Item>] = c.field(.items, or: [])
        items = lossy.compactMap { $0.value }
        wakes = c.field(.wakes, or: [:])
        sleeps = c.field(.sleeps, or: [:])
        wakesModifiedAt = c.field(.wakesModifiedAt, or: wakesModifiedAt)
        settings = c.field(.settings, or: SyncedSettings())
    }
}

enum Coding {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    static let decoder = JSONDecoder()
}

/// Saves everything as one JSON file in Application Support, written atomically.
/// The first save of each launch keeps the previous file as a backup.
final class Persistence {
    private let fm = FileManager.default
    let folder: URL
    private var backupDone = false

    init() {
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        folder = base.appendingPathComponent("Routine", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    var fileURL: URL { folder.appendingPathComponent("data.json") }
    var backupURL: URL { folder.appendingPathComponent("data-backup.json") }
    var hasData: Bool { fm.fileExists(atPath: fileURL.path) || fm.fileExists(atPath: backupURL.path) }

    func load() -> StoredData? {
        if let data = try? Data(contentsOf: fileURL), let stored = try? Coding.decoder.decode(StoredData.self, from: data) {
            return stored
        }
        // The main file is missing or damaged: never overwrite the backup with it.
        backupDone = true
        if let data = try? Data(contentsOf: backupURL), let stored = try? Coding.decoder.decode(StoredData.self, from: data) {
            return stored
        }
        return nil
    }

    func save(_ stored: StoredData) {
        guard let data = try? Coding.encoder.encode(stored) else { return }
        if !backupDone {
            backupDone = true
            if fm.fileExists(atPath: fileURL.path) {
                try? fm.removeItem(at: backupURL)
                try? fm.copyItem(at: fileURL, to: backupURL)
            }
        }
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("Routine: could not save – \(error.localizedDescription)")
        }
    }
}
