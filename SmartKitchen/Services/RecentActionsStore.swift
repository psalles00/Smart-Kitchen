import Foundation

/// Persists recently accessed items for the Command Bar empty state.
final class RecentActionsStore: @unchecked Sendable {
    static let shared = RecentActionsStore()

    private let key = "com.smartkitchen.recentActions"
    private let maxItems = 12

    private init() {}

    /// All recent actions, newest first.
    var actions: [RecentAction] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentAction].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Record an action. Deduplicates by objectID or title+type.
    func record(_ action: RecentAction) {
        var list = actions

        // Remove existing duplicate
        list.removeAll { existing in
            if let oid = action.objectID, let eid = existing.objectID {
                return oid == eid
            }
            return existing.title == action.title && existing.type == action.type
        }

        list.insert(action, at: 0)
        if list.count > maxItems {
            list = Array(list.prefix(maxItems))
        }

        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
