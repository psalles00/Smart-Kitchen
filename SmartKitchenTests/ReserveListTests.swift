import Foundation
import SwiftData
import XCTest
@testable import Savoria

@MainActor
final class ReserveListTests: XCTestCase {
    func testOptionalListDefaultsOffAndDisabledRouteRemainsGrocery() {
        XCTAssertFalse(AppSettings().showReserve)
        let item = UnifiedItem(name: "Synthetic", isPantry: true)
        XCTAssertNil(item.isReserveValue)
        item.deplete(reserveEnabled: false)
        XCTAssertEqual(item.activeFlags, [.grocery])
    }

    func testFullCycleKeepsIdentityDetailsAndRenewsShelfLifeOnlyOnAcquire() throws {
        let photo = Data([1, 2, 3])
        let oldExpiry = Date(timeIntervalSince1970: 100)
        let item = UnifiedItem(name: "Synthetic", descriptionText: "Details", imageData: photo,
                               quantity: 2, unit: "kg", isPantry: true,
                               expirationDate: oldExpiry, defaultExpiryDays: 7, isFixed: true)
        let id = item.id
        item.deplete(reserveEnabled: true)
        XCTAssertEqual(item.activeFlags, [.reserve])
        XCTAssertEqual(item.expirationDate, oldExpiry)
        item.move(to: .grocery)
        XCTAssertEqual(item.activeFlags, [.grocery])
        XCTAssertEqual(item.expirationDate, oldExpiry)
        let now = Date(timeIntervalSince1970: 1_000_000)
        item.move(to: .pantry, now: now)
        XCTAssertEqual(item.activeFlags, [.pantry])
        XCTAssertEqual(item.expirationDate, Calendar.current.date(byAdding: .day, value: 7, to: now))
        XCTAssertEqual(item.id, id)
        XCTAssertEqual(item.descriptionText, "Details")
        XCTAssertEqual(item.imageData, photo)
        XCTAssertEqual(item.quantity, 2)
        XCTAssertEqual(item.unit, "kg")
        XCTAssertTrue(item.isFixed)
    }

    func testBackupRoundTripAndOldBackupsWithoutReserveFields() throws {
        let item = UnifiedItem(name: "Synthetic", isReserve: true, reserveSortOrder: 4)
        let data = try JSONEncoder().encode(UnifiedItemRecord(item))
        let restored = try JSONDecoder().decode(UnifiedItemRecord.self, from: data)
        XCTAssertEqual(restored.isReserve, true)
        XCTAssertEqual(restored.reserveSortOrder, 4)
        XCTAssertEqual(restored.id, item.id)
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "isReserve")
        old.removeValue(forKey: "reserveSortOrder")
        let legacy = try JSONDecoder().decode(UnifiedItemRecord.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(legacy.isReserve)
        let settings = AppSettings()
        settings.showReserve = true
        let restoredSettings = try JSONDecoder().decode(AppSettingsRecord.self, from: JSONEncoder().encode(AppSettingsRecord(settings)))
        XCTAssertTrue(restoredSettings.showReserve)
    }

