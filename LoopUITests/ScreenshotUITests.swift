//
//  ScreenshotUITests.swift
//  LoopUITests
//
//  Captures App Store screenshots against the local Supabase stack. Seeds a demo
//  user with realistic people + interactions via REST, signs into the app as that
//  user (which syncs the data down), then screenshots the key screens.
//
//  Run against the 6.9" iPhone and 13" iPad simulators; extract the attachments
//  from the .xcresult afterward. Requires `supabase start`.
//

import XCTest

final class ScreenshotUITests: XCTestCase {
    private let baseURL = "http://127.0.0.1:54321"
    private let anonKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureScreenshots() async throws {
        let email = "demo_\(Int(Date().timeIntervalSince1970))@example.com"
        let password = "password123"

        // 1. Seed a demo user + data directly in the backend.
        try await seedDemoData(email: email, password: password)

        // 2. Sign in as the demo user via the developer email path.
        let app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launch()

        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15))
        emailField.tap(); emailField.typeText(email)
        let passwordField = app.textFields["Password"]
        passwordField.tap(); passwordField.typeText(password)
        app.buttons["Sign In"].tap()

        // 3. Wait for the synced data to arrive. Use plain button queries for the
        // tabs so this works on iPhone (bottom tab bar) and iPad (sidebar tabs).
        let people = app.buttons["People"].firstMatch
        XCTAssertTrue(people.waitForExistence(timeout: 20))
        people.tap()
        XCTAssertTrue(app.staticTexts["Ada Lovelace"].waitForExistence(timeout: 20), "seeded data should sync")

        // People list
        snapshot(app, name: "02-People")

        // Person detail
        app.staticTexts["Ada Lovelace"].firstMatch.tap()
        _ = app.buttons["Log Interaction"].waitForExistence(timeout: 10)
        snapshot(app, name: "03-PersonDetail")

        // Next Actions
        let nextActions = app.buttons["Next Actions"].firstMatch
        if nextActions.waitForExistence(timeout: 5) {
            nextActions.tap()
            _ = app.navigationBars["Next Actions"].waitForExistence(timeout: 10)
            snapshot(app, name: "01-NextActions")
        }

        // Settings (privacy story)
        let settings = app.buttons["Settings"].firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            _ = app.navigationBars["Settings"].waitForExistence(timeout: 10)
            snapshot(app, name: "04-Settings")
        }
    }

    // MARK: Screenshot helper

    @MainActor
    private func snapshot(_ app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Seeding via REST

    private func seedDemoData(email: String, password: String) async throws {
        // Sign up -> access token + user id.
        let signup = try await post(
            path: "/auth/v1/signup",
            body: ["email": email, "password": password],
            token: nil
        )
        let token = signup["access_token"] as? String ?? ""
        let user = signup["user"] as? [String: Any]
        let uid = user?["id"] as? String ?? ""
        XCTAssertFalse(token.isEmpty, "seed signup should return a token")
        XCTAssertFalse(uid.isEmpty)

        func uuid() -> String { UUID().uuidString.lowercased() }
        func iso(_ daysFromNow: Int) -> String {
            let date = Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!
            let f = ISO8601DateFormatter()
            return f.string(from: date)
        }

        let ada = uuid(), grace = uuid(), katherine = uuid(), alan = uuid()
        let persons: [[String: Any]] = [
            ["id": ada, "owner_user_id": uid, "name": "Ada Lovelace", "company": "Analytical Engines", "title": "Founder", "tags": ["VC", "alum"], "source": "manual"],
            ["id": grace, "owner_user_id": uid, "name": "Grace Hopper", "company": "Navy Labs", "title": "Engineering Lead", "tags": ["recruiter"], "source": "manual"],
            ["id": katherine, "owner_user_id": uid, "name": "Katherine Johnson", "company": "Orbital", "title": "Research Scientist", "tags": ["alum"], "source": "businessCard"],
            ["id": alan, "owner_user_id": uid, "name": "Alan Turing", "company": "Bletchley", "title": "Principal Engineer", "tags": ["friend-of-friend"], "source": "contactsImport"],
        ]
        _ = try await postArray(path: "/rest/v1/persons", rows: persons, token: token)

        // PostgREST bulk insert requires every row to have the same keys, so
        // include all optional columns on each row (NSNull where absent).
        func interaction(_ personID: String, date: Int, type: String, notes: String,
                         outcomes: Any, aiSummary: Any, followUp: Any, status: String) -> [String: Any] {
            [
                "id": uuid(), "owner_user_id": uid, "person_id": personID,
                "date": iso(date), "type": type, "notes": notes,
                "outcomes": outcomes, "ai_summary": aiSummary,
                "follow_up_date": followUp, "follow_up_status": status,
            ]
        }
        let interactions: [[String: Any]] = [
            interaction(ada, date: -3, type: "coffeeChat",
                        notes: "Great chat about her new fund and how they evaluate early-stage teams. She offered to intro me to two portfolio founders.",
                        outcomes: "Send deck; ask for intros",
                        aiSummary: "Discussed Ada Lovelace's fund thesis; she offered intros to two founders.",
                        followUp: iso(-1), status: "pending"),
            interaction(grace, date: -5, type: "videoCall",
                        notes: "Talked through the platform role. She wants a follow-up with the hiring manager next week.",
                        outcomes: NSNull(), aiSummary: NSNull(), followUp: iso(2), status: "pending"),
            interaction(katherine, date: -8, type: "event",
                        notes: "Met at the analytics meetup. Shared notes on data tooling.",
                        outcomes: NSNull(), aiSummary: NSNull(), followUp: iso(4), status: "pending"),
            interaction(alan, date: -10, type: "phoneCall",
                        notes: "Caught up on his new role; he's happy to be a reference.",
                        outcomes: NSNull(), aiSummary: NSNull(), followUp: NSNull(), status: "done"),
        ]
        _ = try await postArray(path: "/rest/v1/interactions", rows: interactions, token: token)
    }

    private func post(path: String, body: [String: Any], token: String?) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func postArray(path: String, rows: [[String: Any]], token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: rows)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            XCTAssertTrue((200...299).contains(http.statusCode), "seed insert \(path) HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return data
    }
}
