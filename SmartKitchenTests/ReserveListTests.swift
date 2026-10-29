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
final class BulkListActionTests: XCTestCase {
    func testMoveAppliesOnlyToSelectedItemsStillInSourceAndPreservesDetails() throws {
        let container = try ModelContainer(for: UnifiedItem.self, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let first = UnifiedItem(name: "First", descriptionText: "Details", imageData: Data([1, 2]),
                                quantity: 2, unit: "kg", isPantry: true, defaultExpiryDays: 7, isFixed: true)
        let second = UnifiedItem(name: "Second", isPantry: true)
        let unselected = UnifiedItem(name: "Unselected", isPantry: true)
        let stale = UnifiedItem(name: "Already moved", isGrocery: true)
        for item in [first, second, unselected, stale] { context.insert(item) }
        try context.save()
        let ids = Set([first.id, second.id, stale.id, UUID()])
        try ListBulkMutation.apply(.move(.reserve), selectedIDs: ids, source: .pantry, in: context)
        XCTAssertEqual(first.activeFlags, [.reserve])
        XCTAssertEqual(second.activeFlags, [.reserve])
        XCTAssertEqual(unselected.activeFlags, [.pantry])
        XCTAssertEqual(stale.activeFlags, [.grocery])
        XCTAssertTrue(ids.contains(first.id))
        XCTAssertEqual(first.descriptionText, "Details")
        XCTAssertEqual(first.imageData, Data([1, 2]))
        XCTAssertEqual(first.quantity, 2)
        XCTAssertEqual(first.unit, "kg")
        XCTAssertEqual(first.defaultExpiryDays, 7)
        XCTAssertTrue(first.isFixed)
        let saved = try ModelContext(container).fetch(FetchDescriptor<UnifiedItem>())
        XCTAssertEqual(saved.count, 4)
        XCTAssertEqual(Set(saved.filter(\.isReserve).map(\.id)), Set([first.id, second.id]))
    }

    func testBulkCategoryWorksForUtensilsWithoutChangingMembershipOrOtherItems() throws {
        let container = try ModelContainer(for: UnifiedItem.self, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let utensils = (0..<2).map { UnifiedItem(name: "Utensil \($0)", isUtensil: true) }
        let pantry = UnifiedItem(name: "Pantry", isPantry: true)
        for item in utensils + [pantry] { context.insert(item) }
        try context.save()
        let selected = Set((utensils + [pantry]).map(\.id))
        try ListBulkMutation.apply(.category("Tools"), selectedIDs: selected, source: .utensil, in: context)
        for item in utensils {
            XCTAssertEqual(item.category, "Tools")
            XCTAssertEqual(item.activeFlags, [.utensil])
        }
        XCTAssertEqual(pantry.category, "Outros")
        try ListBulkMutation.apply(.move(.grocery), selectedIDs: selected, source: .utensil, in: context)
        XCTAssertTrue(utensils.allSatisfy(\.isUtensil))
        XCTAssertTrue(pantry.isPantry)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UnifiedItem>()), 3)
    }
}

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

final class AdaptiveWorkspaceLayoutTests: XCTestCase {
    func testPhoneAndNarrowMultitaskingKeepOneCompletePage() {
        for size in [CGSize(width: 402, height: 874), CGSize(width: 600, height: 1000),
                     CGSize(width: 874, height: 360)] {
            XCTAssertFalse(SavoriaWorkspaceMetrics.supportsCompanion(size: size), "\(size)")
        }
    }

    func testDuoAndIPadHaveRoomForBothFunctionalPanels() {
        for size in [CGSize(width: 840, height: 780), CGSize(width: 780, height: 840),
                     CGSize(width: 834, height: 1194), CGSize(width: 1194, height: 834)] {
            XCTAssertTrue(SavoriaWorkspaceMetrics.supportsCompanion(size: size), "\(size)")
        }
    }

    func testAccessibilityTextKeepsTheFullPrimaryFlowReachable() {
        XCTAssertFalse(SavoriaWorkspaceMetrics.supportsCompanion(
            size: CGSize(width: 1194, height: 834), accessibilitySize: true))
    }
}


final class RecipeWorkspaceNavigationTests: XCTestCase {
    func testClosingDetailBeforeFoldingDoesNotResurrectIt() {
        var navigation = SavoriaRecipeWorkspaceNavigation()
        navigation.open(UUID(), expanded: true)
        navigation.selection = nil // the library/notebook clears the shared binding
        navigation.resize(expanded: false)
        XCTAssertTrue(navigation.path.isEmpty)
        XCTAssertNil(navigation.selection)
    }

    func testFoldingAndUnfoldingPreserveTheActiveRecipe() {
        let id = UUID()
        var navigation = SavoriaRecipeWorkspaceNavigation()
        navigation.open(id, expanded: true)
        XCTAssertTrue(navigation.path.isEmpty)
        navigation.resize(expanded: false)
        XCTAssertEqual(navigation.path, [id])
        navigation.resize(expanded: true)
        XCTAssertEqual(navigation.selection, id)
        XCTAssertTrue(navigation.path.isEmpty)
    }

    func testBackFromCompactDetailClearsSelection() {
        var navigation = SavoriaRecipeWorkspaceNavigation()
        navigation.open(UUID(), expanded: false)
        navigation.path = []
        navigation.stackChanged(expanded: false)
        navigation.resize(expanded: true)
        XCTAssertNil(navigation.selection)
        XCTAssertTrue(navigation.path.isEmpty)
    }
}

@MainActor
final class PlainTextExportTests: XCTestCase {
    func testListKeepsRequestedOrderQuantitiesNotesAndAttributionWithoutMutation() {
        let milk = UnifiedItem(name: "Leite", descriptionText: "Sem lactose", quantity: 2, unit: "L", isGrocery: true)
        let rice = UnifiedItem(name: "Arroz", isPantry: true)
        let text = SavoriaPlainTextExport.list(title: "Mercado", items: [milk, rice])
        XCTAssertLessThan(text.range(of: "Leite")!.lowerBound, text.range(of: "Arroz")!.lowerBound)
        XCTAssertTrue(text.contains("2 L"))
        XCTAssertTrue(text.contains("Sem lactose"))
        XCTAssertTrue(text.hasSuffix(SavoriaPlainTextExport.attribution))
        XCTAssertEqual(milk.quantity, 2)
        XCTAssertTrue(milk.isGrocery)
        XCTAssertFalse(milk.isPantry)
        XCTAssertTrue(rice.isPantry)
    }

