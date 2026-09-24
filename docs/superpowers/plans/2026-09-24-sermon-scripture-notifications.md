# Sermon Scripture Notifications — Plan

**Status:** draft, awaiting owner answers to the open questions below. No code yet.
**Branch:** `claude/sermon-scripture-notifications-07g812`
**Linear:** none yet. One issue = one branch = one PR, so file one before implementation starts.

## Goal

After a sermon is recorded and summarized, the user gets a short run of local notifications over the next week. Each one shows a scripture the sermon used (reference plus verse text) and a short line tied to the sermon's message. Tapping one opens that sermon.

## What exists today (read before planning)

| Piece | Where | Relevance |
|---|---|---|
| Scripture detection | `Services/ScriptureAnalysisService.swift` + `ScriptureAnalysisServiceProtocol.swift` (`ScriptureReference`) | Regex extraction from any text. Already used by `RecordingView`, `ClickableScriptureText`, `BibleFAB`. Returns references sorted by book, not by importance. |
| Summary content | `Models/Summary.swift` (`text`, `title`), prompt in `tablet-notes-api/netlify/functions/summarize.js` | The summary prompt already produces a **Main Scripture Text** section and a **Scripture References** section that excludes opening-prayer verses. This is a better source than the raw transcript. |
| Verse text | `Services/Bible/BibleAPIService.swift` `fetchVerse(reference:bibleId:)` | Proxied through `/api/bible`, needs a Bearer token and network. Notification bodies are static, so verse text must be fetched when scheduling, not at delivery. |
| Summary completion | `SummaryRetryService` (three places set `summaryStatus = "complete"`) and the durable pipeline, whose results arrive through `SermonSyncLocalRepository` | Several completion paths. Hooking each one is fragile and touches high-risk code. |
| Notifications | `Services/Notification/NotificationService.swift` is an in-app banner only. No `UNUserNotificationCenter` use anywhere. | This is net-new: permission, scheduling, delegate, and tap handling. |
| Notification prefs | `UserNotificationSettings` `@Model` in `Models/User.swift`, mirrored by `SupabaseUserNotificationSettings` | Adding a field here is a migration event and touches the Supabase settings contract. Avoid in v1 (see Decisions). |

## Proposed design

### 1. Local notifications only. No backend change in v1.

`UNCalendarNotificationTrigger`, scheduled on device. No APNs, no server cron, no new endpoint, no migration, no deploy debt. The content already exists on device once the summary is complete.

### 2. A reconciler, not a completion hook

A new `ScriptureReminderScheduler` (`@MainActor`, `@Observable`, behind a `ScriptureReminderScheduling` protocol with a mock) exposes one idempotent method, `reconcile()`. It:

1. Returns early if the feature is off or notification permission is not granted.
2. Finds sermons that are eligible: `summaryStatus == "complete"`, not archived, recorded in the last 48 hours, and not already scheduled (a set of sermon ids in `UserDefaults`).
3. Builds that sermon's reminder plan (step 3), fetches verse text, and schedules the requests.
4. Records the sermon id as scheduled **only after** `UNUserNotificationCenter.add` succeeds for every request. If any fail, it removes what it added and leaves the sermon unscheduled so the next pass retries. This follows the manual's rule against optimistic acks.

It runs from the app root's existing lifecycle hooks (`handleAppLaunch`, `handleAppDidBecomeActive`, and after `SermonProcessingCoordinator` finishes a summary), per D-20260914-0000: constructed once in `TabletNotesApp.init`, injected, never built in a view init.

Why a reconciler: it covers every completion path (legacy, durable, arriving via sync) without editing `SummaryRetryService`, the sync engine, or `SermonService`. The 48-hour recording window stops a cloud restore or reinstall from firing reminders for months-old sermons.

### 3. Building the plan for one sermon (pure, unit-tested)

`ScriptureReminderPlanner` is a pure function: (sermon title, summary text, transcript text, recording date, preferences) in, `[PlannedReminder]` out. No I/O, so it gets thorough tests.

- **Scripture selection:** parse the summary's "Main Scripture Text" section first, then its "Scripture References" section, then the rest of the summary, then the transcript. Pass each through `ScriptureAnalysisService`, dedupe, and keep first-seen order so the main text leads. Cap at the number of reminders in the week.
- **Schedule:** default is the day after recording, then every other day, for up to 4 reminders over 7 days, at 8:00 local time. Fewer scriptures means fewer reminders. No scriptures means no reminders; a generic "revisit your notes" message is not in scope.
- **Message line:** v1 takes it from the summary locally: the summary title first, then key points or application bullets, one per reminder, trimmed to fit. No new AI call. The alternative is in the open questions.
- **Content:** title is `"<Reference> · <Sermon title>"`, body is the verse text (truncated around 180 characters) followed by the message line. If verse text can't be fetched (offline, API error), the body is the reference plus the message line, and the reminder still goes out.

### 4. Identifiers, replacement, cancellation

