# Design Document — Loop

## Overview

Loop is an iPhone/iPad app built with SwiftUI and SwiftData, backed by Supabase for
authentication, multi-device sync, storage, and an AI proxy. The app is local-first:
SwiftData is the on-device source of truth, and a sync layer reconciles changes with
Supabase Postgres. AI features (summaries, action-item extraction, follow-up drafts)
run through a Loop-owned Supabase Edge Function, with PII tokenized on-device before
any text leaves the phone and rehydrated locally on the way back.

This design covers architecture, the data layer, the sync engine, the AI redaction
pipeline, notifications, permissions, security, and the screen-level UI. It maps
directly to the 14 requirements in `requirements.md`.

### Current Scaffold and Migration Notes

The project is the default Xcode SwiftData template: a single `Item` model, a
`ContentView` list, and a `ModelContainer` in `LoopApp`. The entitlements currently
enable CloudKit and push notifications.

- The `Item` model and its `ContentView` usage will be removed and replaced by the
  Loop domain models and feature views.
- We are using Supabase, not CloudKit, for sync. The CloudKit entitlement/container
  entries will be removed to avoid confusion; the push-notification background mode is
  retained only if we later add remote push (local notifications do not require it).
- `ModelContainer` setup in `LoopApp` will be expanded to register the full schema and
  inject app-wide services (auth, sync, AI, notifications).

## Architecture

### High-Level Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     SwiftUI Views (Screens)                   │
│  NextActions · PeopleList · PersonDetail · LogInteraction ·   │
│  AIDraftModal · CardScan · Settings/Privacy · Auth            │
└───────────────────────────────┬───────────────────────────────┘
                                │  observes
┌───────────────────────────────▼───────────────────────────────┐
│                        View Models (@Observable)               │
│   Coordinate use cases, expose state, no persistence logic     │
└───────────────────────────────┬───────────────────────────────┘
                                │  calls
┌───────────────────────────────▼───────────────────────────────┐
│                          Service Layer                         │
│  AuthService · SyncEngine · AIService · NotificationService ·  │
│  CardScanService · ContactsService · PersonRepository ·        │
│  InteractionRepository                                         │
└───────────────┬───────────────────────────────┬───────────────┘
                │                               │
     ┌──────────▼──────────┐        ┌───────────▼───────────┐
     │   SwiftData (local) │        │   Supabase (remote)    │
     │  source of truth /  │◄──────►│  Auth · Postgres+RLS · │
     │  offline cache      │  sync  │  Realtime · Storage ·  │
     └─────────────────────┘        │  Edge Functions (AI)   │
                                    └───────────┬────────────┘
                                                │ redacted text only
                                    ┌───────────▼────────────┐
                                    │  LLM provider          │
                                    │  (zero-retention,      │
                                    │   no-training)         │
                                    └────────────────────────┘
```

### Key Principles

- **Local-first:** Every read and write hits SwiftData first. The UI never blocks on
  the network. Sync happens in the background.
- **Repositories own persistence:** Views and view models never touch `ModelContext`
  directly for domain operations; they go through `PersonRepository` and
  `InteractionRepository`. This keeps derived fields (e.g., `lastContactedDate`) and
  sync bookkeeping consistent.
- **Services are protocol-backed:** Each service has a protocol and a live
  implementation, enabling previews and tests with fakes.
- **PII never reaches the LLM vendor:** Redaction is enforced at the `AIService`
  boundary, not left to callers.

## Data Layer (SwiftData)

### Models

SwiftData `@Model` classes mirror the canonical model in `requirements.md`. Each
syncable model carries sync metadata.

```swift
enum PersonSource: String, Codable { case manual, businessCard, contactsImport }

enum InteractionType: String, Codable {
    case coffeeChat, event, phoneCall, email, videoCall
}

enum FollowUpStatus: String, Codable { case none, pending, done }

@Model final class Person {
    @Attribute(.unique) var id: UUID
    var ownerUserId: String
    var name: String
    var company: String?
    var title: String?
    var email: String?
    var phone: String?
    var tags: [String]
    var sourceRaw: String            // PersonSource
    var lastContactedDate: Date?     // derived, maintained by repository
    var createdAt: Date
    var updatedAt: Date

    // sync metadata
    var isDeleted: Bool              // soft delete (tombstone) for sync
    var syncedAt: Date?              // last time reconciled with server
    var dirty: Bool                  // has local changes pending upload

