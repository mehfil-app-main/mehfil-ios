# Mehfil · iOS

Operations app for Indian wedding-service vendors — decorators, caterers, photographers, light-and-sound crews. The calendar is the spine, outstanding money is always one tap away, and double-bookings surface before they become a problem.

Built in **SwiftUI for iOS 26 with Liquid Glass**, from the Figma design
[Mehfil](https://www.figma.com/design/HiKVpYsO9qLnUAWF1iZrUY/Untitled?node-id=3-2): 24 screens, 18 components, light and dark, on the Airbnb-derived skin. Accounts and data live in **Firebase** (Sign in with Apple, Google, Cloud Firestore) — the rules and data model are in the sibling repo `mehfil-backend`; the Android app is `mehfil-android`.

<p>
  <img src="docs/screenshots/home.png" width="180" alt="Home">
  <img src="docs/screenshots/events.png" width="180" alt="Events">
  <img src="docs/screenshots/event-detail.png" width="180" alt="Event detail">
  <img src="docs/screenshots/change-request.png" width="180" alt="Change request">
</p>

## Start here

The code is a translation of a documented design process, not a sketch that grew. Before reading a single
screen, read **[`NOTES.md`](https://github.com/Sanu5/mehfil-design/blob/main/NOTES.md)** in the design
repository: six phases of decisions, every derivation from the source design system, the rulings applied in
review, and the full skin migration — with the measurements that forced each change. `tokens.css` there is the
single source of truth that both apps' token files are generated against.

Commercial terms, the transfer checklist and an honest account of the repository's history are in
[`mehfil-backend/HANDOVER.md`](https://github.com/Sanu5/mehfil-backend/blob/main/HANDOVER.md).

## What it does

| Flow | Screens |
|---|---|
| **A · Season view** | Home with the conflict banner, outstanding receivables and the event that needs attention · Calendar month with event dots and conflict dates · Day timeline where overlapping events sit side by side · Season summary against target |
| **B · Events** | Segmented list grouped by month · Event hub with summary tiles, collapsible Payments, Crew, Inventory and Runsheet · Two-step create with an inline conflict check the moment a date is picked · Runsheet with completion toggles and reorder · Change request that shows consequences (chairs, tables, helpers, transport) and the revised quote |
| **C · Money** | Receivables grouped Overdue → Due this week → Upcoming · Per-event payment schedule with collection progress · Record payment on a large numeric keypad (never the alphanumeric keyboard) · Reminders with real composed copy in three tones and the history of what was sent before · Expenses with the margin and a loss state |
| **D · Team & inventory** | Crew by role with availability for a chosen date · Assign crew where booked members stay tappable and open a comparison of both events · Attendance with a single-tap three-state control · Inventory with commitment bars and over-committed items first · Item detail with a 30-day commitment strip |
| **E · Clients & system** | Client list with lifetime value and repeat markers · The client-facing shared event page (cream, gradient mesh, always light, ShareLink) · Enquiry intake that saves, edits, closes and converts to an event · Package templates · Profile with business details, payment details, notifications, appearance · Account with sample data, erase, sign out and account deletion |
| **Sign-in & data** | Welcome with Sign in with Apple, Google, or email and password (verified by email) · One-screen business onboarding with an optional sample season · Every record (events, clients, milestones, crew, attendance, inventory, runsheet, reminders, expenses, enquiries, packages, change requests) is a Firestore document under `vendors/{uid}`, cached offline and streamed live |

Every amount uses Indian digit grouping (`₹23,47,500`), every screen that modifies data writes through the store and shows a save state, and the event draft survives leaving the create flow. Overdue milestones, crew conflicts, payment states and season totals are **derived on the device from stored data**, never stored, so they can't go stale.

## Liquid Glass

- System tab bar through the `Tab` API; it minimises on scroll down and hides on pushed screens.
- Glass toolbar and back buttons; `.buttonStyle(.glass)` header actions on tab roots and a `.glassProminent` "New event" action.
- `.glassEffect()` on the toast, the running-total strip above "Create event", and the title chip that floats in when a root screen scrolls.
- Docked primary actions use `safeAreaBar`, so content scrolls under them with the soft edge effect.
- On the shared event page the glass controls pick up the mesh behind them.

<p>
  <img src="docs/screenshots/shared-page.png" width="180" alt="Shared event page">
  <img src="docs/screenshots/record-payment.png" width="180" alt="Record payment">
  <img src="docs/screenshots/reminder.png" width="180" alt="Send reminder">
  <img src="docs/screenshots/home-dark.png" width="180" alt="Home, dark">
</p>

## Run it

Requires Xcode 26 (iOS 26 SDK). Open `Mehfil.xcodeproj`, pick the **Mehfil** scheme and an iPhone simulator, and run. Swift packages (`firebase-ios-sdk`, `GoogleSignIn-iOS`) resolve on first open. From the terminal:

```bash
xcodebuild -project Mehfil.xcodeproj -scheme Mehfil -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO build
```

**Without a Firebase config** the app runs in *device-only* mode: the welcome screen offers **Continue on this device**, data is stored as JSON in Application Support, and the whole product can be used and reviewed. Nothing else changes.

**With Firebase** — drop `GoogleService-Info.plist` (git-ignored) into `Mehfil/`. The build script registers the Google URL scheme from it, `FirebaseApp.configure()` runs, and the welcome screen shows Sign in with Apple and Google. Setup steps, Firestore rules and the data model are in [`mehfil-backend`](https://github.com/Sanu5/mehfil-backend).

## Configuration

`Model/FeatureConfig.swift` is the one place where capabilities are switched. Every sign-in method and every
product module (inventory, runsheet, expenses, enquiries, packages, change requests, the client page,
reminders, dark mode) has a flag with a documented default, so a narrower first version ships without deleting
code. They are build-time decisions on purpose: there is no in-app switchboard, so a shipped app cannot have
parts of itself turned on and off from the outside, and the whole configuration surface is one readable file.

Sign-in: **Sign in with Apple**, **Google**, and **email + password** with a mandatory verification email,
password reset and change-password. Without a Firebase config the app runs in device-only mode.

## Ship it

- Bundle id `com.anish.mehfil`, iOS 26.0+, version in `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.
- Signing & Capabilities → your team. **Sign in with Apple** is in `Mehfil.entitlements`; Xcode registers it on the App ID.
- `PrivacyInfo.xcprivacy` declares the collected data (email, name, user content — linked, not tracked) and the required-reason APIs; answer App Privacy the same way.
- Account deletion (guideline 5.1.1(v)) is in Profile → Account → Delete account: re-authenticates, revokes the Apple token, deletes every document, then the Firebase user.
- Privacy policy and terms: [`PRIVACY.md`](PRIVACY.md), [`TERMS.md`](TERMS.md) — link them in App Store Connect.
- Archive with **Product → Archive** and upload through Xcode Organizer.

## Layout

```
Mehfil/
  MehfilApp.swift            Firebase configure, session routing (welcome → onboarding → app)
  Navigation/RootView.swift  TabView + per-tab NavigationStack, routes, toast overlay
  Model/
    Models.swift             Codable records (Event, Client, Milestone, CrewMember, …, VendorProfile)
    AuthService.swift        Sign in with Apple (nonce), Google, sign out, delete account, device-only account
    Repository.swift         Repository protocol · LocalRepository (JSON on device) · Backend.isConfigured
    FirestoreRepository.swift  snapshot listeners per collection, batched writes, offline cache
    AppStore.swift           @Observable store: computed views, every mutation, derived conflicts/overdue/season
    SampleSeason.swift       the demo season, date-shifted so it always starts next Saturday
    Format.swift             ₹ grouping, dates, ids
  DesignSystem/              Tokens · Typography · Components · Layouts
  Features/Auth | Home | Events | Money | Team | Profile | Shared (edit sheets)
  Mehfil.entitlements · PrivacyInfo.xcprivacy · Info.plist
  Fonts/                     Inter Light/Regular/Medium (SIL Open Font License)
```

## Design notes worth knowing

- "Today" is live (`Cal.today`). The sample season is shifted by whole weeks so its busy Saturday is always the coming one — the conflict banner, overdue money and "Needs attention" read correctly on any date.
- Nothing derived is stored: overdue is computed from due dates, crew conflicts from bookings, payment state from milestones. Firestore rules (`mehfil-backend/firestore.rules`) allow only the owner to touch `vendors/{uid}`.
- Tokens come straight from the design's `tokens.css`: white ground and surface with structure carried by hairlines and 14pt clipping, ink type at 400–700, Rausch `#ff385c` as the single voltage (filled CTAs, the FAB, the selected tab, save/assign, the hero bar, event 1 — never links or data-viz), one shadow tier reserved for things that float, and a dark set derived by mixing any hue below 4.5:1 toward canvas until it passes.
- Decline on the change request is tertiary, not destructive; destructive confirmations name the exact thing being cancelled.
- The client page (E2) has no dark variant on purpose — it is the client's page, opened from a WhatsApp link.

## Screens

<details>
<summary>All 24 screenshots</summary>
<p>
  <img src="docs/screenshots/home.png" width="160">
  <img src="docs/screenshots/calendar.png" width="160">
  <img src="docs/screenshots/timeline.png" width="160">
  <img src="docs/screenshots/season.png" width="160">
  <img src="docs/screenshots/events.png" width="160">
  <img src="docs/screenshots/event-detail.png" width="160">
  <img src="docs/screenshots/runsheet.png" width="160">
  <img src="docs/screenshots/change-request.png" width="160">
  <img src="docs/screenshots/receivables.png" width="160">
  <img src="docs/screenshots/payment-schedule.png" width="160">
  <img src="docs/screenshots/record-payment.png" width="160">
  <img src="docs/screenshots/reminder.png" width="160">
  <img src="docs/screenshots/team.png" width="160">
  <img src="docs/screenshots/assign-crew.png" width="160">
  <img src="docs/screenshots/crew-comparison.png" width="160">
  <img src="docs/screenshots/attendance.png" width="160">
  <img src="docs/screenshots/inventory.png" width="160">
  <img src="docs/screenshots/item-detail.png" width="160">
  <img src="docs/screenshots/clients.png" width="160">
  <img src="docs/screenshots/shared-page.png" width="160">
  <img src="docs/screenshots/enquiry.png" width="160">
  <img src="docs/screenshots/profile.png" width="160">
  <img src="docs/screenshots/home-dark.png" width="160">
  <img src="docs/screenshots/events-dark.png" width="160">
</p>
</details>

## Licence

Proprietary — all rights reserved. See [`LICENSE`](LICENSE). Publication of this repository has never granted
a licence to use the code; rights transfer only by written agreement.
