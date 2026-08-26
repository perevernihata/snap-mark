# Test report

Tested on 27 August 2026 with macOS 26.5.2 and Apple Swift 6.2.4. Full Xcode was not installed, so the project uses Swift Package Manager and a built-in test runner.

## Automated run

Command:

```sh
make test
```

Result: 30 passed, 0 failed.

The suite covers:

- selection normalization and point-to-pixel crop conversion
- an exact supported-mode list containing only area and window capture
- display unions with mixed 1x and 2x scales, negative origins, vertical offsets, and gaps
- one shared selection interaction across one overlay window per display
- a transparent live selector that uses nonactivating, full-screen auxiliary panels
- AppKit-to-Quartz rectangle conversion for the primary display and displays above it
- cancellation when a selection overlay disappears or the app is hidden
- deferred overlay teardown, ARC-safe window ownership, and a pool bounded by display count
- stale overlay callbacks that cannot cancel a newer selection session
- flattened privacy edits and untouched neighboring pixels
- visible pixelation, blackout, and privacy gestures
- blackout precedence across overlapping privacy edits
- bottom-left crop orientation
- pen, highlight, arrow, rectangle, text, pixelate, and blackout rendering
- one-drag creation for every drawing and privacy tool
- PNG and JPEG encoding and decoding
- editor undo, crop, and redo
- annotation-canvas drag ownership while the dedicated title bar remains draggable
- transparent, content-sized live text with renderer-matched styling, exact character preservation, and drag-to-reposition without commit snap-back
- palette changes that recolor an active text draft and survive Return
- history ordering and the 30-item retention mechanism
- history refresh after an external file change and bounded background thumbnail decoding
- capture-service watchdog behavior when an asynchronous capture call stalls
- detection of a running app bundle that has been moved or removed
- permission-gated routing that never launches a prompt-prone capture fallback when access is unavailable
- a full synthetic capture, annotate, crop, redact, export, save, and reopen flow

## Packaged-app checks

The release build passed these checks:

```text
Info.plist: OK
PrivacyInfo.xcprivacy: OK
codesign --verify --deep --strict: passed
Architectures: arm64 and x86_64
Archive checksum: passed
```

The app was then driven through its accessibility interface. The checks covered:

- launch into the editor with a synthetic 1,280 × 760 capture
- text entry and Return-to-commit
- visible text rendering after export-layer redraw
- undo availability after an edit
- clipboard copy and success feedback
- opening and canceling the native Save panel
- returning to the home screen
- labels and selected states for every toolbar and color button
- starting a real area capture, rendering the full virtual desktop overlay, and canceling with Escape
- saving the live capture into history and showing its recent-capture card

The 1.0.1 regression run additionally covered the installed `/Applications/SnapMark.app`: a Recent card opened into the editor, removing its backing test file refreshed the empty state, the delayed-capture progress pill exposed **Cancel**, and a denied Screen Recording permission returned a bounded repair alert instead of an indefinite spinner. Replacing the ad-hoc signed build reset macOS Screen Recording approval, so a final live capture with the exact 1.0.1 binary requires enabling that permission again in System Settings.

The 1.0.3 regression run kept full Screen Recording access unavailable and exercised the recovery path in the installed app. Apple's display picker authorized a one-frame `SCStream`, the frame arrived in 95 ms, and SnapMark created a real 1,512 × 982 area-selection window on the chosen display without an indefinite progress state. The overlay then canceled cleanly. A separate temporary history directory showed a Recent card, decoded its thumbnail, opened the 1,024 × 1,024 image in the editor, and returned to the refreshed Recent list; the temporary capture was removed afterward without touching the normal history directory.

The 1.0.4 regression run reproduced the editor-drag bug at the AppKit event-routing boundary. Before the fix, `AnnotationCanvasNSView.mouseDownCanMoveWindow` was true, so the window could consume a shape drag before the canvas. The canvas now returns false while `WindowDragArea` still returns true. The regression failed before the change and passed afterward.

## 1.0.9 permission regression run

The final run replaced ad-hoc signing with a persistent certificate-backed designated requirement:

```text
certificate root = H"87fc7905f0c4f39278c6658a42c73b943d44f817"
and identifier "com.ivanfioravanti.snapmark"
```

Three consecutively rebuilt apps had different executable CDHashes but the same designated requirement. Screen Recording access was granted to build 9, then build 10 was installed without changing System Settings. The installed 1.0.9 build passed all of these checks:

- **Capture area** opened the selection overlay immediately instead of showing an Apple permission prompt or remaining on **Preparing capture…**.
- Recent Captures incremented after every completed capture and reopened correctly.
- After fully quitting and relaunching SnapMark, **Capture area** started again without touching Privacy settings.
- The native Window selector started and canceled cleanly without leaving a `screencapture` process behind.
- System Settings still showed SnapMark's Screen Recording switch on for the final installed build.
- Exactly one installed SnapMark process remained, and Spotlight found only `/Applications/SnapMark.app`.
- The installed app and the app extracted from `dist/SnapMark.zip` both passed strict code-signature verification and had the same designated requirement.
- A deliberately ad-hoc-signed packaging run was rejected before it could replace the release archive.

