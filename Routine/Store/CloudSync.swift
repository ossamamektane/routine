import Foundation

/// Sync through the iCloud key-value store: private to your Apple Account, no sign-in screen,
/// and it comes back by itself after reinstalling or on a new iPhone.
/// Each item is stored under its own key so a change only uploads that item.
final class CloudSync {
    private let store = NSUbiquitousKeyValueStore.default
    private var observer: NSObjectProtocol?
    /// Called on the main queue with the change reason when another device changed something.
    var onChange: ((Int?) -> Void)?

    private static let itemPrefix = "i."
    /// Wake-up times only, from earlier versions.
    private static let wakesKey = "wakes"
    private static let daysKey = "days"
    private static let settingsKey = "settings"

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue
            self?.onChange?(reason)
        }
        store.synchronize()
    }

    func synchronize() {
        store.synchronize()
    }

    static var isAccountAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    func remoteItems() -> [Item] {
        var result: [Item] = []
        for (key, value) in store.dictionaryRepresentation where key.hasPrefix(CloudSync.itemPrefix) {
            if let data = value as? Data, let item = try? Coding.decoder.decode(Item.self, from: data) {
                result.append(item)
            }
        }
        return result
    }

    func write(_ item: Item) {
        guard let data = try? Coding.encoder.encode(item) else { return }
        store.set(data, forKey: CloudSync.itemPrefix + item.id.uuidString)
    }

    func remove(_ id: UUID) {
        store.removeObject(forKey: CloudSync.itemPrefix + id.uuidString)
    }

    func remoteWakes() -> [String: Int] {
        guard let data = store.data(forKey: CloudSync.wakesKey),
              let wakes = try? Coding.decoder.decode([String: Int].self, from: data) else { return [:] }
        return wakes
    }

    func remoteDays() -> WakeRecords? {
        guard let data = store.data(forKey: CloudSync.daysKey) else { return nil }
        return try? Coding.decoder.decode(WakeRecords.self, from: data)
    }

    func writeDays(_ records: WakeRecords) {
        guard let data = try? Coding.encoder.encode(records) else { return }
        store.set(data, forKey: CloudSync.daysKey)
    }

    func remoteSettings() -> SyncedSettings? {
        guard let data = store.data(forKey: CloudSync.settingsKey) else { return nil }
        return try? Coding.decoder.decode(SyncedSettings.self, from: data)
    }

    func writeSettings(_ settings: SyncedSettings) {
        guard let data = try? Coding.encoder.encode(settings) else { return }
        store.set(data, forKey: CloudSync.settingsKey)
    }
}

/// Wake-up and sleep times, synced as one record. The newest change wins.
struct WakeRecords: Codable, Equatable {
    var wakes: [String: Int] = [:]
    var sleeps: [String: Int] = [:]
    var modifiedAt: Date = Date(timeIntervalSince1970: 0)

    enum CodingKeys: String, CodingKey {
        case wakes, sleeps, modifiedAt
    }
}

extension WakeRecords {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        wakes = c.field(.wakes, or: [:])
        sleeps = c.field(.sleeps, or: [:])
        modifiedAt = c.field(.modifiedAt, or: modifiedAt)
    }
}
