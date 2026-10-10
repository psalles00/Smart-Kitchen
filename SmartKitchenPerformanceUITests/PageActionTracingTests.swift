import XCTest

/// Navigates existing food data without purchases, AI calls, seeding or deletion.
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
        XCUIDevice.shared.press(.home)
    }

    func testSettingsAndForeground() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-SavoriaActionTrace", "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45))
        tabs.buttons["Savoria"].firstMatch.tap()
        app.buttons["savoria.settings"].tap()
        XCTAssertTrue(app.buttons["savoria.settings.close"].waitForExistence(timeout: 10))
        // Read-only destinations; never toggle sync or perform backup/restore.
        for destination in ["icloud", "family", "notifications", "backup", "appearance", "lists", "nutrition", "data"] {
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
    /// Changes only a reversible visibility preference; never creates or moves food records.
    func testReserveVisibilityAndCreationDestination() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45))
        func openListSettings() {
            tabs.buttons["Savoria"].firstMatch.tap()
            app.buttons["savoria.settings"].tap()
            app.buttons["savoria.settings.lists"].tap()
        }
        openListSettings()
        let toggle = app.switches["savoria.lists.reserve.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        let originallyEnabled = toggle.value as? String == "1"
        let info = app.buttons["savoria.lists.reserve.info"]
        XCTAssertTrue(info.exists)
        info.tap()
        let explanation = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Guarde itens que acabaram")).firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String == "1", originallyEnabled, "Opening information must not change the preference.")
        let infoAttachment = XCTAttachment(screenshot: app.screenshot())
        infoAttachment.lifetime = .keepAlways
        add(infoAttachment)
        // The popover excludes underlying navigation elements from hit testing.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        XCTAssertFalse(explanation.exists)
        if !originallyEnabled {
            // iOS 27 reports the whole row as the switch frame. Tap the actual control.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
        }
        app.navigationBars.buttons["Configurações"].firstMatch.tap()
        app.buttons["savoria.settings.close"].tap()
        tabs.buttons["Listas"].firstMatch.tap()
        let reserve = app.buttons["Para depois"].firstMatch
        XCTAssertTrue(reserve.waitForExistence(timeout: 10))
        reserve.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(reserve.waitForExistence(timeout: 10))
        app.buttons["savoria.lists.add"].tap()
        let destination = app.buttons["savoria.item.destination.reserve"]
        XCTAssertTrue(destination.waitForExistence(timeout: 10))
        XCTAssertTrue(destination.isSelected, "New item must inherit its explicit list destination.")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        // Dismiss the unsaved sheet by dragging its handle, without modifying records.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        if !originallyEnabled {
            openListSettings()
            app.switches["savoria.lists.reserve.enabled"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            app.navigationBars.buttons["Configurações"].firstMatch.tap()
            app.buttons["savoria.settings.close"].tap()
            tabs.buttons["Listas"].firstMatch.tap()
            XCTAssertFalse(app.buttons["Para depois"].exists)
        }
        XCUIDevice.shared.press(.home)
    }

}