## 1.0.15 overlay-lifecycle regression run

The installed build was tested with four connected displays: one 1,512 × 982 Retina display and three 1,920 × 1,080 displays with negative and offset origins. The run covered:

- eleven consecutive area-capture and Escape cycles without **Preparing capture…** becoming stuck
- three completed drag selections opening the editor
- hiding SnapMark during an active selection and returning to the home screen cleanly
- an Arrow drag enabling Undo without changing the main window's bounds
- ten consecutive reopen requests remaining on the single SwiftUI scene with ID `main`
- one SnapMark process and one visible SnapMark window throughout
- a fixed set of 16 cross-Space WindowServer clones after first overlay use; the exact IDs did not grow across subsequent captures
- zero new SnapMark crash reports after installing build 16
- strict signature verification and the same persistent designated requirement used by the existing Screen Recording grant

Two failures were reproduced before the final fix. Build 13 synchronously released an overlay's content view from inside its own mouse or keyboard event. Build 15 then confirmed that `isReleasedWhenClosed` causes an AppKit over-release under Swift ARC. Build 16 instead keeps one `NSWindowController`-owned overlay per physical display, hides and reuses those windows, and releases only their screenshot content on the next main-actor turn.

## 1.0.17 live-area regression run

The installed build was tested on the same four-display layout. The fix changes only **Capture area**. Window capture and the editor keep their existing routes.

- Before the fix, two selector screenshots were 97.77% black and a completed crop was 100% black.
- The selector now uses four transparent panels whose bounds exactly match the four physical displays. The live-selector screenshot measured 0.00% black.
- Release captures the selected Quartz screen rectangle through macOS `screencapture -R`, after the transparent panels leave the screen.
- A direct selection across the primary-to-upper-display seam produced one 600 × 500 PNG with 6.61% black pixels.
- Five consecutive Capture Area and Escape cycles returned to the same main window.
- Four completed live crops opened in the editor. The final 1,332 × 794 PNG measured 0.00% black, and the other completed crops also contained real screen pixels.
- The selector panels use `nonactivatingPanel`, `canJoinAllSpaces`, and `fullScreenAuxiliary`, so opening Capture Area does not switch away from a full-screen app.
- No crash report appeared after the final build. One installed SnapMark process remained.
- The release build passed all 28 self-tests with warnings treated as errors, strict signature verification, and the existing persistent designated requirement.

## 1.0.18 capture-mode removal

SnapMark now has two capture modes: **Capture area** and **Capture window**.

- The home screen uses two direct buttons and no longer has a **More** menu.
- The app menu, menu-bar menu, keyboard commands, and capture router contain no whole-display modes.
- The unused display-composition code and ScreenCaptureKit dependency were removed.
- A regression test checks that `CaptureMode.allCases` is exactly area and window.

## 1.0.19 inline-text regression run

The installed build was tested against the reported text-entry workflow on a real Recent capture.

- The former fixed 260 × 32 field, rounded bezel, opaque fill, focus ring, and placeholder were removed.
- Typed text now appears directly on the screenshot in a transparent editor whose width follows its content.
- Live and committed text use the same font-size rule, color, weight, and stroke attributes.
- Leading and trailing spaces are preserved; only an entirely blank annotation is discarded.
- The draft can be dragged while it remains editable, and its image-space position is updated so Return cannot snap it back.
- The editor sidebar now exposes the drag interaction in both its tool hint and keyboard-help area.
- The strengthened regression moves a live draft by 34 × 21 points, commits it, and verifies its exact characters, style, and final position.
- The release build passed all 29 self-tests with warnings treated as errors. The installed app and release ZIP passed strict signature verification with the existing persistent designated requirement.

## 1.0.20 active-text color regression run

The installed 1.0.19 build reproduced the reported sequence on a real Recent capture: start with Coral, type `Color test`, then click Mint. The palette selected Mint while the active draft stayed Coral.

The inline editor had copied `selectedColor` only when the draft began. A dedicated `selectedColor` subscription now applies every palette choice to the active text storage, caret, typing attributes, and stored annotation color.

- In the installed 1.0.20 build, clicking Mint changed the visible draft immediately while the editor kept focus.
- Pressing Return committed the same Mint text and enabled Undo.
- A regression starts a Coral draft, changes the palette to Blue, and verifies both the live attributed string and committed annotation are Blue.
- The release build passed all 30 self-tests with warnings treated as errors. The installed app and release ZIP passed strict signature verification with the existing persistent designated requirement.