    @Relationship(deleteRule: .cascade, inverse: \Interaction.person)
    var interactions: [Interaction]
}

@Model final class Interaction {
    @Attribute(.unique) var id: UUID
    var ownerUserId: String
    var person: Person?
    var date: Date
    var typeRaw: String              // InteractionType
    var notes: String
    var outcomes: String?
    var aiSummary: String?
    var followUpDate: Date?
    var followUpStatusRaw: String    // FollowUpStatus
    var createdAt: Date
    var updatedAt: Date

    // sync metadata
    var isDeleted: Bool
    var syncedAt: Date?
    var dirty: Bool
}
```

Enums are stored as raw strings for forward compatibility and are exposed through
computed properties (`var source: PersonSource`). `id` is a client-generated `UUID`
so records can be created offline and reconciled without server round-trips.

### Derived Data

- **`lastContactedDate`** is recomputed by `PersonRepository` whenever an interaction
  is inserted, edited, deleted, or has its date changed. It equals the max
  `Interaction.date` among the person's non-deleted interactions, or `nil`.
- **Overdue vs upcoming** for Next Actions is computed at read time by comparing
  `followUpDate` to the current date; it is not stored.

### Repositories

```swift
protocol PersonRepository {
    func create(_ draft: PersonDraft) throws -> Person
    func update(_ person: Person) throws
    func delete(_ person: Person) throws            // soft delete + cascade tombstones
    func search(query: String, tags: [String]) -> [Person]
    func all() -> [Person]
}

protocol InteractionRepository {
    func create(_ draft: InteractionDraft) throws -> Interaction
    func update(_ interaction: Interaction) throws
    func delete(_ interaction: Interaction) throws
    func nextActions() -> [NextActionItem]          // derived, ordered feed
    func timeline(for person: Person) -> [Interaction]
}
```

All mutations set `updatedAt = now` and `dirty = true`, then signal the `SyncEngine`.

## Sync Engine (Requirement 12)

### Strategy

A background, bidirectional sync between SwiftData and Supabase Postgres, using
last-writer-wins at field granularity where practical, and per-record LWW at minimum.

**Tables** (Postgres) mirror the models with the same `id` (UUID PK), `owner_user_id`,
domain columns, `updated_at`, and `is_deleted`. Row Level Security restricts every row
to `owner_user_id = auth.uid()` (Requirement 12.4).

### Push (local → remote)

1. On any local mutation, the record is marked `dirty = true`.
2. The `SyncEngine` batches dirty records and upserts them to Supabase.
3. Conflict handling: the server compares `updated_at`. The row with the newer
   `updated_at` wins (Requirement 12.5). To avoid losing unrelated fields, upserts send
   the full record; because a single user rarely edits the same record concurrently on
   two devices, field-level merge is a documented enhancement rather than MVP-critical.
4. On success, `dirty = false` and `syncedAt = now`.

### Pull (remote → local)

1. On launch, on foreground, and via Supabase Realtime subscriptions, the engine pulls
   rows changed since the last `syncedAt` watermark.
2. For each incoming row, if the local copy is not `dirty`, apply the remote version.
   If local is `dirty`, apply LWW by `updated_at`.
3. Tombstones (`is_deleted = true`) remove the local record (and cascade for a person's
   interactions).

### Offline (Requirement 12.3)

All operations work against SwiftData with no network. Dirty records accumulate and
flush when connectivity returns (observed via `NWPathMonitor`). The UI shows a subtle
sync status indicator (idle / syncing / offline).

### Conflict Resolution Summary

- Most-recent-`updated_at` wins per record.
- Deletes are tombstones so a delete on one device propagates rather than being
  resurrected by a stale update.

## Authentication (Requirements 1, 2)

### AuthService

Wraps the Supabase Auth SDK.

- **Sign in with Apple:** Native `ASAuthorizationController` flow; the Apple identity
  token is exchanged with Supabase (`signInWithIdToken`).
- **Sign in with Google:** Google Sign-In SDK produces an ID token exchanged with
  Supabase, or Supabase's OAuth web flow via `ASWebAuthenticationSession`.
- **Session:** Supabase persists and refreshes the session in the Keychain. On launch,
  `AuthService` restores the session; a valid session skips the sign-in screen
  (Requirement 1.5).
- **Sign out:** Ends the Supabase session. Local data is cleared unless a session can be
  restored later (Requirement 1.6).

### Account Deletion (Requirement 2)

Because deleting an auth user requires elevated privileges, deletion runs through a
dedicated Supabase Edge Function using the service role:

1. Client calls the `delete-account` function with the user's JWT.
2. The function verifies the caller, deletes the user's `persons` and `interactions`
   rows (cascade), then deletes the auth user.
3. On success, the client clears all local SwiftData for the user and returns to
   sign-in. Partial failures leave the account recoverable and report an error
   (Requirement 2.4).

## AI Pipeline with PII Protection (Requirements 9, 10.4)

### Redaction / Rehydration

Redaction happens entirely on-device, before any network call.

```
notes/text ──► PIIRedactor.redact ──► (redactedText, tokenMap)
                                          │
                    redactedText ─────────┼──► Supabase Edge Function ──► LLM
                                          │            (zero-retention)
