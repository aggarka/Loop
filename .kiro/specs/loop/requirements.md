# Requirements Document — Loop

## Introduction

Loop is a mobile-first personal networking app for iPhone and iPad that helps
early-career professionals (ages 22–35) log conversations, remember context, and
know exactly who to follow up with next. It acts as a relationship memory and a
lightweight AI coach. The core promise: never forget a networking conversation or
miss a follow-up again.

This document defines the requirements for the combined MVP (original MVP + V1
scope). Features described in the original "V2" list (dormant-tie detection,
proactive weekly outreach agent, tone-matched drafting, calendar/LinkedIn
integrations) are explicitly out of scope for this release.

### Product Decisions (agreed)

- **Platforms:** iPhone and iPad (iOS/iPadOS 17+ for SwiftData).
- **Local-first storage:** SwiftData is the on-device source of truth and cache.
- **Backend & multi-device sync:** Supabase (Postgres + Row Level Security,
  Realtime, Auth, Storage, Edge Functions).
- **Authentication:** Sign in with Apple and Google for this release. Microsoft/Live
  is a deferred fast-follow. Users can delete their account.
- **AI:** Summaries, action-item extraction, and follow-up drafting. AI runs through
  a Loop-owned backend proxy (Supabase Edge Function). PII is tokenized on-device
  before any text leaves the device and rehydrated locally in the response, so the
  third-party LLM vendor never receives identifiable data. The model endpoint must
  be configured for zero data retention and no training on inputs.
- **AI drafts:** Generated on demand and not persisted.
- **Reminders:** Both iOS local notifications and an in-app Next Actions feed.
- **Offline:** All core CRUD works offline against SwiftData. AI features require
  network and degrade gracefully.

### Assumptions

1. Managed Supabase storing user PII for sync is acceptable. The "no PII to third
   parties" rule applies specifically to the AI/LLM vendor, not the sync backend.
   (Revisit here if self-hosting is later required.)
2. Business card OCR uses on-device text recognition (VisionKit). Any AI-based field
   parsing of the recognized text follows the same redaction rules as other AI calls.
3. A single user account maps to a single person's private relationship data; there
   is no sharing between users in this release.

### Canonical Data Model

**User** (profile; identity managed by auth provider)
- `id`, `displayName`, `email`, `authProvider`, `createdAt`

**Person**
- `id`, `ownerUserId`, `name`, `company`, `title`, `email`, `phone`
- `tags: [String]` (presets: VC, recruiter, alum, friend-of-friend; plus custom)
- `source: { manual, businessCard, contactsImport }`
- `lastContactedDate` (derived from latest interaction), `createdAt`, `updatedAt`

**Interaction**
- `id`, `personId`, `ownerUserId`, `date`
- `type: { coffeeChat, event, phoneCall, email, videoCall }`
- `notes` (free text), `outcomes` (commitments)
- `aiSummary` (nullable), `followUpDate` (nullable)
- `followUpStatus: { none, pending, done }` (overdue is derived from `followUpDate`)
- `createdAt`, `updatedAt`

Next Actions is a derived view over interactions that have a `followUpDate` and a
`followUpStatus` of `pending`; it is not a separately stored entity.

---

## Requirements

### Requirement 1: Account Creation and Authentication

**User Story:** As a new user, I want to sign in with Apple or Google, so that my
networking data is tied to my account and available across my devices.

#### Acceptance Criteria

1. WHEN a user opens the app without an active session THEN the system SHALL present
   sign-in options for Apple and Google.
2. WHEN a user completes Sign in with Apple THEN the system SHALL create or restore
   their account and establish an authenticated session.
3. WHEN a user completes Sign in with Google THEN the system SHALL create or restore
   their account and establish an authenticated session.
4. IF a user signs in on a new device with an existing account THEN the system SHALL
   associate that device with the existing account and sync their data.
5. WHEN a user's authenticated session is valid THEN the system SHALL not require
   re-authentication on subsequent launches until the session expires or the user
   signs out.
6. WHEN a user chooses to sign out THEN the system SHALL end the session and return
   to the sign-in screen while retaining locally cached data only if a session can
   later be restored, otherwise clearing local data.

### Requirement 2: Account Deletion

**User Story:** As a user, I want to delete my account, so that I can permanently
remove my data from the service.

#### Acceptance Criteria

1. WHEN a user requests account deletion THEN the system SHALL require an explicit
   confirmation that describes the consequences before proceeding.
2. WHEN account deletion is confirmed THEN the system SHALL delete the user's auth
   identity and cascade-delete all of the user's People and Interaction records from
   the backend.
3. WHEN account deletion completes THEN the system SHALL clear all local on-device
   data for that user and return to the sign-in screen.
4. IF account deletion fails partway THEN the system SHALL report the failure and
   leave the account in a recoverable state rather than a partially deleted state.

### Requirement 3: People Management (CRUD)

