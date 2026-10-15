import XCTest

/// Navigates existing food data without purchases, AI calls, seeding or deletion.
@MainActor
final class PageActionTracingTests: XCTestCase {
    func testHitchesHomeScrollAndForeground() throws { try measurePageHitches("Savoria") }
    func testHitchesListsScrollAndForeground() throws { try measurePageHitches("Listas") }
    func testHitchesRecipesScrollAndForeground() throws { try measurePageHitches("Receitas") }
    func testHitchesNutritionScrollAndForeground() throws { try measurePageHitches("Nutrição") }
    func testHitchesSearchAndForeground() throws { try measurePageHitches("Buscar") }

    /// Actual OS hitch measurements, not automation elapsed time or callback gaps.
    /// Existing data only: no seeding, AI requests, checkbox changes or purchases.
    private func measurePageHitches(_ name: String) throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("OS hitch metrics require iOS 26 or later.") }
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-SavoriaActionTrace", "-SavoriaKeepAwakeForValidation",
                               "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        try openMeasurementApp(app)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        let lowPowerBefore = ProcessInfo.processInfo.isLowPowerModeEnabled
        // Clock samples also prove the measurement block produced a report.
        // They include automation waits and must never be interpreted as FPS.
        var metrics: [any XCTMetric] = [XCTClockMetric(), XCTHitchMetric(application: app)]
        if name != "Buscar" { metrics.append(XCTOSSignpostMetric.scrollingAndDecelerationMetric) }
        measure(metrics: metrics, options: options) {
            tabs.buttons[name == "Savoria" ? "Listas" : "Savoria"].firstMatch.tap()
            tabs.buttons[name].firstMatch.tap()
            if name == "Listas", app.buttons["Despensa"].firstMatch.isHittable {
                app.buttons["Despensa"].firstMatch.tap()
            }
            if name != "Buscar" {
                // SwiftUI List can be exposed as UICollectionView on new iOS.
                // Never let a missing scrolling surface silently pass this test.
                let surfaces = (app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex)
                    // UICollectionView may itself report non-hittable while
                    // its cells scroll normally. Use the visible viewport.
                    .filter { $0.frame.intersection(app.frame).height > 200 && $0.frame.intersection(app.frame).width > 200 }
                let scroll = surfaces.max { $0.frame.height * $0.frame.width < $1.frame.height * $1.frame.width }
                XCTAssertNotNil(scroll, "The actual vertical page content must be exercised")
                scroll?.swipeUp()
                scroll?.swipeDown()
                // A downward pull can deliberately open Search. Return to the
                // target so foreground measures and checks the intended page.
                if !tabs.buttons[name].firstMatch.isSelected { tabs.buttons[name].firstMatch.tap() }
            }
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(tabs.buttons[name].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(tabs.buttons[name].firstMatch.isSelected)
        }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Measured page hierarchy: \(name)"
        tree.lifetime = .keepAlways
        add(tree)
        attachDeviceConditions(thermalBefore: thermalBefore, lowPowerBefore: lowPowerBefore)
        // Keep the validation app foreground while Xcode exports results.
        // Going Home here re-enables system Auto-Lock before the CLI can reopen
        // the app, even though the app's validation flag disables its idle timer.
        app.activate()
    }

    /// Feed Instruments with real gestures without a competing XCTest trace.
    /// This deliberately creates no XCTHitchMetric or OS signpost metric session.
    func testProfileListsForInstruments() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-SavoriaActionTrace", "-SavoriaKeepAwakeForValidation",
                               "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        try openMeasurementApp(app)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45))
        tabs.buttons["Listas"].firstMatch.tap()
        if app.buttons["Despensa"].firstMatch.isHittable { app.buttons["Despensa"].firstMatch.tap() }
        let surfaces = (app.scrollViews.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex)
            .filter { $0.frame.intersection(app.frame).height > 200 && $0.frame.intersection(app.frame).width > 200 }
        let scroll = try XCTUnwrap(surfaces.max { $0.frame.height * $0.frame.width < $1.frame.height * $1.frame.width })
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        let lowPowerBefore = ProcessInfo.processInfo.isLowPowerModeEnabled
        for _ in 0..<6 {
            scroll.swipeUp()
            scroll.swipeDown()
            if !tabs.buttons["Listas"].firstMatch.isSelected { tabs.buttons["Listas"].firstMatch.tap() }
        }
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(tabs.buttons["Listas"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(tabs.buttons["Listas"].firstMatch.isSelected)
        attachDeviceConditions(thermalBefore: thermalBefore, lowPowerBefore: lowPowerBefore)
    }

    /// Profiles warm foreground transitions on every tab, without trace metrics.
    func testProfileForegroundForInstruments() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-SavoriaActionTrace", "-SavoriaKeepAwakeForValidation",
                               "-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        try openMeasurementApp(app)
        let tabs = app.tabBars.firstMatch
        XCTAssertTrue(tabs.waitForExistence(timeout: 45))
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        let lowPowerBefore = ProcessInfo.processInfo.isLowPowerModeEnabled
        for _ in 0..<2 {
            for page in ["Savoria", "Listas", "Nutrição", "Receitas", "Buscar"] {
                tabs.buttons[page].firstMatch.tap()
                XCUIDevice.shared.press(.home)
                app.activate()
                // Sleep only the separate test-driver process. Leave the app
                // free of AX queries for two seconds after each activation.
                Thread.sleep(forTimeInterval: 2)
                XCTAssertTrue(tabs.buttons[page].firstMatch.isSelected)
            }
        }
        attachDeviceConditions(thermalBefore: thermalBefore, lowPowerBefore: lowPowerBefore)
    }

    private func openMeasurementApp(_ app: XCUIApplication) throws {
        if ProcessInfo.processInfo.environment["SAVORIA_USE_INSTALLED_TARGET"] == "1" {
            // The CLI opens the signed, installed app before starting XCTest.
            // launch() triggers an erroneous installation in Xcode 27 beta's
            // UseDestinationArtifacts mode. Never silently launch without flags.
            XCTAssertTrue(app.state == .runningForeground || app.state == .runningBackground,
                          "Open the installed validation app before this test")
            app.activate()
        } else {
            app.launch()
        }
    }

    private func attachDeviceConditions(thermalBefore: Int, lowPowerBefore: Bool) {
        // UITest runner executes on the target iPhone, so these describe that
        // device, not the Mac. Read outside the measurement block.
        let context = XCTAttachment(string: "thermalBefore=\(thermalBefore) thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue) lowPowerBefore=\(lowPowerBefore) lowPowerAfter=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
        context.name = "Device thermal and power conditions (not frame metrics)"
        context.lifetime = .keepAlways
        add(context)
    }

    /// Hardware-only preview; never captures, analyzes, or registers a photo.
    func testPhysicalCameraPreviewAndCancellationWithoutSaving() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Real camera validation requires a physical iPhone.")
        #else
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launch()
        let nutrition = app.tabBars.buttons["Nutrição"].firstMatch
        XCTAssertTrue(nutrition.waitForExistence(timeout: 45))
        nutrition.tap()
        let add = app.buttons["savoria.nutrition.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        app.buttons["Câmera"].firstMatch.tap()
        let cancel = app.buttons["DismissButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15))
        XCTAssertFalse(app.alerts["Câmera indisponível"].exists)
        XCTAssertTrue(app.buttons["PhotoCapture"].isHittable, "The real camera shutter must be exposed, but never pressed")
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "Physical camera preview, no photo captured"
        screen.lifetime = .keepAlways
        self.add(screen)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Physical camera controls"
        tree.lifetime = .keepAlways
        self.add(tree)
        cancel.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["savoria.nutrition.capture.analyze"].exists)
        XCUIDevice.shared.press(.home)
        #endif
    }

    /// Uses the existing four-step validation recipe without editing it.
    func testExistingRecipeCookingStepsAndForegroundPreserveData() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let recipes = app.tabBars.buttons["Receitas"].firstMatch
        XCTAssertTrue(recipes.waitForExistence(timeout: 45))
        recipes.tap()
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Wrap de frango com homus")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let start = app.buttons["Começar a cozinhar"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Existing wrap recipe detail"
        detail.lifetime = .keepAlways
        self.add(detail)
        start.tap()
        XCTAssertTrue(app.staticTexts["1/4"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Anterior"].isEnabled)
        app.buttons["Próximo"].tap()
        XCTAssertTrue(app.staticTexts["2/4"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["2/4"].waitForExistence(timeout: 10))
        app.buttons["Anterior"].tap()
        XCTAssertTrue(app.staticTexts["1/4"].waitForExistence(timeout: 5))
        for step in 2...4 {
            app.buttons["Próximo"].tap()
            XCTAssertTrue(app.staticTexts["\(step)/4"].waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.buttons["Próximo"].exists)
        let lastStep = XCTAttachment(screenshot: app.screenshot())
        lastStep.name = "Final cooking step after foreground and back navigation"
        lastStep.lifetime = .keepAlways
        self.add(lastStep)
        app.buttons["Finalizar"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
    }

    func testOnboardingAndPaywallPreviewsAcrossSupportedLanguages() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        defer {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
            app.launch()
        }
        for (language, locale) in [("pt-BR", "pt_BR"), ("en", "en_US"), ("de", "de_DE"),
                                   ("es", "es_ES"), ("fr", "fr_FR"), ("it", "it_IT"), ("ja", "ja_JP")] {
            app.terminate()
            app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
            app.launch()
            let home = app.tabBars.buttons["Savoria"].firstMatch
            XCTAssertTrue(home.waitForExistence(timeout: 45), language)
            home.tap()
            app.buttons["savoria.settings"].tap()
            let debug = app.buttons["settings-debug-center"]
            XCTAssertTrue(debug.waitForExistence(timeout: 10), language)
            debug.tap()
            for preview in ["debug-open-onboarding", "debug-open-paywall"] {
                let open = app.buttons[preview]
                XCTAssertTrue(open.waitForExistence(timeout: 10), language)
                if !open.isHittable { app.swipeUp() }
                open.tap()
                let close = app.buttons["debug-close-onboarding-preview"]
                XCTAssertTrue(close.waitForExistence(timeout: 15), language)
                if preview == "debug-open-paywall" {
                    let disclaimer = app.staticTexts["savoria.paywall.disclaimer"]
                    let restore = app.buttons["savoria.paywall.restore"]
                    XCTAssertTrue(disclaimer.exists, language)
                    XCTAssertTrue(restore.isHittable, language)
                    XCTAssertGreaterThanOrEqual(disclaimer.frame.minX, app.frame.minX, language)
                    XCTAssertLessThanOrEqual(disclaimer.frame.maxX, app.frame.maxX, language)
                    XCTAssertLessThanOrEqual(disclaimer.frame.maxY, restore.frame.minY, language)
                }
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "\(preview) \(language), preview only"
                screenshot.lifetime = .keepAlways
                self.add(screenshot)
                close.tap()
                XCTAssertTrue(close.waitForNonExistence(timeout: 10), language)
            }
        }
    }

    /// Exact local-only input is guarded by a real-parser, zero-network unit test.
    /// Adds one synthetic food to the isolated validation Simulator; never deletes it.
    func testExactLemonSugarRegistrationOnceAndReopen() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let tab = app.tabBars.buttons["Nutrição"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 45))
        tab.tap()
        let add = app.buttons["savoria.nutrition.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        app.buttons["Texto"].firstMatch.tap()
        let editor = app.textViews["savoria.nutrition.capture.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("suco de limao com 6cs de acucar")
        let analyze = app.buttons["savoria.nutrition.capture.analyze"]
        XCTAssertTrue(analyze.isEnabled)
        analyze.tap()
        let register = app.buttons["Registrar"].firstMatch
        XCTAssertTrue(register.waitForExistence(timeout: 15))
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "suco de limao com 6cs de acucar")).firstMatch.exists)
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "393")).firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Exact lemon sugar analysis, local references and review warning"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        register.tap(withNumberOfTaps: 2, numberOfTouches: 1)
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(tab.waitForExistence(timeout: 45))
        tab.tap()
        XCTAssertTrue(app.staticTexts["suco de limao com 6cs de acucar"].firstMatch.waitForExistence(timeout: 15))
        let reopened = XCTAttachment(screenshot: app.screenshot())
        reopened.name = "Lemon sugar food retained after relaunch"
        reopened.lifetime = .keepAlways
        self.add(reopened)
        XCUIDevice.shared.press(.home)
    }

    /// Closed-network unit tests guarantee the saved-library source survives these follow-ups.
    func testSavedLibraryFollowUpKeepsSourceAndUpdatesTimeAfterForeground() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let home = app.tabBars.buttons["Savoria"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 45))
        home.tap()
        let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "SavorIA")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.tap()
        let input = app.textFields["savoria.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("Me mostre apenas receitas salvas da minha biblioteca, sem restringir à despensa.")
        app.buttons["savoria.chat.send"].tap()
        XCTAssertTrue(app.staticTexts["Suas Receitas"].firstMatch.waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("Agora em até 5 minutos.")
        app.buttons["savoria.chat.send"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "Suas Receitas").element(boundBy: 1).waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Receitas da Web"].exists)
        XCTAssertFalse(app.staticTexts["Ideias Rápidas"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved library follow-up after foreground, five-minute limit"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        input.tap()
        input.typeText("Mais opções.")
        app.buttons["savoria.chat.send"].tap()
        XCTAssertTrue(app.staticTexts["Nenhum resultado encontrado"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Receitas da Web"].exists)
        XCTAssertFalse(app.staticTexts["Ideias Rápidas"].exists)
        XCUIDevice.shared.press(.home)
    }

    /// This request shape is covered by closed-network source-routing tests.
    func testSavedLibraryRequestUsesExistingCardsWithoutGenerating() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.pedrosalles.smartkitchen.sync")
        app.launchArguments = ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        let home = app.tabBars.buttons["Savoria"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 45))
        home.tap()
        let chat = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "SavorIA")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        chat.tap()
        let input = app.textFields["savoria.chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("Me mostre apenas receitas salvas da minha biblioteca, sem restringir à despensa.")
        app.buttons["savoria.chat.send"].tap()
        XCTAssertTrue(app.staticTexts["Suas Receitas"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Receitas da Web"].exists)
        XCTAssertFalse(app.staticTexts["Ideias Rápidas"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved library only, no web or generation"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Mingau Simples")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.tabBars.buttons["Receitas"].firstMatch.isSelected)
        XCTAssertTrue(app.staticTexts["Mingau Simples"].firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
    }

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
