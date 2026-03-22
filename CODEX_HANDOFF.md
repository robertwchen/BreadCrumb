# Breadcrumb Codex Handoff

This document is the fast-context handoff for the next Codex session or teammate.

## What Breadcrumb Is

Breadcrumb is an iPhone-first, offline-first visual memory aid MVP.

Core promise:

> Help a user recover the last visual context where an important item was seen.

This repo intentionally does **not** claim generic object detection, AR room memory, background surveillance capture, or medical diagnosis/treatment.

## What Was Built

The repository now contains:

- A fresh SwiftUI iOS app scaffold in `Breadcrumb/`
- A minimal Xcode project in `Breadcrumb.xcodeproj/`
- Existing research/source docs from the earlier investigation

### Current MVP flow

1. Register a tracked item with 1 or more reference photos.
2. Capture explicit breadcrumb snapshots from the phone camera.
3. Optionally add a short context note and manually confirm which tracked items are visible.
4. Search for an item.
5. Show the latest likely match, preferring:
   - manual confirmation from a saved snapshot
   - otherwise on-device Vision feature-print similarity against registered reference photos
6. Show nearby timeline frames as the short context strip.

## Key Files

### App shell

- `Breadcrumb/App/BreadcrumbApp.swift`
- `Breadcrumb/App/ContentView.swift`
- `Breadcrumb/App/AppModel.swift`

### Registration flow

- `Breadcrumb/Features/Register/ItemLibraryView.swift`
- `Breadcrumb/Features/Register/RegisterItemView.swift`

### Capture flow

- `Breadcrumb/Features/Capture/CaptureTimelineView.swift`
- `Breadcrumb/Features/Capture/SnapshotReviewView.swift`
- `Breadcrumb/Shared/Camera/CameraCaptureView.swift`
- `Breadcrumb/Services/Camera/CameraSessionController.swift`

### Search / retrieval

- `Breadcrumb/Features/Search/FindItemView.swift`
- `Breadcrumb/Services/Search/SearchService.swift`
- `Breadcrumb/Services/Vision/ImageSimilarityService.swift`

### Persistence / models

- `Breadcrumb/Services/Storage/LibraryStore.swift`
- `Breadcrumb/Models/TrackedItem.swift`
- `Breadcrumb/Models/TimelineSnapshot.swift`
- `Breadcrumb/Models/BreadcrumbLibrary.swift`
- `Breadcrumb/Models/SearchModels.swift`

### Project / resources

- `Breadcrumb.xcodeproj/project.pbxproj`
- `Breadcrumb/Resources/Info.plist`
- `Breadcrumb/Resources/Assets.xcassets/`
- `README.md`

## Important Product Decisions Already Made

- iPhone-only for the hackathon MVP
- Offline-first and local-only storage
- Explicit capture only
- No AR in the MVP
- No always-on recording
- No generic object-class claims for keys/cane/etc.
- Best demo objects are:
  - pill bottle / meds
  - wallet as a secondary item

## What Is Real vs Inferred

### Real / implemented

- Local reference-photo registration
- Local breadcrumb snapshot capture
- Local JSON + image storage
- On-device image similarity using Apple Vision feature prints
- Manual snapshot tagging for visible items
- Search result with primary match + nearby context strip

### Inferred / intentionally lightweight

- "Last likely seen" is a ranking result, not a guarantee
- "Route/context snippet" is approximated using adjacent timeline frames and optional notes

### Not implemented and intentionally cut

- AR anchors
- SLAM route reconstruction
- Caregiver mode / cloud sync
- Background recording
- Generic real-time object detection for all item classes

## What Still Needs To Be Done On A Mac/iPhone

This Codex session ran in a Windows environment without Xcode, so the following still need real validation:

1. Open `Breadcrumb.xcodeproj` in Xcode on macOS.
2. Set the Apple development team / signing settings.
3. Build the app for an iPhone target.
4. Validate camera permission flow.
5. Validate photo capture works on-device.
6. Validate Vision feature-print matching quality on:
   - pill bottle
   - wallet
7. Check that the hand-written Xcode project opens cleanly and that Xcode does not need to rewrite/fix anything.
8. Replace the placeholder app icon if desired.

## Most Likely Risks

### 1. Xcode project integrity

The `.xcodeproj` was created manually rather than by Xcode or XcodeGen in this environment.

What to verify:

- project opens without repair prompts
- target membership is correct
- bundle identifier and signing are valid
- asset catalog is recognized

### 2. Vision retrieval quality

Feature-print similarity is a strong honest baseline, but its live-demo quality still depends on:

- lighting consistency
- angle changes
- cluttered scenes
- object size in frame

If similarity is weak, the fallback is to lean harder on:

- manual confirmation toggles
- better reference photos
- clearer capture guidance

### 3. Camera UX polish

The camera flow is functional, but may need:

- improved loading states
- a post-capture toast/confirmation
- better framing guidance
- clearer error copy

## Suggested First Mac-Side Validation Sequence

1. Open the project in Xcode.
2. Fix signing and run on a real iPhone.
3. Register one pill bottle with 3 reference photos.
4. Capture 5 to 8 snapshots around a room, only some containing the pill bottle.
5. Manually confirm the visible item in 1 or 2 shots.
6. Run a search and inspect:
   - whether the latest manual match is shown first
   - whether visual matches are sensible when no manual match exists
   - whether nearby timeline frames tell the story clearly

## Recommended Next Improvements

### Highest priority

1. Device compile + bug fixing in Xcode
2. Tighten the result card for demo storytelling
3. Add a confidence explanation string for visual matches
4. Add a seeded demo mode or sample library for presentations

### Good next steps after that

5. Add delete/edit actions for items and snapshots
6. Store light metadata like location or motion only if it improves context and remains private
7. Add lightweight onboarding explaining what Breadcrumb does and does not promise
8. Add tests around storage and search ranking

## Recommended Demo Script

1. Show the problem: important objects get misplaced and the context is lost.
2. Register a pill bottle and a wallet.
3. Capture a few explicit breadcrumbs while moving through a small environment.
4. Search for the pill bottle.
5. Show:
   - the matched image
   - the timestamp
   - the nearby context strip
6. Explain that Breadcrumb is private, local, and technically honest.

## Existing Research Files In This Repo

These were already present and still provide useful context:

- `final_research_memo.md`
- `sources.md`
- `concept_scorecard.csv`
- `competitors.csv`
- `user_pain_clusters.csv`

## Best Prompt For The Next Codex Session

Use something close to this:

> Open this iOS project and finish Mac-side validation. First, make the Xcode project build and run on an actual iPhone. Then test the Breadcrumb MVP flow end-to-end, fix any camera/Vision/storage bugs, and improve the live-demo UX without expanding scope beyond the existing product decisions in `CODEX_HANDOFF.md`.

## One-Line Summary

This repo now contains a technically honest Breadcrumb MVP scaffold; the remaining work is primarily Xcode/device validation, bug fixing, and live-demo polish on macOS.