**User Story:** As a user, I want to add, view, edit, and remove people, so that I
can maintain a record of everyone in my network.

#### Acceptance Criteria

1. WHEN a user creates a person with at least a name THEN the system SHALL persist a
   Person record with `source = manual` and make it available in the People list.
2. WHEN a user provides company, title, email, phone, or tags THEN the system SHALL
   store those fields on the Person.
3. WHEN a user edits a person THEN the system SHALL persist the changes and update
   `updatedAt`.
4. WHEN a user deletes a person THEN the system SHALL remove the Person and all of
   that person's Interaction records after an explicit confirmation.
5. WHEN a Person is displayed THEN the system SHALL show `lastContactedDate` derived
   from that person's most recent interaction, or an empty state if none exists.
6. IF a user attempts to create a person without a name THEN the system SHALL block
   creation and indicate that a name is required.

### Requirement 4: Tagging

**User Story:** As a user, I want to tag people, so that I can group and find them by
relationship type.

#### Acceptance Criteria

1. WHEN a user adds tags to a person THEN the system SHALL offer the presets VC,
   recruiter, alum, and friend-of-friend, and SHALL allow custom tag values.
2. WHEN a user assigns multiple tags to a person THEN the system SHALL store all of
   them.
3. WHEN a user removes a tag from a person THEN the system SHALL update the person's
   tag set without affecting other people.

### Requirement 5: Search and Filter

**User Story:** As a user, I want to search and filter my people, so that I can
quickly find the right contact.

#### Acceptance Criteria

1. WHEN a user enters a search query THEN the system SHALL match against name,
   company, and title and return matching people.
2. WHEN a user applies one or more tag filters THEN the system SHALL show only people
   who have all selected tags.
3. WHEN search and filters are combined THEN the system SHALL apply both and show
   only people that satisfy the query and the selected filters.
4. WHEN no people match THEN the system SHALL show an empty state.
5. WHEN search and filters are cleared THEN the system SHALL restore the full People
   list.

### Requirement 6: Interaction Logging

**User Story:** As a user, I want to log a conversation with a person, so that I can
remember what was discussed and what I committed to.

#### Acceptance Criteria

1. WHEN a user logs an interaction for a person THEN the system SHALL persist an
   Interaction with `personId`, `date`, and `type`.
2. WHEN a user records notes and outcomes THEN the system SHALL store them on the
   Interaction.
3. WHEN a user sets a follow-up date THEN the system SHALL store `followUpDate` and
   set `followUpStatus = pending`.
4. WHEN a user views a person THEN the system SHALL show that person's interactions in
   reverse chronological order as a timeline.
5. WHEN a user edits or deletes an interaction THEN the system SHALL persist the
   change and re-derive the person's `lastContactedDate`.
6. WHEN an interaction is created or its date changes THEN the system SHALL update the
   related person's derived `lastContactedDate` accordingly.

### Requirement 7: Follow-ups and Next Actions Feed

**User Story:** As a user, I want a single feed of overdue and upcoming follow-ups, so
that I know exactly who to reach out to next.

#### Acceptance Criteria

1. WHEN interactions have a `followUpDate` and `followUpStatus = pending` THEN the
   system SHALL include them in the Next Actions feed.
2. WHEN a follow-up's date is earlier than the current date THEN the system SHALL
   present it as overdue.
3. WHEN a follow-up's date is the current date or later THEN the system SHALL present
   it as upcoming.
4. WHEN the Next Actions feed is displayed THEN the system SHALL order items with
   overdue first, then upcoming by soonest date.
5. WHEN a user marks a follow-up as done THEN the system SHALL set
   `followUpStatus = done` and remove it from the Next Actions feed.
6. WHEN a user taps a follow-up item THEN the system SHALL navigate to the related
   person's detail view.

### Requirement 8: Local Notification Reminders

**User Story:** As a user, I want reminders on my device for follow-ups, so that I am
prompted even when the app is closed.

#### Acceptance Criteria

1. WHEN a user first sets a follow-up date THEN the system SHALL request notification
   permission if it has not already been granted or denied.
2. IF notification permission is granted AND a follow-up date is set THEN the system
   SHALL schedule a local notification for that follow-up.
3. WHEN a follow-up date or status changes THEN the system SHALL reschedule or cancel
   the associated local notification to stay consistent.
4. WHEN a user taps a follow-up notification THEN the system SHALL open the app to the
   related person's detail view.
5. IF notification permission is denied THEN the system SHALL still surface the
   follow-up in the in-app Next Actions feed and SHALL not repeatedly prompt for
   permission.

### Requirement 9: AI Assistance with PII Protection

**User Story:** As a user, I want the app to summarize my notes, extract action items,
and draft follow-up messages, so that I save time and capture next steps, without
exposing my contacts' personal information to a third-party AI vendor.

#### Acceptance Criteria

1. WHEN a user requests AI summarization of an interaction's notes THEN the system
   SHALL return a concise summary and store it as `aiSummary` on that interaction.
