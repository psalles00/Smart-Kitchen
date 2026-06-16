import Foundation
import SwiftData
import XCTest
@testable import Savoria

@MainActor
final class UnifiedItemMergeTests: XCTestCase {
    func testMergeDuplicateNamesKeepsOneItemAndPreservesDivergentDetails() throws {
        let container = try ModelContainer(
            for: Schema([UnifiedItem.self]),
            configurations: ModelConfiguration(
                "UnifiedItemMergeTests",
                schema: Schema([UnifiedItem.self]),
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
        let context = ModelContext(container)

        let laterExpiry = Date(timeIntervalSince1970: 2_000)
        let earlierExpiry = Date(timeIntervalSince1970: 1_000)
        let pantry = UnifiedItem(
            name: "Leite",
            descriptionText: "Integral",
            category: "Outros",
            isPantry: true,
            pantrySortOrder: 3,
            expirationDate: laterExpiry
        )
        let grocery = UnifiedItem(
            name: " leite ",
            descriptionText: "Sem lactose",
            category: "Laticínios",
            quantity: 2,
            unit: "L",
            iconName: "milk.png",
            isGrocery: true,
            grocerySortOrder: 1,
            expirationDate: earlierExpiry,
            defaultExpiryDays: 4,
            isChecked: false,
            isFixed: true
        )
        context.insert(pantry)
        context.insert(grocery)
        try context.save()

        let removed = try UnifiedItem.mergeDuplicateNames(in: context)
        try context.save()

        let items = try context.fetch(FetchDescriptor<UnifiedItem>())
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(items.count, 1)

        let merged = try XCTUnwrap(items.first)
        XCTAssertTrue(merged.isPantry)
        XCTAssertTrue(merged.isGrocery)
        XCTAssertTrue(merged.descriptionText.contains("Integral"))
        XCTAssertTrue(merged.descriptionText.contains("Sem lactose"))
        XCTAssertEqual(merged.category, "Laticínios")
        XCTAssertEqual(merged.quantity, 2)
        XCTAssertEqual(merged.unit, "L")
        XCTAssertEqual(merged.iconName, "milk.png")
        XCTAssertEqual(merged.pantrySortOrder, 3)
        XCTAssertEqual(merged.grocerySortOrder, 1)
        XCTAssertEqual(merged.expirationDate, earlierExpiry)
        XCTAssertEqual(merged.defaultExpiryDays, 4)
        XCTAssertTrue(merged.isFixed)
    }
}
