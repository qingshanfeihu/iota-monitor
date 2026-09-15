//
//  Store.swift
//  Adapted from exelban/stats (Kit/plugins/Store.swift) — MIT License.
//  Thread-safe UserDefaults wrapper.
//

import Cocoa

public class Store {
    public static let shared = Store()

    private var cache: [String: Any] = [:]
    private let queue = DispatchQueue(label: "eu.exelban.Stats.Store", attributes: .concurrent)
    private let defaults = UserDefaults.standard

    init() {
        self.syncFromDisk()
    }

    private func syncFromDisk() {
        guard let preferences = self.defaults.dictionaryRepresentation() as? [String: Any] else { return }
        self.queue.sync(flags: .barrier) {
            preferences.forEach { self.cache[$0.key] = $0.value }
        }
    }

    public func exist(key: String) -> Bool {
        return self.defaults.object(forKey: key) != nil
    }

    public func bool(key: String, defaultValue: Bool? = nil) -> Bool {
        return self.value(key: key, defaultValue: defaultValue) as? Bool ?? (defaultValue ?? false)
    }
    public func string(key: String, defaultValue: String? = nil) -> String {
        return self.value(key: key, defaultValue: defaultValue) as? String ?? (defaultValue ?? "")
    }
    public func int(key: String, defaultValue: Int? = nil) -> Int {
        return self.value(key: key, defaultValue: defaultValue) as? Int ?? (defaultValue ?? 0)
    }
    public func double(key: String, defaultValue: Double? = nil) -> Double {
        return self.value(key: key, defaultValue: defaultValue) as? Double ?? (defaultValue ?? 0)
    }
    public func array(key: String, defaultValue: [Any]? = nil) -> [Any]? {
        return self.value(key: key, defaultValue: defaultValue) as? [Any] ?? defaultValue
    }
    public func data(key: String, defaultValue: Data? = nil) -> Data? {
        return self.value(key: key, defaultValue: defaultValue) as? Data ?? defaultValue
    }

    private func value(key: String, defaultValue: Any?) -> Any? {
        var value: Any? = nil
        self.queue.sync {
            value = self.cache[key]
        }
        if value == nil, let defaultValue = defaultValue {
            self.set(key: key, value: defaultValue)
            value = defaultValue
        }
        return value
    }

    public func set(key: String, value: Any) {
        self.queue.sync(flags: .barrier) {
            self.cache[key] = value
        }
        self.defaults.set(value, forKey: key)
    }

    public func remove(_ key: String) {
        self.queue.sync(flags: .barrier) {
            self.cache.removeValue(forKey: key)
        }
        self.defaults.removeObject(forKey: key)
    }

    public func reset() {
        self.cache.keys.forEach { self.defaults.removeObject(forKey: $0) }
        if let bundleID = Bundle.main.bundleIdentifier {
            self.defaults.removePersistentDomain(forName: bundleID)
        }
        self.queue.sync(flags: .barrier) {
            self.cache.removeAll()
        }
    }

    public func export() -> String {
        if let dictionary = defaults.dictionaryRepresentation() as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: dictionary),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{}"
    }

    public func importFrom(_ string: String) -> Bool {
        guard let data = string.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        var state: [String: Any] = [:]
        self.queue.sync { state = self.cache }
        state.filter { $0.key.hasPrefix("NSStatusItem") || $0.key.hasPrefix("NSWindow") }.forEach {
            self.set(key: $0.key, value: $0.value)
        }
        json.filter { $0.key != "NSStatusItem Preferred Position noscript" }.forEach {
            self.set(key: $0.key, value: $0.value)
        }
        return true
    }
}