    func testMembershipPersistsAndHidingListDoesNotRemoveItems() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: UnifiedItem.self, AppSettings.self, configurations: config)
        let context = ModelContext(container)
        let item = UnifiedItem(name: "Synthetic", isPantry: true)
        let settings = AppSettings()
        context.insert(item)
        context.insert(settings)
        settings.showReserve = true
        item.deplete(reserveEnabled: settings.showReserve)
        try context.save()
        settings.showReserve = false
        try context.save()
        let next = ModelContext(container)
        let fetched = try XCTUnwrap(next.fetch(FetchDescriptor<UnifiedItem>()).first)
        XCTAssertEqual(fetched.id, item.id)
        XCTAssertTrue(fetched.isReserve)
        XCTAssertFalse(fetched.isPantry)
        XCTAssertEqual(try next.fetchCount(FetchDescriptor<UnifiedItem>()), 1)
    }

    /// Runs only against an explicitly copied, offline fixture, never the live store.
    func testPhysicalSnapshotMigrationPreservesEveryEntityIdentity() throws {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReserveMigrationFixture", isDirectory: true)
        let manifest = directory.appendingPathComponent("expected-ids.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw XCTSkip("No offline pre-migration physical snapshot supplied.")
        }
        let expected = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: manifest))
        let privateSchema = Schema([AppSettings.self, ChatMessage.self, ChatConversation.self,
                                    NutritionProfile.self, FoodEntry.self, WeightEntry.self, NutritionDayLog.self])
        let sharedSchema = Schema([UnifiedItem.self, PantryItem.self, GroceryItem.self, UtensilItem.self,
                                   Category.self, DeletedDefaultCategory.self, Recipe.self, RecipeIngredient.self,
                                   RecipeIngredientSection.self, RecipeStep.self, RecipePreparationMedia.self])
        let privateConfig = ModelConfiguration("Private", schema: privateSchema,
                                               url: directory.appendingPathComponent("Private.store"), cloudKitDatabase: .none)
        let sharedConfig = ModelConfiguration("Shared", schema: sharedSchema,
                                              url: directory.appendingPathComponent("Shared.store"), cloudKitDatabase: .none)
        let container = try ModelContainer(for: CloudSyncService.appSchema, configurations: privateConfig, sharedConfig)
        let context = ModelContext(container)
        func compare<T: PersistentModel>(_ type: T.Type, _ table: String, _ id: (T) -> UUID) throws {
            let values = try context.fetch(FetchDescriptor<T>()).map { id($0).uuidString }.sorted()
            XCTAssertEqual(values, expected[table] ?? [], "Identity changed in " + table)
        }
        try compare(AppSettings.self, "ZAPPSETTINGS", { $0.id })
        try compare(ChatMessage.self, "ZCHATMESSAGE", { $0.id })
        try compare(ChatConversation.self, "ZCHATCONVERSATION", { $0.id })
        try compare(NutritionProfile.self, "ZNUTRITIONPROFILE", { $0.id })
        try compare(FoodEntry.self, "ZFOODENTRY", { $0.id })
        try compare(WeightEntry.self, "ZWEIGHTENTRY", { $0.id })
        try compare(NutritionDayLog.self, "ZNUTRITIONDAYLOG", { $0.id })
        try compare(UnifiedItem.self, "ZUNIFIEDITEM", { $0.id })
        try compare(PantryItem.self, "ZPANTRYITEM", { $0.id })
        try compare(GroceryItem.self, "ZGROCERYITEM", { $0.id })
        try compare(UtensilItem.self, "ZUTENSILITEM", { $0.id })
        try compare(Category.self, "ZCATEGORY", { $0.id })
        try compare(DeletedDefaultCategory.self, "ZDELETEDDEFAULTCATEGORY", { $0.id })
        try compare(Recipe.self, "ZRECIPE", { $0.id })
        try compare(RecipeIngredient.self, "ZRECIPEINGREDIENT", { $0.id })
        try compare(RecipeIngredientSection.self, "ZRECIPEINGREDIENTSECTION", { $0.id })
        try compare(RecipeStep.self, "ZRECIPESTEP", { $0.id })
        try compare(RecipePreparationMedia.self, "ZRECIPEPREPARATIONMEDIA", { $0.id })
        XCTAssertTrue(try context.fetch(FetchDescriptor<UnifiedItem>()).allSatisfy { !$0.isReserve })
        try context.save()
    }
}

#if os(iOS)
import UIKit

@MainActor
final class RecipeCoverPaletteTests: XCTestCase {
    func testPaletteFollowsDifferentCoverColors() async throws {
        for color in [(0.2, 0.7, 0.1), (0.8, 0.2, 0.4)] {
            let data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { renderer in
                renderer.cgContext.setFillColor(UIColor(red: color.0, green: color.1, blue: color.2, alpha: 1).cgColor)
                renderer.cgContext.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            }
            let result = await SavoriaImagePalette.averageRGB(from: data)
            let rgb = try XCTUnwrap(result)
            XCTAssertEqual(rgb.x, color.0, accuracy: 2.0 / 255)
            XCTAssertEqual(rgb.y, color.1, accuracy: 2.0 / 255)
            XCTAssertEqual(rgb.z, color.2, accuracy: 2.0 / 255)
        }
    }

    func testInvalidCoverUsesFallbackInsteadOfInvalidRGB() async {
        let result = await SavoriaImagePalette.averageRGB(from: Data([0, 1, 2]))
        XCTAssertNil(result)
    }
}
#endif
