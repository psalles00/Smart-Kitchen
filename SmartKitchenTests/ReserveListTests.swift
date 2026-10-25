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

#if os(iOS)
import SwiftUI

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

    private func render(_ root: AnyView, name: String) async throws -> UIWindow {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.windowLevel = .normal + 1
        let ready = expectation(description: "Native layout: " + name)
        let controller = UIHostingController(rootView: root.environment(\.scenePhase, .active).onAppear { ready.fulfill() })
        window.rootViewController = controller
        window.makeKeyAndVisible()
        await fulfillment(of: [ready], timeout: 10)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        // Wait for native display commits, including geometry/query-driven updates.
        // No wall-clock sleep and no production bootstrap/test-mode changes.
        let committed = expectation(description: "Display commits: " + name)
        let frames = WorkspaceDisplayCommits { committed.fulfill() }
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
            XCTAssertFalse(bars.isEmpty, "Real native tab navigation must be present")
            XCTAssertFalse(inputs.isEmpty, "The single assistant field must be present")
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
        let window = try await render(AnyView(root), name: "native-workspace-geometry")
        defer { window.isHidden = true; window.rootViewController = nil }
        let primary = try XCTUnwrap(measurements.primary)
        XCTAssertGreaterThan(primary.width, 100)
        XCTAssertGreaterThanOrEqual(primary.minX, -1)
        XCTAssertGreaterThanOrEqual(primary.minY, -1)
        if measurements.expanded {
            let secondary = try XCTUnwrap(measurements.secondary)
            XCTAssertGreaterThan(secondary.width, 100)
            XCTAssertFalse(primary.insetBy(dx: 1, dy: 1).intersects(secondary.insetBy(dx: 1, dy: 1)))
            if primary.maxX <= secondary.minX, let content = measurements.primaryContent {
                XCTAssertEqual(content.minY - 10, secondary.minY, accuracy: 1, "Panel tops must align after the primary content inset")
            }
            for reserved in measurements.reserved where reserved.width > 0 && reserved.height > 0 {
                XCTAssertFalse(primary.intersects(reserved), "Header overlaps reserved region: \(reserved)")
                XCTAssertFalse(secondary.intersects(reserved), "Content overlaps reserved region: \(reserved)")
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "expanded": measurements.expanded,
            "window": String(describing: window.bounds),
            "safeArea": String(describing: window.safeAreaInsets),
            "primaryHeader": String(describing: primary),
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
}

@MainActor
private final class WorkspaceDisplayCommits: NSObject {
    private var link: CADisplayLink?
    private var frames = 0
    private let completion: () -> Void
    init(completion: @escaping () -> Void) { self.completion = completion }
    func start() {
        link = CADisplayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    @objc private func tick() {
        frames += 1
        if frames == 6 { stop(); completion() }
    }
}

@MainActor
private final class WorkspaceRenderMeasurements {
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

private struct WorkspaceGeometryFixture: View {
    let measurements: WorkspaceRenderMeasurements
    @State private var expanded = false
    var body: some View {
        NavigationStack {
            ExpandedPageLayout(pageTheme: .home, companion: {
                AnyView(SavoriaPantryReference().onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                    action: { measurements.secondary = $0 })
            }, header: { inverted in
                PageHeader(title: "Savoria", isInverted: inverted) {
                    HStack { SettingsButton(); GlassGroupButton(systemImage: "plus") {} }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                    action: { measurements.primary = $0 }
            }, content: {
                SavoriaPantryReference().onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                    action: { measurements.primaryContent = $0 }
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
    }
}
#endif
