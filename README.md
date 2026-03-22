# Breadcrumb

Breadcrumb is an iPhone-first SwiftUI MVP for answering:

> Where did I last leave the thing I depend on?

The app keeps the promise narrow and honest:

- Observe a scene and let Breadcrumb auto-discover object candidates on device.
- Promote the candidates that matter into named memories when you want stronger identity continuity.
- Keep a local timeline of sightings, hand-linked interaction inferences, and last-known context.
- Add optional reference photos later if you want stronger re-identification for a specific object.

## MVP Scope

- Offline-first and local-first.
- Fresh installs work with zero registered objects and zero uploaded reference photos.
- Optional hosted refinement can be layered on later without breaking the offline core.
- No background surveillance recording.

## Architecture

```text
Observe -> Saliency + Foreground Proposals + Vision Tracking + Hand Pose -> Candidate / Event Memory Graph
Promote Candidate -> Named Object Memory
Optional Reference Photos -> Stronger Re-identification Only When Needed
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
- The current implementation uses `AVFoundation` for live camera capture, `Vision` proposals and tracking for automatic discovery, and feature prints as a local re-identification aid.
- This workspace was scaffolded in a non-macOS environment, so final device validation still needs to happen in Xcode on a Mac.
