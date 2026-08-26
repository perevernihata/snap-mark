# Architecture

SnapMark is a Swift Package that produces one native macOS executable. It has no third-party runtime dependencies.

## Main components

- `AppModel` owns the application state and coordinates capture, history, editor sessions, and export.
- `CaptureService` invokes the macOS screenshot utility after permission and geometry checks.
- `SelectionOverlayController` keeps one reusable transparent panel per physical display and shares one selection model across them.
- `EditorSession` stores the base image, non-destructive annotations, and undo and redo snapshots.
- `AnnotationCanvasNSView` handles direct AppKit pointer and text interaction inside the SwiftUI editor.
- `ImageRenderer` flattens annotations for clipboard, saved files, and sharing. Privacy edits run in a final pass so blackout always wins an overlap.
- `HistoryStore` keeps up to 30 raw PNG captures under Application Support when history is enabled. The capture directory is mode `0700`; PNG files are normalized to mode `0600`, including older files discovered during reload.

## Capture flow

```text
shortcut or button
        |
        v
permission and route check
        |
        +--> area: live multi-display selector --> bounded region capture
        |
        +--> window: macOS window picker
        |
        v
EditorSession --> annotations --> flattened export
        |
        +--> optional local raw-history copy
```

The selection overlay never paints a cached desktop image. It leaves the real desktop visible, records a global AppKit rectangle, removes the panels, then captures the matching Quartz rectangle.

## Privacy model

SnapMark does not contain networking code. Preferences use app-local `UserDefaults`. Recent history reads file timestamps to show capture dates. Those uses are declared in `Packaging/PrivacyInfo.xcprivacy`.

Blackout and pixelation modify exported pixels, but the original capture remains unchanged in Recent history. Pixelation is visual obfuscation rather than reliable secret redaction; Blackout replaces selected exported pixels. That separation makes undo possible and is called out in the UI and README.

## Test strategy

`SnapMark --self-test` runs deterministic tests without a screen-capture prompt. It covers geometry, overlay ownership, capture routing, annotations, redaction output, crop orientation, undo and redo, history, watchdogs, process locking, and file export. UI and multi-display changes also require a manual installed-app pass because macOS window-server behavior cannot be fully represented in a headless test.
