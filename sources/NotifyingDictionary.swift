enum NotifyingDictionaryChange {
    case added
    case removed
    case updated
}

typealias NotifyingDictionaryObserver<Key: Hashable, Value> = (Key, Value?, NotifyingDictionaryChange) -> Void

class NotifyingDictionary<Key: Hashable, Value> {
    private var storage: [Key: Value] = [:]
    private var observers: [UUID: NotifyingDictionaryObserver<Key, Value>] = [:]

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
    var keys: Dictionary<Key, Value>.Keys { storage.keys }
    var values: Dictionary<Key, Value>.Values { storage.values }

    subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            let oldValue = storage[key]
            storage[key] = newValue
            if let newValue {
                if oldValue != nil {
                    notify(key: key, value: newValue, change: .updated)
                } else {
                    notify(key: key, value: newValue, change: .added)
                }
            } else if oldValue != nil {
                notify(key: key, value: oldValue, change: .removed)
            }
        }
    }

    @discardableResult
    func removeValue(forKey key: Key) -> Value? {
        guard let value = storage.removeValue(forKey: key) else {
            return nil
        }
        notify(key: key, value: value, change: .removed)
        return value
    }

    func removeAll() {
        let snapshot = storage
        storage.removeAll()
        for (key, value) in snapshot {
            notify(key: key, value: value, change: .removed)
        }
    }

    /// Register an observer. Returns a UUID token; pass it to `removeObserver(_:)` to unregister.
    @discardableResult
    func addObserver(_ observer: @escaping NotifyingDictionaryObserver<Key, Value>) -> UUID {
        let token = UUID()
        observers[token] = observer
        return token
    }

    func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    private func notify(key: Key, value: Value?, change: NotifyingDictionaryChange) {
        for observer in observers.values {
            observer(key, value, change)
        }
    }
}
