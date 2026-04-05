import Foundation
import CloudKit
import SwiftData
import Observation

// MARK: - Sharing Scope

enum SharingScope: String, CaseIterable, Identifiable, Codable {
    case everything = "everything"
    case listsOnly = "listsOnly"
    case recipesOnly = "recipesOnly"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .everything: "Tudo"
        case .listsOnly: "Apenas Listas"
        case .recipesOnly: "Apenas Receitas"
        }
    }

    var description: String {
        switch self {
        case .everything: "Compartilha receitas, despensa, lista de compras, utensílios e categorias."
        case .listsOnly: "Compartilha despensa, lista de compras, utensílios e categorias."
        case .recipesOnly: "Compartilha apenas as receitas."
        }
    }

    var icon: String {
        switch self {
        case .everything: "tray.full"
        case .listsOnly: "list.clipboard"
        case .recipesOnly: "book"
        }
    }
}

// MARK: - Sharing Service

@Observable
final class SharingService: @unchecked Sendable {
    static let shared = SharingService()

    private static let sharingActiveKey = "SmartKitchen.sharingActive"
    private static let sharingScopeKey = "SmartKitchen.sharingScope"

    private let ckContainer: CKContainer

    // MARK: - State

    var isSharing: Bool {
        get { UserDefaults.standard.bool(forKey: Self.sharingActiveKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sharingActiveKey) }
    }

    var shareScope: SharingScope {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.sharingScopeKey) else { return .everything }
            return SharingScope(rawValue: raw) ?? .everything
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.sharingScopeKey) }
    }

    var participants: [CKShare.Participant] = []
    var activeShare: CKShare?
    var isLoading = false
    var error: String?

    // MARK: - Init

    private init() {
        ckContainer = CKContainer(identifier: CloudSyncService.cloudKitContainerID)
        if isSharing {
            Task { await refreshShare() }
        }
    }

    // MARK: - Zone Discovery

    /// Discovers the CloudKit record zone created by SwiftData for the Shared store.
    func discoverSharedZoneID() async throws -> CKRecordZone.ID {
        let zones = try await ckContainer.privateCloudDatabase.allRecordZones()

        // SwiftData zones for named ModelConfigurations typically include the config name
        // Look for the "Shared" zone, or fall back to a CoreData zone that isn't "Private"
        for zone in zones {
            let name = zone.zoneID.zoneName
            if name.localizedCaseInsensitiveContains("Shared") {
                return zone.zoneID
            }
        }

        // Fallback: use the first CoreData CloudKit zone that isn't obviously "Private"
        for zone in zones {
            let name = zone.zoneID.zoneName
            if name.contains("com.apple.coredata.cloudkit") && !name.localizedCaseInsensitiveContains("Private") {
                return zone.zoneID
            }
        }

        // Last resort: use any zone that isn't the default zone
        for zone in zones where zone.zoneID != CKRecordZone.default().zoneID {
            return zone.zoneID
        }

        throw NSError(
            domain: "Sharing", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Nenhuma zona de dados encontrada. Ative a sincronização iCloud e adicione alguns dados primeiro."]
        )
    }

    // MARK: - Share Management

    /// Fetches the existing CKShare for the shared zone, if any.
    func fetchExistingShare() async throws -> CKShare? {
        let zoneID = try await discoverSharedZoneID()
        let shareRecordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            let record = try await ckContainer.privateCloudDatabase.record(for: shareRecordID)
            return record as? CKShare
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Creates a new CKShare for the shared zone and returns it for use with UICloudSharingController.
    @MainActor
    func createShare(scope: SharingScope) async throws -> CKShare {
        isLoading = true
        error = nil
        defer { isLoading = false }

        // Check if a share already exists
        if let existing = try await fetchExistingShare() {
            activeShare = existing
            isSharing = true
            shareScope = scope
            await refreshParticipants()
            return existing
        }

        let zoneID = try await discoverSharedZoneID()
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Smart Kitchen"
        share.publicPermission = .none

        try await ckContainer.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])

        activeShare = share
        isSharing = true
        shareScope = scope
        await refreshParticipants()
        return share
    }

    /// Stops sharing by deleting the active CKShare.
    @MainActor
    func stopSharing() async throws {
        isLoading = true
        error = nil
        defer { isLoading = false }

        if let share = activeShare {
            try await ckContainer.privateCloudDatabase.modifyRecords(saving: [], deleting: [share.recordID])
        }

        activeShare = nil
        participants = []
        isSharing = false
    }

    /// Refreshes the active share and participants from CloudKit.
    @MainActor
    func refreshShare() async {
        isLoading = true
        defer { isLoading = false }

        do {
            activeShare = try await fetchExistingShare()
            if activeShare == nil {
                isSharing = false
                participants = []
            } else {
                await refreshParticipants()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Updates the participants list from the active share.
    @MainActor
    func refreshParticipants() async {
        guard let share = activeShare else {
            participants = []
            return
        }
        // Filter out the owner — only show other participants
        participants = share.participants.filter { $0.role != .owner }
    }

    /// Removes a participant from the active share.
    @MainActor
    func removeParticipant(_ participant: CKShare.Participant) async throws {
        guard let share = activeShare else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        share.removeParticipant(participant)
        try await ckContainer.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])

        await refreshParticipants()
    }

    // MARK: - Share Acceptance

    /// Accepts a CloudKit share invitation from another user.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        try await ckContainer.accept(metadata)
    }

    // MARK: - Helpers

    /// The CKContainer instance for use with UICloudSharingController.
    var cloudKitContainer: CKContainer { ckContainer }
}