    func testRecipeScalesOnlyExportAndKeepsSectionsStepsAndSource() {
        let section = RecipeIngredientSection(title: "Molho", subtitle: "Misture à parte")
        let rice = RecipeIngredient(name: "Arroz", quantity: 1, unit: "g", sortOrder: 1)
        let sauce = RecipeIngredient(name: "Tomate", quantity: 2, unit: "g", sortOrder: 0, sectionID: section.id)
        let recipe = Recipe(name: "Arroz com molho", ingredients: [sauce, rice], steps: [
            RecipeStep(order: 2, instruction: "Sirva."), RecipeStep(order: 1, instruction: "Cozinhe.")
        ], externalURLString: "https://example.com/recipe", prepTime: 10, servings: 2)
        recipe.ingredientSections = [section]
        let text = SavoriaPlainTextExport.recipe(recipe, servings: 4)
        XCTAssertTrue(text.contains("Arroz — 2 g"))
        XCTAssertTrue(text.contains("Tomate — 4 g"))
        XCTAssertTrue(text.contains("Molho\nMisture à parte"))
        XCTAssertTrue(text.contains("1. Cozinhe.\n2. Sirva."))
        XCTAssertTrue(text.contains("https://example.com/recipe"))
        XCTAssertTrue(text.hasSuffix(SavoriaPlainTextExport.attribution))
        XCTAssertEqual(recipe.servings, 2)
        XCTAssertEqual(rice.quantity, 1)
        XCTAssertEqual(sauce.quantity, 2)
    }

    func testOrphanIngredientsRemainAndLocalSourceIsNotShared() {
        let ingredient = RecipeIngredient(name: "Sal", sectionID: UUID())
        let recipe = Recipe(name: "Teste", ingredients: [ingredient], externalURLString: "file:///private/photo.jpg")
        let text = SavoriaPlainTextExport.recipe(recipe)
        XCTAssertTrue(text.contains("Sal"))
        XCTAssertFalse(text.contains("file:///"))
        XCTAssertTrue(SavoriaPlainTextExport.list(title: "Mercado", items: []).hasSuffix(SavoriaPlainTextExport.attribution))
    }
}

#if os(iOS)
import SwiftUI
import StoreKitTest

