import XCTest

/// Navigates existing food data without purchases, AI calls, seeding or deletion.
@MainActor
final class PageActionTracingTests: XCTestCase {
    /// Simulator camera is unavailable; exercise the recovery without selecting media.
    func testUnavailableCameraOffersGalleryAndCanCancelWithoutRegistering() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let tab = app.tabBars.buttons["Nutrição"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 45))
        tab.tap()
        let addMenu = app.buttons["savoria.nutrition.add"]
        for useGallery in [false, true] {
            XCTAssertTrue(addMenu.waitForExistence(timeout: 10))
            addMenu.tap()
            app.buttons["Câmera"].firstMatch.tap()
            let alert = app.alerts["Câmera indisponível"]
            XCTAssertTrue(alert.waitForExistence(timeout: 10))
            XCTAssertTrue(alert.buttons["Escolher da galeria"].exists)
            if useGallery {
                alert.buttons["Escolher da galeria"].tap()
                XCTAssertTrue(alert.waitForNonExistence(timeout: 10))
                let cancel = app.buttons["Cancelar"].firstMatch
                XCTAssertTrue(cancel.waitForExistence(timeout: 10))
                let loading = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Carregando")).firstMatch
                XCTAssertTrue(loading.waitForNonExistence(timeout: 30), "The system photo picker must finish loading")
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Gallery after unavailable camera"
                screenshot.lifetime = .keepAlways
                self.add(screenshot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.lifetime = .keepAlways
                self.add(hierarchy)
                let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
                XCTAssertTrue(photo.waitForExistence(timeout: 10))
                photo.tap() // One built-in simulator landscape; never press Analyze.
                XCTAssertTrue(app.staticTexts["Imagem selecionada"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.buttons["Analisar"].firstMatch.isEnabled)
                XCTAssertTrue(app.buttons["Analisar"].firstMatch.isHittable, "The selected-photo preview must expose Analyze without dragging the sheet")
                let preview = XCTAttachment(screenshot: app.screenshot())
                preview.name = "Selected simulator photo preview without inference"
                preview.lifetime = .keepAlways
                self.add(preview)
                app.buttons["Cancelar"].firstMatch.tap()
            } else {
                alert.buttons["Cancelar"].tap()
            }
            XCTAssertTrue(addMenu.waitForExistence(timeout: 10))
            XCTAssertTrue(app.tabBars.firstMatch.exists)
        }
    }

    func testTextCaptureCancellationInEverySupportedLanguage() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        let languages = [
            ("pt-BR", "pt_BR", "Nutrição", "Texto", "Cancelar"),
            ("en", "en_US", "Nutrition", "Text", "Cancel"),
            ("de", "de_DE", "Ernährung", "Text", "Abbrechen"),
            ("es", "es_ES", "Nutrición", "Texto", "Cancelar"),
            ("fr", "fr_FR", "Nutrition", "Texte", "Annuler"),
            ("it", "it_IT", "Nutrizione", "Testo", "Annulla"),
            ("ja", "ja_JP", "栄養", "テキスト", "キャンセル")
        ]
        defer {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
            app.launch()
        }
        for (language, locale, nutrition, text, cancel) in languages {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            let tab = app.tabBars.buttons[nutrition].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 45), language)
            tab.tap()
            let add = app.buttons["savoria.nutrition.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            app.buttons[text].firstMatch.tap()
            let editor = app.textViews["savoria.nutrition.capture.text"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["savoria.nutrition.capture.analyze"].isEnabled)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Text capture \(language)"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)
            app.buttons[cancel].firstMatch.tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        }
    }

    /// Empty-input/dismissal checks never press Analyze and never issue inference.
    func testTextCaptureEmptyCancellationAndReopening() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45))
        tabs.buttons["Nutrição"].firstMatch.tap()
        for cycle in 0..<3 {
            let add = app.buttons["savoria.nutrition.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            app.buttons["Texto"].firstMatch.tap()
            let editor = app.textViews["savoria.nutrition.capture.text"]
            XCTAssertTrue(editor.waitForExistence(timeout: 10))
            let analyze = app.buttons["savoria.nutrition.capture.analyze"]
            XCTAssertFalse(analyze.isEnabled)
            if cycle == 1 {
                editor.tap()
                editor.typeText("   ")
                XCTAssertFalse(analyze.isEnabled, "Whitespace must not start an analysis")
            }
            app.buttons["Cancelar"].firstMatch.tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
            XCTAssertTrue(add.waitForExistence(timeout: 10))
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["savoria.nutrition.add"].waitForExistence(timeout: 10))
    }

    /// Selects existing rows without applying any mutation to personal items.
    func testMultipleSelectionMenuAndCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45))
        // iOS 27 can expose duplicate tab labels with invalid automatic hit points.
        let listsTabFrame = tabs.buttons["Listas"].firstMatch.frame
        if !tabs.buttons["Listas"].firstMatch.isSelected {
            app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: listsTabFrame.midX - app.frame.minX, dy: listsTabFrame.midY - app.frame.minY)
            ).tap()
        }
        XCTAssertTrue(app.buttons["Despensa"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["Despensa"].firstMatch.tap()
        app.buttons["savoria.lists.options"].firstMatch.tap()
        app.buttons["savoria.lists.select"].firstMatch.tap()
        let cancel = app.buttons["savoria.lists.selection.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "savoria.item.select."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(rows.count, 2, "Validation needs existing pantry rows, without creating fixtures.")
        rows.element(boundBy: 0).tap()
        rows.element(boundBy: 1).tap()
        XCTAssertEqual(app.staticTexts["savoria.lists.selection.count"].label, "Selecionados: 2")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "savoria.item.complete.")).firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["savoria.lists.selection.actions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Mover para Mercado"].waitForExistence(timeout: 5))
        app.buttons["Alterar categoria"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Alterar categoria"].waitForExistence(timeout: 5))
        app.buttons["Cancelar"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["savoria.lists.selection.count"].label, "Selecionados: 2")
        let all = app.buttons["savoria.lists.selection.all"]
        all.tap()
        XCTAssertEqual(all.label, "Limpar seleção")
        all.tap()
        XCTAssertEqual(app.staticTexts["savoria.lists.selection.count"].label, "Selecionados: 0")
        XCTAssertFalse(app.buttons["savoria.lists.selection.actions"].isEnabled)
        cancel.tap()
        XCTAssertFalse(cancel.exists)
        app.buttons["savoria.lists.options"].firstMatch.tap()
        app.buttons["savoria.lists.select"].firstMatch.tap()
        rows.element(boundBy: 0).tap()
        app.buttons["Mercado"].firstMatch.tap()
        XCTAssertFalse(cancel.exists, "Changing lists must discard only transient selection.")
        XCUIDevice.shared.press(.home)
    }

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
