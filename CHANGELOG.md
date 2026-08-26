# Changelog

This file records user-visible SnapMark changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and releases use [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- A privacy-safe editor walkthrough recorded entirely from SnapMark's built-in synthetic scene.

## [1.0.20] - 2026-08-27

This is the first public source release.

### Added

- Area capture across display boundaries and native macOS window capture.
- A local editor with pen, highlight, arrow, rectangle, text, pixelate, blackout, and crop tools.
- PNG clipboard export, PNG and JPEG saving, the macOS share sheet, undo, redo, capture timers, and a global capture shortcut.
- Local Recent capture history with a configurable retention switch.
- VoiceOver labels and keyboard shortcuts for the editor.
- Universal arm64 and Intel packaging, a privacy manifest, automated tests, and GitHub release automation.

### Fixed

- Repeated captures no longer create duplicate main windows or leak selection overlays.
- Area selection stays live across four-display layouts, full-screen apps, mixed scaling, negative origins, and display seams.
- Capture preparation has cancellation and timeout handling instead of an indefinite spinner.
- Recent thumbnails reload and open without blocking the main thread.
- Editor drags create annotations instead of moving the whole window.
- Inline text is transparent, content-sized, movable while typing, and visually consistent after commit.
- Changing the palette recolors an active text draft and preserves that color after pressing Return.

[Unreleased]: https://github.com/perevernihata/snap-mark/compare/v1.0.20...HEAD
[1.0.20]: https://github.com/perevernihata/snap-mark/releases/tag/v1.0.20
