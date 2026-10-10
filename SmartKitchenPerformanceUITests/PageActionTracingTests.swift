import XCTest

/// Navigates existing data only. Never buys, calls AI, seeds, deletes or edits records.
@MainActor
final class PageActionTracingTests: XCTestCase {
    func testPagesAndForeground() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-SavoriaActionTrace", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45), "App must reach its populated root without resetting data.")
        for cycle in 0..<3 {
            for name in ["Savoria", "Listas", "Receitas", "Nutrição", "Buscar"] {
                XCTContext.runActivity(named: "\(cycle): \(name), scroll and foreground") { activity in
                    let tab = tabs.buttons[name].firstMatch
                    XCTAssertTrue(tab.exists)
                    tab.tap()
                    XCTAssertTrue(tab.isSelected)
                    let scroll = app.scrollViews.firstMatch
                    if scroll.exists { scroll.swipeUp(); scroll.swipeDown() }
                    let table = app.tables.firstMatch
                    if !scroll.exists && table.exists { table.swipeUp(); table.swipeDown() }
                    if name == "Listas" {
                        for subtab in ["Mercado", "Despensa", "Utensílios"] where app.buttons[subtab].exists {
                            app.buttons[subtab].tap()
                        }
                    }
                    if name == "Nutrição" && app.buttons["Expandir calendário"].exists {
                        app.buttons["Expandir calendário"].tap()
                        app.buttons["Voltar para hoje"].tap()
                        app.buttons["Recolher calendário"].tap()
                    }
                    if app.keyboards.firstMatch.exists { app.swipeUp() }
                    // The app's pull-to-search gesture can intentionally change
                    // tabs during scrolling. Preserve the actual page before Home.
                    let selectedName = tabs.buttons.allElementsBoundByIndex.first(where: \.isSelected)?.label
                    XCTAssertNotNil(selectedName)
                    XCUIDevice.shared.press(.home)
                    app.activate()
                    if let selectedName {
                        let selected = tabs.buttons[selectedName].firstMatch
                        XCTAssertTrue(selected.waitForExistence(timeout: 10))
                        XCTAssertTrue(selected.isSelected, "Foreground must preserve page selection.")
                    }
                    if cycle == 0 {
                        let attachment = XCTAttachment(screenshot: app.screenshot())
                        attachment.lifetime = .keepAlways
                        activity.add(attachment)
                    }
                }
            }
        }
        tabs.buttons["Receitas"].firstMatch.tap()
        let recipe = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "savoria.recipe.")).firstMatch
        if recipe.exists {
            recipe.tap()
            XCUIDevice.shared.press(.home)
            app.activate()
            let back = app.navigationBars.buttons.matching(identifier: "BackButton")
                .allElementsBoundByIndex.first(where: \.isHittable)
            XCTAssertNotNil(back)
            back?.tap()
        }
        tabs.buttons["Savoria"].firstMatch.tap()
        app.buttons["savoria.settings"].tap()
        XCTAssertTrue(app.buttons["savoria.settings.close"].waitForExistence(timeout: 10))
        // Read-only destinations; never toggle sync or perform backup/restore.
        for destination in ["icloud", "family", "notifications", "backup", "appearance", "lists", "nutrition"] {
            let link = app.buttons["savoria.settings.\(destination)"].firstMatch
            if !link.exists { app.swipeUp() }
            XCTAssertTrue(link.waitForExistence(timeout: 5), "Settings destination must be exercised: \(destination)")
            link.tap()
            XCUIDevice.shared.press(.home)
            app.activate()
            let back = app.navigationBars.buttons["Configurações"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.tap()
            XCTAssertTrue(app.buttons["savoria.settings.close"].waitForExistence(timeout: 5))
        }
        app.buttons["savoria.settings.close"].tap()
        XCUIDevice.shared.press(.home) // flush bounded trace after the final interaction
    }
}