/// Native-scene rendering only. Fixtures never enter the application's stores or CloudKit.
@MainActor
final class AdaptiveWorkspaceRenderingTests: XCTestCase {
    private func fixture() throws -> (ModelContainer, UUID) {
        let container = try ModelContainer(for: CloudSyncService.appSchema, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let settings = AppSettings()
        settings.hasCompletedOnboarding = true
        settings.showReserve = true
        context.insert(settings)
        for name in ["Arroz", "Ovos", "Tomate", "Queijo"] {
            context.insert(UnifiedItem(name: name, quantity: 2, unit: "un", isPantry: true))
        }
        context.insert(UnifiedItem(name: "Leite", isGrocery: true))
        context.insert(UnifiedItem(name: "Aveia", isReserve: true))
        let recipe = Recipe(name: "Arroz com ovos e tomate", ingredients: [
            RecipeIngredient(name: "Arroz", quantity: 1, unit: "xícara"),
            RecipeIngredient(name: "Ovos", quantity: 2, unit: "un")
        ], steps: [RecipeStep(order: 1, instruction: "Cozinhe o arroz e prepare os ovos.")], prepTime: 10)
        context.insert(recipe)
        let profile = NutritionProfile()
        profile.hasCompletedOnboarding = true
        context.insert(profile)
        try context.save()
        return (container, recipe.id)
    }

    private func render(_ root: AnyView, name: String,
                        style: UIUserInterfaceStyle = .light,
                        layoutReady: @escaping () -> Bool = { true }) async throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = style
        window.windowLevel = .normal + 1
        let ready = expectation(description: "Native layout: " + name)
        let localeIdentifier = ProcessInfo.processInfo.environment["SAVORIA_TEST_LOCALE"]
        let localizedRoot = root.environment(\.locale, localeIdentifier.map(Locale.init(identifier:)) ?? .current)
        let controller = UIHostingController(rootView: localizedRoot.environment(\.scenePhase, .active).onAppear { ready.fulfill() })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        await fulfillment(of: [ready], timeout: 10)
        // Wait for native display commits, including geometry/query-driven updates.
        // No wall-clock sleep and no production bootstrap/test-mode changes.
        let committed = expectation(description: "Display commits: " + name)
        let frames = WorkspaceDisplayCommits(isReady: {
            guard layoutReady() else { return false }
            if #available(iOS 27.1, *) {
                return window.windowScene?.statusBarManager?.isStatusBarHidden ==
                    (window.traitCollection.verticalBarEdge != .unspecified)
            }
            return true
        }) { committed.fulfill() }
        frames.start()
        await fulfillment(of: [committed], timeout: 10)
        frames.stop()
        XCTAssertGreaterThan(controller.view.bounds.width, 300)
        XCTAssertGreaterThan(controller.view.bounds.height, 300)
        if name == "native-page-home" {
            func descendants(_ view: UIView) -> [UIView] {
                view.subviews.flatMap { [$0] + descendants($0) }
            }
            let visible = descendants(window).filter { !$0.isHidden && $0.alpha > 0 &&
                !$0.bounds.isEmpty && $0.convert($0.bounds, to: window).intersects(window.bounds) }
            let bars = visible.compactMap { $0 as? UITabBar }
            let inputs = visible.compactMap { $0 as? UITextField }
            // iPad's native top tab switcher is not a UITabBar. When a
            // bottom/side UITabBar exists, assert its actual frame directly.
            XCTAssertFalse(inputs.isEmpty, "The single assistant field must be present")
            if SavoriaWorkspaceMetrics.supportsCompanion(size: window.bounds.size) {
                let input = try XCTUnwrap(inputs.first)
                let inputFrame = input.convert(input.bounds, to: window)
                XCTAssertLessThan(window.bounds.maxY - inputFrame.midY, 52,
                    "The floating footer must use the bottom edge, not sit above a reserved strip")
                let scrollFrames = visible.compactMap { $0 as? UIScrollView }
                    .filter { $0.bounds.height > 150 }
                    .map { $0.convert($0.bounds, to: window) }
                XCTAssertTrue(scrollFrames.contains { $0.maxY >= window.bounds.maxY - 1 },
                    "The scroll viewport must continue behind the floating footer: \(scrollFrames)")
            }
            for bar in bars {
                let barFrame = bar.convert(bar.bounds, to: window).insetBy(dx: 1, dy: 1)
                for input in inputs {
                    let inputFrame = input.convert(input.bounds, to: window).insetBy(dx: 1, dy: 1)
                    XCTAssertFalse(inputFrame.intersects(barFrame),
                                   "Assistant field overlaps native tab navigation: \(inputFrame) / \(barFrame)")
                }
            }
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        // Home can now draw cards/text at the physical bottom. Sample the
        // sparse geometry fixture for the surface, not arbitrary Home content.
        if name == "native-workspace-geometry", let pixels = image.cgImage {
            for fraction in [0.25, 0.75] {
                let rect = CGRect(x: Double(pixels.width) * fraction, y: Double(pixels.height - 4), width: 1, height: 1)
                let sample = try XCTUnwrap(pixels.cropping(to: rect))
                var rgba = [UInt8](repeating: 0, count: 4)
                let context = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                XCTAssertTrue(rgba.prefix(3).allSatisfy { $0 > 224 },
                              "The light main surface must reach the bottom edge behind navigation: \(rgba)")
            }
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        return window
    }

    func testNativePanelsRespectReservedRegions() async throws {
        let (container, _) = try fixture()
        let measurements = WorkspaceRenderMeasurements()
        let search = SearchBarState()
        let root = WorkspaceGeometryFixture(measurements: measurements)
            .modelContainer(container).environmentObject(search)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let expectsExpanded = SavoriaWorkspaceMetrics.supportsCompanion(size: scene.coordinateSpace.bounds.size)
        let window = try await render(AnyView(root), name: "native-workspace-geometry", layoutReady: {
            if expectsExpanded && !measurements.expanded { return false }
            if measurements.expanded {
                guard let primary = measurements.primaryContent, let secondary = measurements.secondary else { return false }
                if secondary.minX > primary.minX + 1 { return primary.maxX <= secondary.minX + 1 }
            }
            return true
        })
        defer { window.isHidden = true; window.rootViewController = nil }
        let primary = try XCTUnwrap(measurements.primary)
        XCTAssertGreaterThan(primary.width, 100)
        XCTAssertGreaterThanOrEqual(primary.minX, -1)
        XCTAssertGreaterThanOrEqual(primary.minY, -1)
        if measurements.expanded {
            let secondary = try XCTUnwrap(measurements.secondary)
            XCTAssertGreaterThan(secondary.width, 100)
            let content = try XCTUnwrap(measurements.primaryContent)
            XCTAssertFalse(content.insetBy(dx: 1, dy: 1).intersects(secondary.insetBy(dx: 1, dy: 1)))
            XCTAssertGreaterThan(primary.width, content.width + 100, "The one page header must span both content regions")
            if measurements.reserved.isEmpty {
                XCTAssertEqual((content.midX + secondary.midX) / 2, window.bounds.midX, accuracy: 1,
                               "A released status region must not leave both panels shifted to one side")
            }
            XCTAssertEqual(content.minY, secondary.minY, accuracy: 1, "Both halves start in the same shared surface")
            for reserved in measurements.reserved where reserved.width > 0 && reserved.height > 0 {
                XCTAssertFalse(content.intersects(reserved), "Content overlaps reserved region: \(reserved)")
                XCTAssertFalse(secondary.intersects(reserved), "Content overlaps reserved region: \(reserved)")
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "expanded": measurements.expanded,
            "window": String(describing: window.bounds),
            "safeArea": String(describing: window.safeAreaInsets),
            "primaryHeader": String(describing: primary),
            "primaryContent": String(describing: measurements.primaryContent),
            "secondaryContent": measurements.secondary.map { String(describing: $0) } ?? "hidden",
            "reserved": measurements.reserved.map { String(describing: $0) }
        ], options: [.sortedKeys])
        let evidence = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        evidence.name = "native-workspace-frames"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testNativeFunctionalPagesWithIsolatedFixtures() async throws {
        let (container, recipeID) = try fixture()
        let search = SearchBarState()
        let service = UniversalSearchService()
        let subscription = SubscriptionManager(observesTransactions: false)
        for (name, tab, page) in [
            ("home", AppTab.assistant, AnyView(ContentView())),
            ("lists", .lists, AnyView(ListsTabView())),
            ("recipes", .recipes, AnyView(RecipesView()
                .environment(\.savoriaWorkspaceRecipeSelection, .constant(recipeID)))),
            ("nutrition", .nutrients, AnyView(NutrientsView())),
            ("assistant", .commandBar, AnyView(FullscreenAssistantView(
                searchBarState: search, searchService: service, onAction: { _ in },
                onOpenFoodCameraDirect: {}, onOpenFoodGalleryDirect: {},
                pendingChatQuery: .constant(nil), pendingOpenChat: .constant(false),
                pendingNewConversation: .constant(false), pendingShowHistory: .constant(false),
                presentation: .tab)))
        ] {
            let root = WorkspacePageFixture(content: page)
                .environment(\.activeAppTab, tab)
                .environmentObject(search).environment(subscription).modelContainer(container)
            let window = try await render(AnyView(root), name: "native-page-" + name)
            window.isHidden = true
            window.rootViewController = nil
        }
        // Rendering must not change membership, recipes, or create chat requests.
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<UnifiedItem>()), 6)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Recipe>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ChatMessage>()), 0)
    }

    /// App Store assets use production views over memory-only demonstration data.
    /// No model bootstrap, personal stores, purchases or inference requests.
    func testAppStoreDemonstrationCaptures() async throws {
        let captureLanguage = AppLanguage.resolve(identifier:
            ProcessInfo.processInfo.environment["SAVORIA_TEST_LOCALE"] ?? "pt-BR") ?? .ptBR
        let captureLocalization = AppLocalization(language: captureLanguage)
        let fixtureTranslations: [AppLanguage: [String]] = [
            .en: ["Zucchini", "pcs", "Bread with eggs and coffee with milk", "Yogurt with banana and oats"],
            .es: ["Calabacín", "ud", "Pan con huevos y café con leche", "Yogur con plátano y avena"],
            .fr: ["Courgette", "pcs", "Pain aux œufs et café au lait", "Yaourt à la banane et aux flocons d’avoine"],
            .de: ["Zucchini", "Stk.", "Brot mit Eiern und Milchkaffee", "Joghurt mit Banane und Haferflocken"],
            .it: ["Zucchina", "pz", "Pane con uova e caffellatte", "Yogurt con banana e avena"],
            .ja: ["ズッキーニ", "個", "卵とパン、カフェオレ", "バナナとオートミールのヨーグルト"]
        ]
        func fixtureText(_ key: String) -> String {
            guard captureLanguage != .ptBR else { return key }
            let customKeys = ["Abobrinha", "un", "Pão com ovos e café com leite", "Iogurte com banana e aveia"]
            if let index = customKeys.firstIndex(of: key), let values = fixtureTranslations[captureLanguage] {
                return values[index]
            }
            let aliases = ["Peito de Frango": "Peito de frango", "Iogurte Natural": "Iogurte natural",
                "Queijo Minas": "Queijo", "Café em Pó": "Café", "Colher de Sopa": "colher de sopa",
                "Frango grelhado com legumes": "Frango Grelhado com Legumes",
                "Um almoço prático, colorido e cheio de sabor.": "Proteína magra e legumes na chapa.",
                "Corte os legumes. Tempere o frango com sal e azeite.": "Tempere o frango com sal, pimenta e alho.",
                "Grelhe o frango e os legumes até dourarem.": "Salteie os legumes no azeite.",
                "Sirva ainda quente e aproveite.": "Sirva o frango ao lado dos legumes."]
            return captureLocalization.builtInLabel(aliases[key] ?? key)
        }
        let container = try ModelContainer(for: CloudSyncService.appSchema, configurations:
            ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let settings = AppSettings()
        settings.hasCompletedOnboarding = true
        settings.showReserve = false
        settings.recipeGalleryColumns = 2
        settings.pantryDetailLevel = .detailed
        context.insert(settings)
        for (index, value) in [("Tomate", "Frutas", "tomato.png"), ("Alface", "Verduras e Legumes", "lettuce.png"),
                               ("Peito de Frango", "Carnes e Aves", "chicken-raw.png"), ("Ovos", "Laticínios e Ovos", "egg.png"),
                               ("Arroz", "Grãos, Massas e Cereais", "rice.png"), ("Azeite", "Temperos e Condimentos", "olive-oil.png"),
                               ("Banana", "Frutas", "banana.png"), ("Aveia", "Grãos, Massas e Cereais", "oatmeal.png")].enumerated() {
            context.insert(UnifiedItem(name: fixtureText(value.0), category: fixtureText(value.1), quantity: [4.0, 1, 600, 6, 1, 500, 6, 300][index],
                unit: fixtureText(["un", "un", "g", "un", "kg", "ml", "un", "g"][index]), iconName: value.2,
                isPantry: true, pantrySortOrder: index,
                expirationDate: index < 2 ? Calendar.current.date(byAdding: .day, value: index + 2, to: .now) : nil))
        }
        for name in ["Iogurte Natural", "Leite", "Queijo Minas", "Morango"] {
            context.insert(UnifiedItem(name: fixtureText(name), quantity: 1, unit: fixtureText("un"), isGrocery: true))
        }
        context.insert(UnifiedItem(name: fixtureText("Café em Pó"), isReserve: true))
        func cover(_ name: String) throws -> Data {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "images-128"))
            return try Data(contentsOf: url)
        }
        let photo = try cover("onboarding-grilled-chicken-veggies")
        let recipe = Recipe(name: fixtureText("Frango grelhado com legumes"), descriptionText: fixtureText("Um almoço prático, colorido e cheio de sabor."),
            ingredients: [RecipeIngredient(name: fixtureText("Peito de Frango"), quantity: 300, unit: "g", iconName: "chicken-raw.png", sortOrder: 0),
                          RecipeIngredient(name: fixtureText("Tomate"), quantity: 2, unit: fixtureText("un"), sortOrder: 1),
                          RecipeIngredient(name: fixtureText("Azeite"), quantity: 1, unit: fixtureText("Colher de Sopa"), sortOrder: 2),
                          RecipeIngredient(name: fixtureText("Abobrinha"), quantity: 1, unit: fixtureText("un"), sortOrder: 3)],
            steps: [RecipeStep(order: 1, instruction: fixtureText("Corte os legumes. Tempere o frango com sal e azeite."), durationMinutes: 5),
                    RecipeStep(order: 2, instruction: fixtureText("Grelhe o frango e os legumes até dourarem."), durationMinutes: 15),
                    RecipeStep(order: 3, instruction: fixtureText("Sirva ainda quente e aproveite."))],
            imageData: photo, category: fixtureText("Almoço"), prepTime: 5, cookTime: 15, servings: 2, calories: 420, isFavorite: true)
        context.insert(recipe)
        for definition in DataSeeder.defaultDefinitions(for: .recipe) {
            context.insert(Category(name: fixtureText(definition.name), type: .recipe, iconName: definition.iconName))
        }
        for template in OnboardingCatalog.recipeTemplates.filter({ ["caesar-salad", "strawberry-oat-smoothie", "chicken-wrap-hummus", "pancake"].contains($0.id) }) {
            let ingredients = template.ingredients.enumerated().map { index, value in
                RecipeIngredient(name: value.0, quantity: value.1, unit: value.2, iconName: value.3, sortOrder: index)
            }
            let steps = template.steps.enumerated().map { RecipeStep(order: $0.offset + 1, instruction: $0.element) }
            context.insert(Recipe(name: template.name, descriptionText: template.summary, ingredients: ingredients,
                steps: steps, imageData: template.photoFileName.flatMap(IconResolver.imageData(forFilename:)),
                category: fixtureText(template.category), prepTime: template.prepMinutes, cookTime: template.cookMinutes,
                servings: template.servings, calories: template.calories))
        }
        let profile = NutritionProfile()
        profile.hasCompletedOnboarding = true
        profile.overrideCalories = 2200
        profile.overrideProteinG = 120
        profile.overrideCarbsG = 280
        profile.overrideFatG = 65
        context.insert(profile)
        let today = Calendar.current.startOfDay(for: .now)
        context.insert(FoodEntry(name: fixtureText("Pão com ovos e café com leite"), calories: 385, proteinG: 22, carbsG: 38, fatG: 16,
            mealType: .breakfast, timestamp: today.addingTimeInterval(8 * 3600), emoji: "🍳"))
        context.insert(FoodEntry(name: fixtureText("Frango grelhado com legumes"), calories: 420, proteinG: 38, carbsG: 29, fatG: 17,
            mealType: .lunch, timestamp: today.addingTimeInterval(12 * 3600), emoji: "🍗"))
        context.insert(FoodEntry(name: fixtureText("Iogurte com banana e aveia"), calories: 215, proteinG: 12, carbsG: 31, fatG: 5,
            mealType: .snack, timestamp: today.addingTimeInterval(15 * 3600), emoji: "🍌"))
        context.insert(NutritionDayLog(dayStart: today))
        let conversation = ChatConversation(title: "Ideias com a despensa")
        context.insert(conversation)
        let user = ChatMessage(role: .user, content: "O que posso fazer com o que tenho?", conversationId: conversation.id)
        user.timestamp = .now.addingTimeInterval(-60); context.insert(user)
        let ideas: [RecipeQuickIdea] = [
            .init(title: "Omelete de tomate", mainIngredient: "Ovos", category: .quick),
            .init(title: "Frango com arroz", mainIngredient: "Frango", category: .quick),
            .init(title: "Salada com frango", mainIngredient: "Alface", category: .quick),
            .init(title: "Tomate recheado", mainIngredient: "Tomate", category: .unique),
            .init(title: "Panqueca de aveia", mainIngredient: "Aveia", category: .unique),
            .init(title: "Arroz de frigideira", mainIngredient: "Arroz", category: .pantry)]
        let payload = InlineChatView.ResultsPayload(ideas: [], quickIdeas: ideas,
            answer: "Com ovos, frango, arroz e legumes da sua despensa, dá para variar o almoço. Separei algumas ideias para você.",
            localRecipeIDs: [], occasionRaw: nil, refinement: nil, customQuery: user.content, filterByPantry: true)
        context.insert(ChatMessage(role: .assistant, content: payload.encoded(),
            quickActions: [QuickAction(label: "_wizard", prompt: RecipeIdeasSentinel.resultsPrefix)], conversationId: conversation.id))
        try context.save()
        let search = SearchBarState()
        search.aiChatPreset = .recipeIdeas
        let subscription = SubscriptionManager(observesTransactions: false)
        let result = FoodAnalysis(name: fixtureText("Frango grelhado com legumes"), calories: 420, protein: 38, carbs: 29, fat: 17,
            servingSizeGrams: 350, emoji: "🍗", reviewNotes: ["Estimativa para a porção da foto. Revise antes de registrar."])
        let pages: [(String, AnyView, UIUserInterfaceStyle)] = [
            ("home", AnyView(ContentView()), .light),
            ("pantry", AnyView(WorkspacePageFixture(content: AnyView(ListsTabView())).environment(\.activeAppTab, .lists)), .light),
            ("market", AnyView(WorkspacePageFixture(content: AnyView(ListsTabView(initialSubtab: .grocery))).environment(\.activeAppTab, .lists)), .dark),
            ("recipes", AnyView(WorkspacePageFixture(content: AnyView(RecipesView())).environment(\.activeAppTab, .recipes)), .light),
            ("recipe", AnyView(NavigationStack { RecipeDetailView(recipe: recipe) }), .light),
            ("cooking", AnyView(CookingModeView(recipe: recipe)), .light),
            ("assistant", AnyView(InlineChatView(existingConversationId: conversation.id, onDismiss: {}, onShowHistory: {}, searchBarState: search)), .light),
            ("food", AnyView(NavigationStack { FoodResultView(analysis: result, image: UIImage(data: photo), logDate: .now) }), .light),
            ("nutrition", AnyView(WorkspacePageFixture(content: AnyView(NutrientsView())).environment(\.activeAppTab, .nutrients)), .dark)]
        let marketingOnly = ProcessInfo.processInfo.environment["SAVORIA_MARKETING_CAPTURE"] == "1"
        let marketingPages: Set<String> = ["home", "pantry", "market", "recipes", "recipe", "nutrition"]
        for (name, page, style) in pages where !marketingOnly || marketingPages.contains(name) {
            let root = page.modelContainer(container).environmentObject(search).environment(subscription)
            let window = try await render(AnyView(root), name: fixtureText("store-") + name, style: style)
            if marketingOnly && name == "recipe" {
                func recipeScrollViews(_ view: UIView) -> [UIScrollView] {
                    view.subviews.flatMap { child in (child as? UIScrollView).map { [$0] } ?? recipeScrollViews(child) }
                }
                let scroll = try XCTUnwrap(recipeScrollViews(window).max(by: { $0.contentSize.height < $1.contentSize.height }))
                scroll.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
                let settled = expectation(description: "Localized ingredients scroll committed")
                let commits = WorkspaceDisplayCommits(isReady: { true }) { settled.fulfill() }
                commits.start(); await fulfillment(of: [settled], timeout: 10); commits.stop()
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "store-recipe-scrolled"; attachment.lifetime = .keepAlways; add(attachment)
            }
            if name == "food" {
                func scrollViews(_ view: UIView) -> [UIScrollView] {
                    view.subviews.flatMap { child in (child as? UIScrollView).map { [$0] } ?? scrollViews(child) }
                }
                if let scroll = scrollViews(window).max(by: { $0.contentSize.height < $1.contentSize.height }) {
                    scroll.setContentOffset(CGPoint(x: 0, y: 460), animated: false)
                    let settled = expectation(description: "Food detail scroll committed")
                    let commits = WorkspaceDisplayCommits(isReady: { true }) { settled.fulfill() }
                    commits.start(); await fulfillment(of: [settled], timeout: 10); commits.stop()
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "store-food-details"; attachment.lifetime = .keepAlways; add(attachment)
                }
            }
            window.isHidden = true; window.rootViewController = nil
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UnifiedItem>()), 13)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ChatMessage>()), 2)
    }

    func testNativeReportPreviewDoesNotSendOrAttachUserData() async throws {
        // A focused run may start before the hosted app finishes activating.
        // Observe that lifecycle boundary rather than relying on earlier tests.
        let activated = expectation(description: "Report preview scene is active")
        let observer = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { _ in activated.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        if UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }) {
            activated.fulfill()
        }
        await fulfillment(of: [activated], timeout: 10)
        let window = try await render(
            AnyView(AssistantResponseReportView(response: "SYNTHETIC RESPONSE FOR LOCAL PREVIEW")),
            name: "native-assistant-report-preview")
        defer { window.isHidden = true; window.rootViewController = nil }
        // Opening the preview has no model container or network dependency.
        // Email and clipboard actions remain explicit user actions.
        XCTAssertNotNil(window.rootViewController)
    }

    func testNativeStructuredAssistantResponsesKeepTheirReportAction() async throws {
        let (container, recipeID) = try fixture()
        let detail = "**Arroz com ovos**\n\n**Ingredientes**\n- 1 xícara de arroz\n- 2 ovos\n\n**Modo de Preparo**\n1. Cozinhe o arroz e prepare os ovos."
        XCTAssertNotNil(RecipeCardData.parse(content: detail))
        let cases: [(String, String, [UUID])] = [
            ("detail", detail, []),
            ("attached", "", [recipeID]),
            ("options", "**Arroz com ovos** — Uma opção prática.\n**Omelete de tomate** — Outra ideia.", [])
        ]
        for (name, content, recipeIDs) in cases {
            let conversation = ChatConversation(title: "Report fixture " + name)
            container.mainContext.insert(conversation)
            container.mainContext.insert(ChatMessage(role: .assistant, content: content,
                attachedRecipeIds: recipeIDs, conversationId: conversation.id))
            try container.mainContext.save()
            let window = try await render(AnyView(InlineChatView(existingConversationId: conversation.id,
                onDismiss: {}, onShowHistory: {}).modelContainer(container)),
                name: "native-report-" + name)
            window.isHidden = true
            window.rootViewController = nil
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ChatMessage>()), 3)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Recipe>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<UnifiedItem>()), 6)
    }

    /// Opt-in interactive E2E: the normal production views and routing run over
    /// the existing memory-only fixture; no onboarding or customer store changes.
    func testNativeAIConsentCanBeDeclinedWithoutSendingData() async throws {
        guard ProcessInfo.processInfo.environment["SAVORIA_VALIDATE_AI_CONSENT_UI"] == "1" else {
            throw XCTSkip("Requires a native refusal in the selected Simulator")
        }
        let (container, _) = try fixture()
        let root = ContentView().environmentObject(SearchBarState())
            .environment(SubscriptionManager(observesTransactions: false)).modelContainer(container)
        let window = try await render(AnyView(root), name: "native-consent-local-content")
        defer { window.isHidden = true; window.rootViewController = nil }
        let suite = "Savoria.NativeConsentTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = AIDataConsent(defaults: defaults)
        let refused = expectation(description: "Native permission refused")
        let request = Task {
            do { try await consent.request(); XCTFail("This test requires choosing Not now") }
            catch { XCTAssertTrue(error is CancellationError) }
            refused.fulfill()
        }
        defer { request.cancel() }
        print("SAVORIA_CONSENT_UI_READY_CHOOSE_NOT_NOW")
        await fulfillment(of: [refused], timeout: 90)
        XCTAssertFalse(consent.isGranted)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<UnifiedItem>()), 6)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ChatMessage>()), 0)
    }

    func testPullOpensAssistantWithKeyboardInIsolatedFixture() async throws {
        guard ProcessInfo.processInfo.environment["SAVORIA_VALIDATE_PULL_INTERACTION"] == "1" else {
            throw XCTSkip("Requires a native drag in the selected Simulator")
        }
        let (container, _) = try fixture()
        let search = SearchBarState()
        let keyboardShown = expectation(description: "Virtual keyboard shown")
        let keyboardToken = NotificationCenter.default.addObserver(forName: UIResponder.keyboardDidShowNotification,
            object: nil, queue: .main) { _ in keyboardShown.fulfill() }
        defer { NotificationCenter.default.removeObserver(keyboardToken) }
        let released = expectation(description: "Native pull released")
        released.assertForOverFulfill = true
        let token = NotificationCenter.default.addObserver(forName: .openAssistantFromWidget,
            object: nil, queue: .main) { _ in released.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }
        let root = ContentView().environmentObject(search)
            .environment(SubscriptionManager(observesTransactions: false)).modelContainer(container)
        let window = try await render(AnyView(root), name: "native-pull-ready")
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil }
        print("SAVORIA_PULL_E2E_READY")
        await fulfillment(of: [released], timeout: 90)
        func fields(_ view: UIView) -> [UITextField] {
            view.subviews.flatMap { child -> [UITextField] in
                (child as? UITextField).map { [$0] } ?? fields(child)
            }
        }
        let focused = expectation(description: "Assistant field focused without a tap")
        let commits = WorkspaceDisplayCommits(isReady: {
            fields(window).contains { $0.isFirstResponder }
        }) { focused.fulfill() }
        commits.start()
        await fulfillment(of: [focused, keyboardShown], timeout: 10)
        commits.stop()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let capture = XCTAttachment(image: image)
        capture.name = "native-pull-assistant-keyboard"; capture.lifetime = .keepAlways; add(capture)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ChatMessage>()), 0)
    }

    func testNativeOnboardingRecipeGridAndProjection() async throws {
        let (container, _) = try fixture()
        for (name, step) in [("recipe-selection", OnboardingStep.selectRecipes),
                             ("goal-projection", .goalProjection), ("nutrition-coach", .nutritionCoach)] {
            let readiness = WorkspaceRenderMeasurements()
            let root = OnboardingFlowView(isPreview: true, initialStep: step, onFinish: {})
                .modelContainer(container)
                .onPreferenceChange(OnboardingProjectionReadyKey.self) { readiness.presentationReady = $0 }
            let window = try await render(AnyView(root), name: "native-onboarding-" + name,
                layoutReady: { step != .goalProjection || readiness.presentationReady })
            window.isHidden = true; window.rootViewController = nil
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<UnifiedItem>()), 6)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Recipe>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ChatMessage>()), 0)
    }

    func testNativePlainTextSharePreviewDoesNotWriteUserData() async throws {
        let activated = expectation(description: "Share preview scene active")
        let observer = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification,
            object: nil, queue: .main) { _ in activated.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        if UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }) {
            activated.fulfill()
        }
        await fulfillment(of: [activated], timeout: 10)
        let (container, recipeID) = try fixture()
        let recipe = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Recipe>()).first { $0.id == recipeID })
        let payload = PlainTextSharePayload(title: recipe.name, text: SavoriaPlainTextExport.recipe(recipe))
        let window = try await render(AnyView(PlainTextShareSheet(payload: payload)), name: "native-plain-text-share-preview")
        defer { window.isHidden = true; window.rootViewController = nil }
        let detail = try await render(AnyView(NavigationStack {
            RecipeDetailView(recipe: recipe)
        }.modelContainer(container)), name: "native-recipe-share-entry")
        defer { detail.isHidden = true; detail.rootViewController = nil }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<UnifiedItem>()), 6)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Recipe>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ChatMessage>()), 0)
    }

    func testNativePaywallReviewLayoutWithoutWritingUserData() async throws {
        let activated = expectation(description: "Paywall scene active")
        let observer = NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification,
            object: nil, queue: .main) { _ in activated.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }
        if UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }) {
            activated.fulfill()
        }
        await fulfillment(of: [activated], timeout: 10)
        // A local layout fixture, not proof of a Sandbox purchase. Match the
        // currently verified ASC catalogue: neither subscription has a trial.
        let catalogueURL = try XCTUnwrap(Bundle.main.url(forResource: "Configuration", withExtension: "storekit"))
        var catalogue = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: catalogueURL)) as? [String: Any])
        var groups = try XCTUnwrap(catalogue["subscriptionGroups"] as? [[String: Any]])
        var plans = try XCTUnwrap(groups[0]["subscriptions"] as? [[String: Any]])
        for index in plans.indices { plans[index]["introductoryOffer"] = NSNull() }
        groups[0]["subscriptions"] = plans
        catalogue["subscriptionGroups"] = groups
        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".storekit")
        try JSONSerialization.data(withJSONObject: catalogue).write(to: localURL)
        defer { try? FileManager.default.removeItem(at: localURL) }
        let session = try SKTestSession(contentsOf: localURL)
        session.disableDialogs = true
        defer { withExtendedLifetime(session) {} }
        let (container, _) = try fixture()
        let root = PaywallStepView(state: OnboardingState(), onFinish: { _ in
            XCTFail("Review capture must never purchase or complete onboarding")
        }).modelContainer(container)
        let window = try await render(AnyView(root), name: "native-paywall-review-layout-local-catalogue")
        defer { window.isHidden = true; window.rootViewController = nil }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<UnifiedItem>()), 6)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ChatMessage>()), 0)
    }

    func testNativeOnboardingSystemChrome() async throws {
        let (container, _) = try fixture()
        let root = OnboardingFlowView(isPreview: true, initialStep: .overview, onFinish: {})
            .modelContainer(container)
        let window = try await render(AnyView(root), name: "native-onboarding-system-chrome")
        defer { window.isHidden = true; window.rootViewController = nil }
        let hidden = try XCTUnwrap(window.windowScene?.statusBarManager?.isStatusBarHidden)
        if #available(iOS 27.1, *) {
            XCTAssertEqual(hidden, window.traitCollection.verticalBarEdge != .unspecified,
                           "Status visibility must follow the system preference, including after disabling the vertical rail")
        }
        let evidence = try JSONSerialization.data(withJSONObject: [
            "statusBarHidden": hidden,
            "safeArea": String(describing: window.safeAreaInsets),
            "window": String(describing: window.bounds)
        ], options: [.sortedKeys])
        let attachment = XCTAttachment(data: evidence, uniformTypeIdentifier: "public.json")
        attachment.name = "native-system-chrome-frames"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<UnifiedItem>()), 6)
    }
}

