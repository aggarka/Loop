# Implementation Plan — Loop

This plan sequences the build in incremental, testable steps. Each task references the
requirements it satisfies. Tasks are ordered so that core local functionality is usable
early, with sync and AI layered on afterward. Only code-level work is listed; account
provisioning of the Supabase project itself is a prerequisite noted in task 0.

- [x] 0. Project setup and scaffold cleanup
  - Remove the template `Item` model and its usage in `ContentView`.
  - Remove CloudKit entries from `Loop.entitlements` (keep the app sandbox correct);
    keep local-notification support (no remote-push entitlement required for MVP).
  - Add `Info.plist` usage strings: `NSCameraUsageDescription`, `NSContactsUsageDescription`.
  - Add a checked-in-safe `SupabaseConfig` that loads URL + anon key from an optional
    `Supabase-Info.plist`.
  - _Requirements: 1, 13.1_
  - _Note: adding the Supabase + Google Sign-In SPM packages and provisioning the
    Supabase project remain external (Xcode/network) prerequisites, deferred to the
    auth/sync tasks (6, 7)._

- [x] 1. Domain models and repositories (local-first core)
  - [x] 1.1 Define SwiftData models `Person` and `Interaction` with enums and sync
        metadata fields (`isTombstoned`, `syncedAt`, `dirty`).
    - Register the schema in `LoopApp`'s `ModelContainer`.
    - _Note: the tombstone flag is named `isTombstoned`, not `isDeleted`, to avoid a
      silent collision with Core Data's `NSManagedObject.isDeleted`._
    - _Requirements: 3, 6_
  - [x] 1.2 Implement `PersonRepository` (create/update/soft-delete/search/all) with
        derived `lastContactedDate` maintenance.
    - Write unit tests for creation, name-required validation, soft-delete cascade, and
      `lastContactedDate` derivation.
    - _Requirements: 3.1, 3.3, 3.4, 3.5, 3.6, 6.6_
  - [x] 1.3 Implement `InteractionRepository` (create/update/delete, timeline,
        nextActions) with follow-up status handling.
    - Write unit tests for timeline ordering and `lastContactedDate` recomputation on
      interaction changes.
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

- [x] 2. People management UI
  - [x] 2.1 Build People List screen with add/edit/delete and empty states.
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 14.2_
  - [x] 2.2 Build Person Detail screen (fields, tags, `lastContactedDate`, interaction
        timeline).
    - _Requirements: 3.5, 6.4, 14.3_
  - [x] 2.3 Implement tagging UI with presets (VC, recruiter, alum, friend-of-friend)
        plus custom tags.
    - _Requirements: 4.1, 4.2, 4.3_
  - [x] 2.4 Implement search and tag filtering (combined query + filters, clear state).
    - Search matching / multi-tag AND filtering is covered by the existing
      `PersonRepositoryTests` (search + tag filter), which now exercise the shared
      `PersonFilter` used by the UI.
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5_

- [x] 3. Interaction logging UI
  - Build Log Interaction screen (date, type, notes, outcomes, follow-up date) and wire
    it to `InteractionRepository`. Reachable from Person Detail (log new + edit existing
    via timeline row tap).
  - _Requirements: 6.1, 6.2, 6.3, 14.4_

- [x] 4. Next Actions feed
  - [x] 4.1 Implement the derived Next Actions feed (overdue vs upcoming, ordering).
    - Logic lives in the shared `NextActionsBuilder` (used by repository + view);
      classification/ordering and completion removal are covered by
      `InteractionRepositoryTests`.
    - _Requirements: 7.1, 7.2, 7.3, 7.4_
  - [x] 4.2 Build Home / Next Actions screen as the authenticated entry point, with
        complete-follow-up action (swipe) and navigation to Person Detail.
    - _Requirements: 7.5, 7.6, 14.1_

- [x] 5. Local notification reminders
  - Implement `NotificationService`: permission request on first follow-up (only when
    undetermined, never re-prompting a denied user), schedule/reschedule/cancel by
    interaction id, deep-link on tap (via `NotificationRouter` + delegate), and
    feed-only fallback when denied. Wired into log/edit, complete, and delete flows.
  - Unit tests cover the pure `FollowUpNotificationPlanner` decisions and the service's
    schedule/cancel/authorization behavior via a fake scheduler (8 tests).
  - _Note: the runtime permission prompt and the physical notification tap can only be
    fully verified on a device/simulator interactively; the scheduling and routing
    logic is unit-tested._
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 6. Authentication and accounts
  - [x] 6.1 Implement `AuthService` over Supabase Auth; build the Auth screen (`AuthView`)
        with Sign in with Apple (native) and Google (OAuth), plus a DEBUG email path for
        local testing; restore session on launch via `authStateChanges`.
    - _Note: Apple/Google require provider config on a hosted project; verified the email
      path end-to-end against local Supabase (signup → session)._
    - _Requirements: 1.1, 1.2, 1.3, 1.5_
  - [x] 6.2 Scope all local data to the authenticated `ownerUserId` (driven by
        `AuthService` → `AppSession`); sign-out clears local data.
    - _Requirements: 1.4, 1.6_
  - [x] 6.3 Implement account deletion via the `delete_current_user` security-definer RPC
        (cascade delete through FKs), with confirmation, local wipe, and recoverable
        failure handling. Verified via REST: RPC returns 204 and rows cascade-delete.
    - _Note: implemented as a Postgres SECURITY DEFINER function rather than an Edge
      Function — simpler, no service-role key in a function, works locally and hosted._
    - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [~] 7. Backend schema and sync engine
  - [x] 7.1 Create Postgres tables for `persons` and `interactions` with RLS policies
        (`owner_user_id = auth.uid()`) and `updated_at` / `is_tombstoned` columns.
    - Applied to the local Supabase stack via migration
      `supabase/migrations/20260722193745_create_people_and_interactions.sql`; verified
      RLS enabled with 4 policies per table and that unauthenticated REST calls are
      rejected (401).
    - _Requirements: 12.4_
  - [x] 7.2 Implement `SyncEngine` push (upload dirty records, persons before
        interactions for FK order) and pull (delta by `updated_at` watermark), with
        last-writer-wins conflict resolution and tombstone propagation. Triggered on
        sign-in, on foreground, and after each local mutation. Table GRANTs added so the
        authenticated role can access rows (RLS then narrows to owner) — verified the
        full authenticated insert/select path via REST.
    - _Note: Realtime push subscriptions and dedicated LWW/tombstone unit tests remain
      to add; runtime multi-device sync verification is folded into task 13. The REST
      contract (auth + RLS + upsert/select) is validated._
    - _Requirements: 12.1, 12.2, 12.5_
  - [x] 7.3 Add connectivity monitoring (`NWPathMonitor`) with offline status and an
        auto-sync when connectivity returns; `SyncEngine.status` exposes idle/syncing/
        offline/error for a status indicator.
    - _Requirements: 12.3_