result ◄── PIIRedactor.rehydrate ◄── redactedResult ◄──┘
     (tokenMap applied locally)
```

**`PIIRedactor`** detects and tokenizes:
- Person names — from the associated `Person` record (known names) and via Apple's
  `NaturalLanguage` `NLTagger` name-entity recognition for names mentioned in free text.
- Company names — from the `Person.company` and org entities from `NLTagger`.
- Emails and phone numbers — via `NSDataDetector` and regex.

Each detected span is replaced by a stable placeholder for the request
(`[[PERSON_1]]`, `[[ORG_1]]`, `[[EMAIL_1]]`, `[[PHONE_1]]`). The `tokenMap`
(placeholder → original value) never leaves the device. After the model responds,
`rehydrate` swaps placeholders back to the originals so the user sees natural text.

Known limitations are documented: NER is imperfect, so redaction is best-effort for
free-text names. Because processing is routed through Loop's own proxy to a
zero-retention endpoint, residual risk is bounded, and no credentials ship in the app.

### AIService

```swift
protocol AIService {
    func summarize(_ notes: String, context: RedactionContext) async throws -> String
    func extractActionItems(_ notes: String, context: RedactionContext) async throws -> [String]
    func draftFollowUp(for interaction: Interaction, context: RedactionContext) async throws -> String
    func parseCardText(_ text: String) async throws -> PersonDraft   // optional AI parse
}
```

`context` carries the known `Person` fields so the redactor can tokenize reliably.
Summaries are persisted to `Interaction.aiSummary` (Requirement 9.1). Drafts are
returned and never persisted (Requirement 9.3). All methods throw a typed
`AIUnavailable` error when offline or the service fails, which the UI renders as a clear
unavailable state (Requirement 9.8).

### Backend Proxy (Edge Function `ai-proxy`)

- Authenticates the caller via JWT.
- Holds the model provider API key server-side (Requirement 9.6).
- Calls a provider endpoint configured for zero retention and no training
  (Requirement 9.7). Recommended: Amazon Bedrock or Azure OpenAI, both of which offer
  contractual no-train + no-retention; the specific model is a configuration detail
  behind the proxy so it can change without a client release.
- Receives only redacted text.

## Notifications (Requirement 8)

**NotificationService** wraps `UNUserNotificationCenter`.

- Permission is requested the first time a follow-up date is set (Requirement 8.1) and
  not repeatedly re-prompted if denied (Requirement 8.5).
- Scheduling a follow-up creates a `UNCalendarNotificationTrigger` for `followUpDate`,
  with the notification identifier equal to the interaction `id` so it can be updated or
  cancelled when the follow-up changes or is completed (Requirement 8.3).
- Tapping a notification deep-links to the person's detail via the notification's
  `userInfo` carrying `personId` (Requirement 8.4).
- If permission is denied, the follow-up still appears in the Next Actions feed
  (Requirement 8.5).

## Camera / OCR (Requirement 10)

**CardScanService** uses VisionKit `DataScannerViewController` (or `VNRecognizeTextRequest`
with `AVCapture`) for on-device text recognition (Requirement 10.2). Recognized text is
mapped to `PersonDraft` fields heuristically, optionally refined by `AIService.parseCardText`
(which applies the same redaction rules, Requirement 10.4). The user reviews and edits
before saving with `source = businessCard` (Requirements 10.3, 10.5). Denied camera
permission falls back to manual creation (Requirement 10.6).

## Contacts (Requirement 11)

**ContactsService** wraps the `Contacts` framework.

- Import: requests permission, presents a picker, maps `CNContact` fields to
  `PersonDraft` with `source = contactsImport`.
- Export: writes a person's fields to a new or existing `CNContact`.
- Denied permission leaves manual and card-scan creation available.

## Permissions and Privacy (Requirement 13)

Each permission (camera, contacts, notifications) is requested only in the flow that
needs it, with a purpose string in `Info.plist` explaining why (Requirement 13.1). All
non-dependent functionality remains available when a permission is denied
(Requirement 13.2). A Privacy/Settings screen explains local storage vs. synced data vs.
AI PII handling (Requirements 13.3, 13.4).

Required `Info.plist` usage descriptions to add:
- `NSCameraUsageDescription`
- `NSContactsUsageDescription`
- (Notifications use the permission prompt, no plist string required.)

## Security

- **RLS everywhere:** Every Postgres table enforces `owner_user_id = auth.uid()` for
  select/insert/update/delete.
- **No secrets in the client:** LLM and service-role keys live only in Edge Functions.
- **Transport:** All Supabase calls over HTTPS/TLS.
- **Local data:** SwiftData store lives in the app sandbox; iOS Data Protection applies.
- **AI:** Redaction at the service boundary + zero-retention endpoint.

## Screens and Navigation (Requirement 14)

Root uses a `TabView` (works well on iPhone) that adapts to `NavigationSplitView`
layout on iPad regular width.

1. **Auth** — shown when no valid session. Apple + Google buttons.
2. **Home / Next Actions** — default authenticated entry (Requirement 14.1). Sectioned
   list: Overdue, then Upcoming (soonest first). Tap → Person Detail. Complete action
   inline.
3. **People List** — all people, search bar, tag filter chips (Requirement 14.2).
   Add button → manual create or scan card. Import from contacts entry point.
4. **Person Detail** — fields, tags, `lastContactedDate`, interaction timeline, and the
   person's `aiSummary` entries (Requirement 14.3). Actions: log interaction, edit,
   export to contacts, delete.
5. **Log Interaction** — date, type, notes, outcomes, follow-up date; AI actions
   (summarize, extract action items) (Requirement 14.4).
6. **AI Draft Modal** — presents an on-demand draft with copy/dismiss; not persisted
   (Requirement 14.5).
7. **Card Scan** — camera capture → review pre-filled draft.
8. **Settings / Privacy** — privacy explanations, notification status, sign out, delete
   account.

### State Management

Each screen has an `@Observable` view model that depends on service protocols injected
from the environment. Views use `@Query` only for simple local list reads where
convenient; anything involving derived ordering or filtering (Next Actions, search) goes
through repositories so logic is testable.

## Error Handling

- Typed errors per service (`AuthError`, `SyncError`, `AIUnavailable`, `PermissionDenied`).
- User-facing, non-technical messages; destructive/blocking failures surface inline.
- Sync failures are silent and retried; a persistent failure shows the offline/sync
  indicator rather than interrupting the user.

## Testing Strategy

- **Unit tests:** `PIIRedactor` (tokenize/rehydrate round-trip, entity detection),
  repositories (derived `lastContactedDate`, soft-delete cascade), Next Actions ordering
  (overdue/upcoming), follow-up status transitions, sync conflict resolution (LWW,
  tombstones).
- **Service fakes:** In-memory `ModelContainer` and fake Supabase/AI clients for fast,
  deterministic tests.
- **UI tests:** Core flows — sign in (mocked), add person, log interaction, complete a
  follow-up, request an AI draft (mocked AI).
- Tests are added alongside features per the task plan; AI and network are faked so
  suites run offline and deterministically.

## Technology Choices Summary

| Concern            | Choice                                             |
|--------------------|----------------------------------------------------|
| UI                 | SwiftUI (iPhone + iPad, iOS/iPadOS 17+)            |
| Local storage      | SwiftData (source of truth / offline cache)        |
| Backend / sync     | Supabase (Postgres + RLS, Realtime)                |
| Auth               | Supabase Auth — Sign in with Apple, Google         |
| AI proxy           | Supabase Edge Function → zero-retention LLM         |
| PII protection     | On-device redaction (NaturalLanguage, NSDataDetector) |
| Notifications      | UserNotifications (local)                           |
| OCR                | VisionKit / Vision (on-device)                      |
| Contacts           | Contacts framework                                  |
