import Foundation
import Security

struct DiskState: Codable, Sendable {
    var training = TrainingState()
}

enum LocalFiles {
    static func url(testing: Bool) -> URL {
        let directory = URL.applicationSupportDirectory
            .appendingPathComponent(testing ? "BodyweightProgression-UITests" : "BodyweightProgression",
                                    isDirectory: true)
        return directory.appendingPathComponent("training-v1.json")
    }

    static func read(testing: Bool, reset: Bool) throws -> DiskState {
        let url = url(testing: testing)
        if reset, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return DiskState() }
        return try JSONDecoder().decode(DiskState.self, from: Data(contentsOf: url))
    }

    static func save(_ state: DiskState, testing: Bool) throws {
        let url = url(testing: testing)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }

    static func publish(_ widget: WidgetSnapshot) throws -> Bool {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.group)
        else { return false }
        let url = container.appendingPathComponent(WidgetSnapshot.filename)
        let data = try JSONEncoder().encode(widget)
        if (try? Data(contentsOf: url)) == data { return false }
        try data.write(to: url, options: .atomic)
        return true
    }
}

enum EntitlementCache {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.hgsldswk.bodyweightprogression",
            kSecAttrAccount as String: "storekit-v1"
        ]
    }

    static func load() throws -> Entitlement? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    static func save(_ entitlement: Entitlement) throws {
        let data = try JSONEncoder().encode(entitlement)
        let values = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