@MainActor
private final class WorkspaceDisplayCommits: NSObject {
    private var link: CADisplayLink?
    private var frames = 0
    private let completion: () -> Void
    private let isReady: () -> Bool
    init(isReady: @escaping () -> Bool = { true }, completion: @escaping () -> Void) {
        self.isReady = isReady
        self.completion = completion
    }
    func start() {
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    @objc private func tick() {
        frames = isReady() ? frames + 1 : 0
        if frames == 6 { stop(); completion() }
    }
}

@MainActor
private final class WorkspaceRenderMeasurements {
    var presentationReady = false
    var expanded = false
    var primary: CGRect?
    var primaryContent: CGRect?
    var secondary: CGRect?
    var reserved: [CGRect] = []
}

private struct WorkspaceGeometryReport: Equatable {
    let expanded: Bool
    let reserved: [CGRect]
}

private struct WorkspacePanelBoundsKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct WorkspacePanelFrames: Equatable {
    var primary: CGRect?
    var content: CGRect?
    var secondary: CGRect?
}

private struct WorkspaceGeometryFixture: View {
    let measurements: WorkspaceRenderMeasurements
    @State private var expanded = false
    var body: some View {
        NavigationStack {
            ExpandedPageLayout(pageTheme: .home, companion: {
                AnyView(PantryView(searchText: "", sortOption: .custom, filterOption: .all, expiringLeadDays: 30)
                    .anchorPreference(key: WorkspacePanelBoundsKey.self, value: .bounds) { ["secondary": $0] })
            }, header: { inverted in
                PageHeader(title: "Savoria", isInverted: inverted) {
                    HStack { SettingsButton(); GlassGroupButton(systemImage: "plus") {} }
                }
                .anchorPreference(key: WorkspacePanelBoundsKey.self, value: .bounds) { ["header": $0] }
            }, content: {
                PantryView(searchText: "", sortOption: .custom, filterOption: .all, expiringLeadDays: 30)
                    .anchorPreference(key: WorkspacePanelBoundsKey.self, value: .bounds) { ["content": $0] }
            }, infoContent: {
                Text("Ingredientes disponíveis para cozinhar")
            })
            .environment(\.savoriaWorkspaceExpanded, expanded)
            .toolbar(.hidden, for: .navigationBar)
        }
        .onGeometryChange(for: WorkspaceGeometryReport.self) { proxy in
            var reserved: [CGRect] = []
            if #available(iOS 27.1, *) {
                let origin = proxy.frame(in: .global).origin
                reserved = (proxy.reservedRegions(kind: .division) + proxy.reservedRegions(kind: .occlusion))
                    .map { $0.frame.offsetBy(dx: origin.x, dy: origin.y) }
            }
            return WorkspaceGeometryReport(expanded: SavoriaWorkspaceMetrics.supportsCompanion(geometry: proxy),
                                           reserved: reserved)
        } action: {
            expanded = $0.expanded
            measurements.expanded = $0.expanded
            measurements.reserved = $0.reserved
        }
        .overlayPreferenceValue(WorkspacePanelBoundsKey.self) { bounds in
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                let frames = WorkspacePanelFrames(
                    primary: bounds["header"].map { proxy[$0].offsetBy(dx: origin.x, dy: origin.y) },
                    content: bounds["content"].map { proxy[$0].offsetBy(dx: origin.x, dy: origin.y) },
                    secondary: bounds["secondary"].map { proxy[$0].offsetBy(dx: origin.x, dy: origin.y) })
                Color.clear.onChange(of: frames, initial: true) { _, value in
                    measurements.primary = value.primary
                    measurements.primaryContent = value.content
                    measurements.secondary = value.secondary
                }
            }.allowsHitTesting(false)
        }
        .savoriaSystemChrome()
    }
}