- Request id: `scripture-reminder.<sermonId>.<index>`, with `userInfo["sermonId"]`.
- iOS allows 64 pending local notifications. When a newer sermon is scheduled, cancel any pending reminders from an older sermon that overlap its week. At most one sermon's run is active at a time, which also avoids two notifications on the same morning.
- Cancel a sermon's pending reminders when it is deleted or archived. The cancel is a single call from the delete path. `SermonService.deleteSermon` is high-risk, so this is either one line there or an observer on the root. Decide at implementation time; the one line is simpler.
- Cancel all pending reminders when the user turns the feature off or signs out.

### 5. Permission and settings

- Ask for permission in context, not at launch: a one-time prompt card in `SermonDetailView` once the first summary completes ("Get this week's scriptures as reminders?"), plus a toggle in Settings → Notifications.
- Preference lives in `UserDefaults` (`scriptureRemindersEnabled`, and a reminder time if we expose one), not on the `UserNotificationSettings` model.
- If permission was denied, the Settings row explains that and links to the system Settings app instead of showing a dead toggle.

### 6. Tap handling

A `UNUserNotificationCenterDelegate` set at the app root:
- `willPresent`: show the banner even when the app is in the foreground.
- `didReceive`: read `sermonId` and route to that sermon's detail view through the existing navigation state in `MainAppView`, which is a routing change only. Opening the specific scripture sheet is a stretch goal.

## Blast radius

- **New files:** `Services/Notification/ScriptureReminderScheduler.swift` (+ protocol), `ScriptureReminderPlanner.swift`, `TabletNotesTests/ScriptureReminderPlannerTests.swift`, `ScriptureReminderSchedulerTests.swift`, and a mock in `TabletNotesTests/Mocks/`. `fileSystemSynchronizedGroups` picks them up; the `.pbxproj` is not touched.
- **Edited:** `App/TabletNotesApp.swift` (construct and inject, set the delegate; the reset/restore flow is not touched), `SermonProcessingCoordinator` (call `reconcile()` after completion), `SettingsView` (toggle), `SermonDetailView` (opt-in card), `MainAppView` (route on tap; routing only, no construction in init), and the delete/archive cancel.
- **Not touched:** `@Model` classes, the sync engine, `RecordingService`, the backend, the Supabase schema, StoreKit/tier logic (unless the owner makes this premium, see below).
- **Model routing (CLAUDE.md):** planner and settings UI are routine work; wiring into `TabletNotesApp`, `MainAppView`, the coordinator and the delete path is high-risk work.

## Implementation order (checkpointed; the most informative step first)

1. **Planner and tests.** Scripture extraction from real summary text (use prod-shaped fixtures, sanitized), ordering, schedule dates across DST and month boundaries, and the no-scripture case. This is also where we learn whether real summaries give clean references.
2. **Scheduler with an injectable notification-center protocol.** Tests: idempotency (reconcile twice schedules once), the partial-failure rollback, the 48-hour window, replacing an older sermon, and cancel on delete.
3. **Permission, Settings toggle, and the opt-in card.**
4. **App-root wiring and tap routing.** Build, then verify on the simulator: record or seed a sermon, force a trigger a few seconds out with a debug-only override, and tap it.
5. **PR** with the `[TAB-NN]` title and manual test steps. Stating "no `@Model` change, no backend change" explicitly in the PR body is the migration and deploy note.

## Verification plan

- `xcodebuild build` on the 18.5 simulator named in the manual.
- `xcodebuild test -only-testing:TabletNotesTests/ScriptureReminderPlannerTests` and `...SchedulerTests`, plus any existing suite whose file is edited (such as the `SermonService*` suites if the delete path changes).
- Manual on the simulator: pending requests inspected with `getPendingNotificationRequests`, a delivered banner, and tap routing. A signed-in account is needed for verse fetch (manual §12).

## Open questions for the owner

1. **Cadence and time.** Default is 4 reminders over 7 days at 8:00 AM, starting the next morning. Should users be able to choose the time or how many reminders they get?
2. **The quick message.** v1 derives it locally from the summary at no cost. Alternatively, a new AI-generated devotional line per scripture: better copy, but it means a backend endpoint (auth, Joi, rate limit), per-sermon AI cost, and deploy steps. Recommendation: ship v1 local, revisit.
3. **Free or Premium?** Local-only v1 costs nothing to serve, so it can be free. If it should be Premium, it touches entitlement logic, which is a hard stop needing explicit sign-off.
4. **On by default after opt-in, or opt-in per sermon?** Recommendation: one global opt-in, with every new sermon scheduled automatically.
5. **Translation.** Use the user's selected Bible translation (the same setting `ScriptureDetailView` uses). Assumed yes.

## Decisions to record when accepted (medium impact)

- Reminders are local notifications scheduled on device, with no server component in v1.
- Scheduling is an idempotent reconciler over eligible sermons, not a hook in each summary completion path.
- The feature preference lives in `UserDefaults`, not on the `UserNotificationSettings` model, to avoid a migration and a Supabase contract change.
