//
//  WalkthroughUITests.swift
//  LoopUITests
//
//  End-to-end walkthrough of the core flows against the local Supabase stack:
//  sign up, add a person, log an interaction with a follow-up, see it in Next
//  Actions, and run an AI summary. Requires `supabase start` and
//  `supabase functions serve ai-proxy` to be running.
//

import XCTest

final class WalkthroughUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCoreWalkthrough() throws {
        let app = XCUIApplication()

        // Dismiss system alerts (notifications permission, save-password) if they
        // interrupt the flow.
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Not Now", "Allow", "Allow While Using App", "Don't Allow", "OK", "Continue"] {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }

        app.launchEnvironment["UITESTS"] = "1"
        app.launch()

        // MARK: Sign up (developer email path)
        let email = "uitest_\(Int(Date().timeIntervalSince1970))@example.com"
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15), "Auth screen should show an email field")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.textFields["Password"]
        XCTAssertTrue(passwordField.waitForExistence(timeout: 5), "password field")
        passwordField.tap()
        passwordField.typeText("password123")

        app.buttons["Sign Up"].tap()

        // MARK: Reach the main tabs
        let peopleTab = app.tabBars.buttons["People"]
        XCTAssertTrue(peopleTab.waitForExistence(timeout: 20), "Should reach main tabs after sign up")
        peopleTab.tap()

        // MARK: Add a person via the empty-state button (opens the manual form
        // directly, avoiding the flaky toolbar menu).
        let addPerson = app.buttons["addPersonEmptyState"]
        XCTAssertTrue(addPerson.waitForExistence(timeout: 10), "empty-state Add Person button")
        addPerson.tap()

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Ada Lovelace")
        app.buttons["Save"].tap()

        // Person appears in the list.
        let personCell = app.staticTexts["Ada Lovelace"]
        XCTAssertTrue(personCell.waitForExistence(timeout: 10), "New person should appear in the list")
        personCell.tap()

        // MARK: Log an interaction with a follow-up
        let logButton = app.buttons["Log Interaction"]
        XCTAssertTrue(logButton.waitForExistence(timeout: 10))
        logButton.tap()

        let notesEditor = app.textViews.firstMatch
        XCTAssertTrue(notesEditor.waitForExistence(timeout: 10))

        // Enable the follow-up first, before the keyboard is up (defaults to +7
        // days -> upcoming). Verify it actually switched on.
        let followUpToggle = app.switches["Set a follow-up"]
        XCTAssertTrue(followUpToggle.waitForExistence(timeout: 5), "follow-up toggle")
        if (followUpToggle.value as? String) != "1" {
            // Tap the trailing edge where the actual switch control sits; a
            // center tap on a Form row toggle doesn't reliably flip it.
            followUpToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        XCTAssertEqual(followUpToggle.value as? String, "1", "follow-up should be enabled")

        // Now enter notes.
        notesEditor.tap()
        notesEditor.typeText("Discussed working with Ada Lovelace at Analytical Engines on a new role.")

        // Dismiss the keyboard and reveal the AI section below the fold.
        app.swipeUp()

        // MARK: AI summarize (hits the local ai-proxy function)
        let summarize = app.buttons["Summarize Notes"]
        XCTAssertTrue(summarize.waitForExistence(timeout: 10))
        summarize.tap()
        XCTAssertTrue(
            app.staticTexts["Summary"].waitForExistence(timeout: 25),
            "AI summary label should appear after summarizing"
        )

        app.buttons["Save"].tap()

        // MARK: Verify it shows up in Next Actions
        let nextActionsTab = app.tabBars.buttons["Next Actions"]
        XCTAssertTrue(nextActionsTab.waitForExistence(timeout: 10))
        nextActionsTab.tap()

        XCTAssertTrue(
            app.staticTexts["Ada Lovelace"].waitForExistence(timeout: 10),
            "The person with a pending follow-up should appear in Next Actions"
        )
    }
}