2. WHEN a user requests action-item extraction THEN the system SHALL return suggested
   next steps derived from the notes.
3. WHEN a user requests a follow-up draft THEN the system SHALL generate draft message
   text on demand and SHALL NOT persist the draft.
4. WHEN any text is sent for AI processing THEN the system SHALL tokenize personally
   identifiable information (names, company names, emails, phone numbers) on-device
   before the text leaves the device.
5. WHEN an AI response is received THEN the system SHALL rehydrate the tokens back into
   the original PII values locally before displaying the result.
6. WHEN the app calls the AI service THEN the system SHALL route the request through
   the Loop-owned backend proxy so that AI provider credentials are never present in
   the client.
7. WHEN the AI backend calls the model provider THEN the system SHALL use an endpoint
   configured for zero data retention and no training on inputs.
8. IF the device is offline OR the AI service is unavailable THEN the system SHALL
   present a clear unavailable state and SHALL allow all non-AI functionality to
   continue.

### Requirement 10: Business Card Scanning

**User Story:** As a user, I want to scan a business card with my camera, so that I can
create a person record without typing everything manually.

#### Acceptance Criteria

1. WHEN a user initiates a card scan THEN the system SHALL request camera permission if
   not already granted.
2. WHEN a card is captured THEN the system SHALL perform on-device text recognition to
   extract text.
3. WHEN text is recognized THEN the system SHALL pre-populate a new Person's name,
   company, title, email, and phone fields where they can be determined, with
   `source = businessCard`.
4. WHEN AI is used to parse recognized fields THEN the system SHALL apply the same PII
   tokenization rules defined in Requirement 9.
5. WHEN the pre-populated person is shown THEN the system SHALL allow the user to review
   and edit all fields before saving.
6. IF camera permission is denied THEN the system SHALL inform the user and fall back to
   manual person creation.

### Requirement 11: Contacts Import and Export

**User Story:** As a user, I want to import people from my device contacts and export
people back to contacts, so that I can reuse information I already have.

#### Acceptance Criteria

1. WHEN a user initiates contacts import THEN the system SHALL request contacts
   permission if not already granted.
2. WHEN contacts permission is granted THEN the system SHALL let the user select
   contacts to import and SHALL create Person records with `source = contactsImport`,
   mapping name, company, title, email, and phone where available.
3. WHEN a user exports a person to contacts THEN the system SHALL create or update a
   device contact with that person's available fields.
4. IF contacts permission is denied THEN the system SHALL inform the user and SHALL
   continue to support manual and business-card person creation.

### Requirement 12: Multi-Device Sync

**User Story:** As a user, I want my data to sync across my iPhone and iPad, so that my
network is consistent everywhere I use the app.

#### Acceptance Criteria

1. WHEN a user is authenticated on multiple devices THEN the system SHALL sync their
   People and Interaction records across those devices.
2. WHEN a change is made on one device AND connectivity is available THEN the system
   SHALL propagate that change to the user's other devices.
3. WHEN a device is offline THEN the system SHALL allow the user to continue reading and
   writing locally and SHALL sync those changes when connectivity is restored.
4. WHEN the backend enforces access THEN the system SHALL ensure a user can only read
   and write their own records via row-level security.
5. IF conflicting edits to the same record occur on different devices THEN the system
   SHALL resolve them deterministically (most recent update wins) and SHALL not lose
   unrelated fields.

### Requirement 13: Privacy and Permissions

**User Story:** As a privacy-conscious user, I want clear control over data and
permissions, so that I trust the app with sensitive relationship information.

#### Acceptance Criteria

1. WHEN the app requires camera, contacts, or notification access THEN the system SHALL
   request each permission only in the context where it is needed and SHALL explain why.
2. WHEN a user has not opted into a permission THEN the system SHALL continue to provide
   all functionality that does not depend on that permission.
3. WHEN AI features are used THEN the system SHALL make clear that notes are processed by
   AI and SHALL protect PII as defined in Requirement 9.
4. WHEN a user reviews privacy settings THEN the system SHALL describe what data is
   stored locally, what is synced to the backend, and how AI processing handles PII.

### Requirement 14: Core Screens and Navigation

**User Story:** As a user, I want a clear set of screens to move between my next
actions, my people, and logging, so that the app is fast to use.

#### Acceptance Criteria

1. WHEN the app launches with an authenticated session THEN the system SHALL show the
   Home / Next Actions screen as the entry point.
2. WHEN a user navigates to the People List THEN the system SHALL display all of the
   user's people with search and filter controls.
3. WHEN a user selects a person THEN the system SHALL show a Person Detail screen with
   the person's fields and interaction timeline.
4. WHEN a user chooses to log an interaction THEN the system SHALL present a Log
   Interaction screen for the relevant person.
5. WHEN a user requests an AI draft THEN the system SHALL present the draft in a modal
   that can be copied or dismissed.