- [x] 8. AI pipeline with PII protection
  - [x] 8.1 Implement `PIIRedactor` (tokenize names/orgs/emails/phones via
        NaturalLanguage + NSDataDetector; rehydrate from token map).
    - Unit tests cover redact/rehydrate round-trips, repeated-value token reuse,
      prefix-safe rehydration, and detection without context (5 tests).
    - _Requirements: 9.4, 9.5_
  - [x] 8.2 Implement the `ai-proxy` Supabase Edge Function: receives already-redacted
        text, calls a configurable provider endpoint when `AI_PROVIDER_API_KEY` is set
        (documented as zero-retention/no-training), and returns a deterministic local
        response otherwise. `verify_jwt = true` in `config.toml`. Verified end-to-end via
        `supabase functions serve` — returns a summary with placeholders preserved.
    - _Requirements: 9.6, 9.7_
  - [x] 8.3 Implement `AIService` (summarize, extract action items, draft follow-up) over
        an `AIBackend` protocol (`SupabaseAIBackend`); redaction/rehydration enforced at
        the service boundary; summaries persisted, drafts transient; typed `AIError`
        when unavailable. 5 unit tests verify redaction-out, rehydration-in, and error
        paths via a fake backend.
    - _Requirements: 9.1, 9.2, 9.3, 9.8_
  - [x] 8.4 Wired AI actions (Summarize, Extract Action Items, Draft Follow-up) into Log
        Interaction; the `AIDraftModal` presents a transient draft (copy/dismiss, not
        persisted).
    - _Requirements: 9.1, 9.2, 9.3, 14.5_

- [x] 9. Business card scanning
  - `BusinessCardScanView` uses VisionKit `DataScannerViewController` for on-device OCR;
    `BusinessCardParser` maps recognized lines to a `PersonDraft`, reviewed/edited in
    `PersonEditView(prefill:)` before saving with `source = businessCard`; manual
    fallback when scanning is unavailable (covers camera-denied). Parser is unit-tested.
    - _Note: the optional AI-parse of scanned text (`AIService.parseCardText`) is
      deferred to task 8.3, since it depends on the AI backend._
  - _Requirements: 10.1, 10.2, 10.3, 10.5, 10.6 (10.4 with task 8.3)_

- [x] 10. Contacts import/export
  - `ContactsImportView` uses the out-of-process `CNContactPickerViewController`
    (no permission prompt for import) → creates `PersonDraft` (`source = contactsImport`);
    `ContactsService.export` writes a `CNContact` (requests write access, graceful denial
    message). `ContactMapper` is pure and unit-tested.
  - _Requirements: 11.1, 11.2, 11.3, 11.4_

- [x] 11. Privacy and settings screen
  - `SettingsView` explains local-first storage, private cross-device sync, and on-device
    AI PII redaction; provides Sign Out and Delete Account (with confirmation). Camera,
    contacts, and notification prompts are each requested only within the flow that needs
    them, with purpose strings in `Info.plist`.
  - _Requirements: 13.1, 13.2, 13.3, 13.4_

- [~] 12. Navigation shell and iPad layout
  - Root `TabView` (Next Actions, People, Settings) gated on auth state; deep-links from
    notifications switch tabs and navigate. `TARGETED_DEVICE_FAMILY = 1,2` (iPhone + iPad)
    and the app builds for both.
  - _Note: interactive iPad adaptive-layout verification is folded into task 13._
  - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_

- [~] 13. End-to-end verification
  - [x] App builds for iPhone + iPad (iOS 26.5) and the full unit suite passes: 36 tests
        across repositories, PII redactor, Next Actions, notifications, business-card
        parser, contact mapper, and AIService (redaction boundary).
  - [x] Backend contract verified against local Supabase via REST: signup → authenticated
        insert (201) → RLS-scoped select → account-deletion RPC (204) → FK cascade;
        `ai-proxy` edge function returns results with PII placeholders preserved.
  - [x] Automated end-to-end walkthrough (`LoopUITests/WalkthroughUITests`) drives the
        integrated app against the live local stack: sign up → main tabs → add person →
        log interaction with a follow-up → AI summarize (real edge-function call with PII
        redaction/rehydration) → save (synced to Postgres) → follow-up appears in Next
        Actions. Passing.
    - To run: `supabase start` + `supabase functions serve ai-proxy`, then the UI test.
  - [ ] Two-device concurrent sync and physical local-notification delivery still warrant
        a manual check (the UI-test runner skips the notification prompt via a `UITESTS`
        env flag).
  - _Requirements: all_