private struct WorkspacePageFixture: View {
    let content: AnyView
    @State private var expanded = false
    var body: some View {
        NavigationStack { content.environment(\.savoriaWorkspaceExpanded, expanded) }
            .onGeometryChange(for: Bool.self) {
                SavoriaWorkspaceMetrics.supportsCompanion(geometry: $0)
            } action: { expanded = $0 }
            .savoriaSystemChrome()
    }
}
#endif


final class OriginalListWorkspaceSelectionTests: XCTestCase {
    func testPantryAndMarketStartOnOppositeSides() {
        XCTAssertEqual(ListWorkspaceSelection().primary, .pantry)
        XCTAssertEqual(ListWorkspaceSelection().secondary, .grocery)
        XCTAssertEqual(ListWorkspaceSelection(primary: .grocery).secondary, .pantry)
    }
    func testSelectingTheOtherVisibleListSwapsWithoutDuplication() {
        var state = ListWorkspaceSelection()
        state.selectPrimary(.grocery)
        XCTAssertEqual(state.primary, .grocery)
        XCTAssertEqual(state.secondary, .pantry)
        state.selectSecondary(.grocery)
        XCTAssertEqual(state.primary, .pantry)
        XCTAssertEqual(state.secondary, .grocery)
        state.selectSecondary(.reserve)
        XCTAssertEqual(state.primary, .pantry)
        XCTAssertEqual(state.secondary, .reserve)
    }
    func testDisablingAnOptionalListKeepsBothSelectionsValid() {
        var state = ListWorkspaceSelection(primary: .reserve)
        state.selectSecondary(.utensils)
        state.reconcile(available: [.pantry, .grocery])
        XCTAssertEqual(state.primary, .pantry)
        XCTAssertEqual(state.secondary, .grocery)
    }
}

final class AssistantPullStateTests: XCTestCase {
    func testOnlyAPullThatStartedAtTheTopCanOpen() {
        var pull = AssistantPullState()
        pull.begin(atTop: false)
        pull.update(distance: 120)
        XCTAssertFalse(pull.finish())
        pull.begin(atTop: true)
        pull.update(distance: 70)
        XCTAssertTrue(pull.finish())
        XCTAssertFalse(pull.finish(), "Release must be consumed once")
    }
    func testRetreatAndCancellationDoNotOpen() {
        var pull = AssistantPullState()
        pull.begin(atTop: true)
        pull.update(distance: 70)
        pull.update(distance: 50)
        XCTAssertTrue(pull.isArmed, "Small finger movements retain the armed state")
        pull.update(distance: 40)
        XCTAssertFalse(pull.finish())
        pull.begin(atTop: true)
        pull.update(distance: 90)
        XCTAssertFalse(pull.finish(cancelled: true))
        XCTAssertEqual(pull.distance, 0)
    }
}
