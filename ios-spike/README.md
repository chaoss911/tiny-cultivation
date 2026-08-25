# Tiny Cultivation iOS Retreat Spike

Disposable validation code. **Do not merge this directory into V1.**

## Question

Can this chain survive normal iOS lifecycle behavior on a physical device?

`入定 -> kill app -> wait -> local notification -> tap -> same deterministic result -> 入定 again`

Home Screen widgets and Live Activities are optional observations. The core chain must work for a user who never adds a widget.

## Time box

Stop after 3–5 working days. Do not add history, art, naming, progression, analytics SDKs, account systems, cloud storage, or polished layout.

## Xcode setup

1. Create a new native iOS SwiftUI app target named `TinyCultivationSpike`.
2. Set deployment target to iOS 16.2 or newer for the ActivityKit path.
3. Add these app-target files:
   - `TinyCultivationSpikeApp.swift`
   - `ContentView.swift`
   - `SpikeState.swift`
   - `RetreatStore.swift`
   - `NotificationManager.swift`
   - `RetreatActivityAttributes.swift`
   - `LiveActivityManager.swift`
4. Add a Widget Extension with **Include Live Activity** enabled.
5. Add `RetreatWidget.swift` and `RetreatActivityAttributes.swift` to the widget-extension target.
6. In the app target Info settings, enable **Supports Live Activities** (`NSSupportsLiveActivities = YES`).
7. Run on a physical iPhone. Notification/lifecycle conclusions from the simulator do not count.

The spike currently uses a 120-second retreat so device tests are fast. Do not treat that duration as product design.

## Determinism contract

The retreat result is calculated when the retreat begins and persisted with the session.

- result namespace: `result`
- phase namespace: `phase`

Phase text must never read or derive from the result. Seeing an intermediate phase must give the user no information about the eventual outcome.

## Notification permission path

The app asks for notification permission when the user first initiates a retreat, not on cold launch.

Record authorization status separately from retention behavior:

- `authorized`
- `provisional`
- `denied`
- `notDetermined`

A denied permission is not equivalent to a failed notification implementation.

## Required test matrix

Run every row on a physical device and record PASS / FAIL plus evidence.

| # | Test | Required for Go? | Result | Failure class | Notes |
|---|---|---|---|---|---|
| 1 | Start retreat and persist start/end/seed/index/result | Yes | | | |
| 2 | Background app, reopen before completion, same session | Yes | | | |
| 3 | Force-kill app, reopen before completion, same session | Yes | | | |
| 4 | Force-kill app, wait past end, local notification arrives | **Yes** | | | |
| 5 | Tap notification, app opens and shows exact precomputed result | **Yes** | | | |
| 6 | Ignore notification, open hours later, same result | **Yes** | | | |
| 7 | Complete entire loop without adding any widget | **Yes** | | | |
| 8 | Immediately start a second retreat after seeing result | Yes | | | |
| 9 | Reboot phone during retreat, reopen, state is coherent | Yes | | | |
| 10 | Move wall clock backwards/forwards, no crash or duplicate result | Yes | | | |
| 11 | Notification permission denied: app remains usable and state persists | Yes | | | |
| 12 | Focus mode: record actual notification behavior | Observe | | | |
| 13 | Low Power Mode: record actual notification behavior | Observe | | | |
| 14 | Home Screen small widget timeline advances without opening app | Observe | | | |
| 15 | Lock Screen inline widget renders | Observe | | | |
| 16 | Live Activity starts, survives backgrounding, and ends coherently | Observe | | | |

## Failure classification

Every failed core-chain test must be classified before changing product design.

### A — Permission / device setting

Examples: notifications explicitly denied, Focus configuration suppresses presentation, Live Activities disabled by user/device setting.

This is a product/onboarding signal only if normal users are likely to encounter it and the app cannot reasonably explain/recover from it.

### B — iOS behavior limitation

The implementation follows Apple's supported behavior, but the OS does not guarantee the product requirement.

This is a genuine product-shape signal.

### C — Implementation bug

Bad persistence, incorrect entitlement/capability, invalid notification request, lifecycle bug, wrong target membership, coding error, etc.

Fix and rerun. **Do not redesign the product around a C failure.**

## Go / No-Go

### Go

Rows 1–11 pass after implementation bugs are fixed, especially:

`kill app -> wait -> local notification -> tap -> deterministic result`

and the loop works with no widget installed.

### No-Go / reshape

A core requirement fails because of a confirmed iOS behavior limitation rather than an implementation bug, or notification permission behavior makes the core loop structurally unreliable for the intended use.

## What this spike must not become

Do not add:

- 历程列表
- 正式 UI / typography tuning
- 道号系统
- 命格导入
- achievements
- streaks
- analytics SDK
- purchases
- cloud sync
- server
- art

The deliverable is the completed matrix above and a short conclusion, not reusable production code.

## Apple references checked for the spike

WidgetKit supports timelines containing multiple dated entries, allowing the system to advance known future states without repeatedly waking the app. Local notification delivery is scheduled through `UNUserNotificationCenter`. ActivityKit is used only as an optional surface; the notification-only path remains the core validation path.
