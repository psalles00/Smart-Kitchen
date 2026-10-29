import XCTest
import StoreKit
import StoreKitTest

@MainActor
final class DecimalReproTests: XCTestCase {
    func testFractionalPricesFromAppleLocalStoreKit() async throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Configuration", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        defer { withExtendedLifetime(session) {} }
        session.disableDialogs = true
        session.storefront = "BRA"
        session.locale = Locale(identifier: "pt_BR")
        let expected = ["com.example.storekitdecimal.annual": Decimal(string: "99.90")!,
                        "com.example.storekitdecimal.monthly": Decimal(string: "49.90")!]
        let products = try await Product.products(for: Array(expected.keys))
        XCTAssertEqual(products.count, expected.count)
        for product in products {
            print("APPLE_ONLY_PRICE id=\(product.id) numeric=\(product.price) display=\(product.displayPrice) json=\(String(decoding: product.jsonRepresentation, as: UTF8.self))")
            XCTAssertEqual(product.price, expected[product.id])
            XCTAssertEqual(product.priceFormatStyle.currencyCode, "BRL")
        }
    }
}
