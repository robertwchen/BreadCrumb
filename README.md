# Breadcrumb

Breadcrumb is an iPhone-first SwiftUI MVP for answering:

> Where did I last leave the thing I depend on?

The app keeps the promise narrow and honest:

- Register 1-2 important personal objects with a few reference photos.
- Capture explicit timeline snapshots when you want visual breadcrumbs.
- Search locally for the latest likely sighting using on-device image similarity.
- Show the matched image, nearby timeline context, and any manual confirmation tags.

## MVP Scope

- Offline-first and local-only.
- No generic object detection claims.
- No AR anchors.
- No background surveillance recording.

## Architecture

```text
Register Item -> Reference Photo Library
Capture Snapshot -> Timeline Store
Find Item -> Vision Feature Print Similarity -> Last-Seen Result + Context Strip
```

## Project Layout

```text
Breadcrumb.xcodeproj/
Breadcrumb/
  App/
  Features/
    Register/
    Capture/
    Search/
  Models/
  Services/
    Camera/
    Search/
    Storage/
    Vision/
  Shared/
    Camera/
    Views/
  Resources/
```

## Build Notes

- Open `Breadcrumb.xcodeproj` in Xcode on macOS.
- Target is iOS 17+.
- The current implementation uses `AVFoundation` for explicit camera capture and `Vision` feature prints for local visual matching.
- This workspace was scaffolded in a non-macOS environment, so final device validation still needs to happen in Xcode on a Mac.
