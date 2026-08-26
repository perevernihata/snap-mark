# macOS screenshot app benchmark

Checked against first-party documentation on 26 August 2026. "Not documented" means the vendor sources reviewed do not promise the behavior. It does not prove the app lacks it.

## Recommended product shape

Build a native menu bar app with one fast path:

1. A configurable global shortcut starts area capture.
2. Every connected display dims at once. The user can drag one rectangle across display boundaries, press Space to switch between area and window capture, and use a magnifier plus live pixel dimensions for precision.
3. On release, show a small post-capture shelf with Copy, Annotate, Save, Drag, and Pin. Do not force the full editor open.
4. Annotate opens a non-destructive editor. Crop, pencil, text, arrows, shapes, blur, pixelate, and blackout remain movable and undoable until export.
5. Copy is the fastest exit. Save, drag to another app, and local history are always one action away.

This combines the strongest documented ideas in the category: Monosnap's all-monitor fullscreen capture, Shottr's freeze-first precision crop, CleanShot's Quick Access Overlay, Snagit's library and editable project model, and Xnapper's simple capture-preview-share flow.

For the implementation, use Swift with AppKit for capture overlays and precise editor input. SwiftUI is a good fit for settings, onboarding, the menu bar panel, and history. Targeting macOS 15.2 or later gives the app Apple's direct multi-display rectangle capture API. A macOS 14 fallback can capture each intersected display with ScreenCaptureKit and composite the pieces.

## Product findings

### macOS Screenshot and Preview

Apple's built-in workflow sets the minimum users already know. Shift-Command-5 offers screen, window, and portion capture. A portion can be moved and resized before capture. Options include a timer, pointer visibility, save destination, and remembered selection. The floating thumbnail can be dragged into another app, opened for Markup, shared, or allowed to save automatically. Holding Control with a screenshot shortcut copies instead of saving. [Apple's Screenshot guide](https://support.apple.com/guide/mac-help/take-a-screenshot-mh26782/mac)

Preview's Markup tools cover crop, sketch, drawing, shapes, text, line and fill styling, and resizing. Image annotations become uneditable after saving, which is one place a dedicated screenshot editor should do better. Preview also supports image descriptions that VoiceOver can read. [Apple's Preview annotation guide](https://support.apple.com/guide/preview/annotate-an-image-prvw1501/mac)

The useful lesson is familiarity. Keep Escape for cancel, Return for commit, Space for mode switching or moving a selection, Command-Z for undo, and standard Save and Copy commands.

### CleanShot X

CleanShot supports area, window, fullscreen, timer, and scrolling capture. Its precision options include a crosshair, magnifier, frozen screen, exact size, aspect-ratio lock, and remembered selection in All-In-One mode. [CleanShot feature list](https://cleanshot.com/features)

Its editor has crop with edge snapping and aspect ratios, pencil, highlighter, four arrow styles, line, rectangle, filled rectangle, ellipse, text styles, counters, spotlight, randomized pixelation, and blur. Annotations can be stored in an editable CleanShot project. Multiple images can be combined on one canvas. [CleanShot feature list](https://cleanshot.com/features)

The Quick Access Overlay is its best workflow idea. It appears immediately after capture and exposes copy, save, annotate, upload, drag, restore, and auto-close without opening the editor. It supports placement across multiple displays. Capture History can retain up to one month and can filter, restore, or delete captures. [CleanShot feature list](https://cleanshot.com/features)

Its URL API can target a numbered display and route a capture straight to copy, save, annotate, upload, or pin. The official material reviewed does not promise one selected region spanning several displays. [CleanShot URL API](https://cleanshot.com/docs-api)

### Shottr

Shottr explicitly recommends taking a full-screen image first, then cropping the frozen image in its editor. The crop can be zoomed, adjusted, and committed with Return. This is excellent for hover states, video frames, menus, and pixel-accurate selection. Direct click-drag area capture is also available. [Shottr start guide](https://shottr.cc/kb/startguide), [precision guide](https://shottr.cc/kb/precision)

After area capture, the user can choose either the editor or a small preview thumbnail. The thumbnail provides save, copy, OCR and QR extraction, pin, and edit. Shottr remembers the preference. Its editor provides adjustable arrows, shapes, text, blur, crop/select, and object properties in a small contextual toolbar. [Shottr start guide](https://shottr.cc/kb/startguide)

Copy writes image data to the pasteboard. Save writes to a chosen default folder, Save As asks for a name, and a draggable proxy behaves like a file in Finder, Mail, and other apps. Pin keeps a capture above other windows. The editor hides after copy or save but can reopen the current image. Shottr does not document a general local capture-history browser. [Shottr start guide](https://shottr.cc/kb/startguide)

Screen Recording permission is required for capture. Accessibility permission is required only when scrolling capture sends scroll events to another app. Basic screenshots do not need it. [Shottr privacy policy](https://shottr.cc/blog/privacy)

The official material reviewed does not promise one capture spanning several displays.

### Snagit for Mac

Snagit uses an All-In-One capture mode, crosshairs, a magnifier, window and region detection, scrolling capture, presets, and extensive customizable shortcuts. The Mac shortcut guide also documents fixed ratios, one-pixel crosshair movement, and a multiple-region gesture. [Snagit hotkey guide](https://www.techsmith.com/learn/tutorials/snagit/snagit-hotkeys/)

Its editor is the deepest of the reviewed products. Tools include crop, pen, highlighter, arrow and line, text, callout, shapes, steps, blur, spotlight, magnify, object grouping, layer order, snapping, and undo/redo. It also has a Recent Captures tray, searchable Library, tags, and Share History. [Snagit features](https://www.techsmith.com/snagit/features/), [Snagit hotkey guide](https://www.techsmith.com/learn/tutorials/snagit/snagit-hotkeys/)

Current official Mac help says that when several monitors are connected, only one screen can be selected at a time for fullscreen capture. A true spanning capture would be a useful differentiator. [Snagit 2024 Help, page 80](https://www.techsmith.com/learn/wp-content/uploads/2025/01/Snagit-Help-2024-EN.pdf)

Snagit has the clearest product accessibility work in this group. Recent Mac releases mention screen-reader labels, keyboard navigation fixes, accessible colors and icons, hover states, and tooltips. [Snagit Mac 2026 version history](https://support.techsmith.com/hc/en-us/articles/41975263481613-Snagit-Mac-2026-Version-History)

Screen capture requires macOS permission and may require quitting and reopening after approval. Automatic scrolling additionally requires Accessibility access for Snagit and its helper. [Snagit permission guide](https://support.techsmith.com/hc/en-us/articles/360046984312-Mac-OS-Permissions), [scrolling capture permission guide](https://support.techsmith.com/hc/en-us/articles/203732578-Enable-Scrolling-Capture-on-macOS)

### Monosnap

Monosnap is the only reviewed app whose official Mac guide clearly says fullscreen capture includes the area of all monitors in one image. It also supports area and window capture, a square constraint with Shift, moving the current selection with Space, a magnifier, previous-area capture, frozen capture, and delay. [Monosnap Mac screenshot guide](https://monosnap.zendesk.com/hc/en-us/articles/360017530380-Mac-How-to-take-screenshots)

The vendor-authored App Store listing documents pen, text, arrows, shapes, blur, customized hotkeys, delayed screenshots, an 8x crop magnifier, clipboard and drag workflows, one-click sharing, and cloud storage. Pixelation is not documented there. [Monosnap App Store listing](https://apps.apple.com/us/app/monosnap-screenshot-editor/id540348655?mt=12)

Monosnap can reopen the last screenshot and browse cloud uploads, but the reviewed sources do not describe a local history browser comparable to CleanShot or Snagit.

### Xnapper

Xnapper aims for a short "capture, preview, share" workflow. It provides a custom global shortcut, region capture, Space-based window capture, arrows, shapes, text, blur, manual and automatic redaction, screenshot history, file and clipboard input, presets, output compression, and on-device text recognition. It also adds presentation backgrounds, padding, shadows, ratios, and automatic visual balancing. [Xnapper product page](https://xnapper.com/)

Its annotation guide documents editable text, arrows, rectangles, ovals, color, line width, fonts, manual pixelation, automatic detection of sensitive text, PNG save, and clipboard/file input. Freehand painting is not documented. [Xnapper annotation guide](https://xnapper.com/blog/annotate-screenshot)

The current changelog says window selection works across multiple displays. The official material reviewed does not promise a region spanning displays or a combined all-display image. [Xnapper changelog](https://xnapper.com/changelog)

## Feature decisions

| Area | Ship behavior | Reason |
| --- | --- | --- |
| Cross-display | Region selection can cross display seams. Also provide Window, Current Display, and All Displays commands. | This meets the stated requirement and exceeds the documented CleanShot, Shottr, Snagit, and Xnapper behavior. |
| Selection | Dim all displays. Show crosshair, magnifier, dimensions, edge snapping, and window hover. Space switches area/window, Shift locks ratio, arrows adjust by one point, Escape cancels, Return commits. | These controls are already familiar across Apple Screenshot, Monosnap, CleanShot, Shottr, and Snagit. |
| Frozen capture | Offer "Freeze screen while selecting" and remember the setting. | Shottr and CleanShot show why this matters for transient content. |
| Post-capture | Show a compact shelf with Copy as the primary action, then Annotate, Save, Drag, and Pin. Let users choose auto-copy, auto-save, editor, or shelf as the default. | The fast path should not pay the cost of a full editor. |
| Crop and edit | Keep the base image immutable and store crop plus annotation objects separately. All objects remain selectable and undoable. | CleanShot and Snagit both preserve editable work. Preview does not after image save. |
| Drawing | Pencil with smoothing, text, arrow, line, rectangle, ellipse, filled rectangle, highlighter, and numbered step marker. | Covers the common communication tasks without a crowded first release. |
| Privacy | Provide Blur, Pixelate, and solid Blackout. Label Blackout as the secure choice. Flatten redactions into exported pixels. Warn that an editable project retains the original. | A decorative overlay is not redaction. Blur and ordinary pixelation can leave recoverable visual information. |
| Output | Copy PNG data, quick-save PNG, Save As for PNG/JPEG/HEIC, drag as a promised file, and Pin. Keep cloud upload out of the first release. | Clipboard and drag are the shortest Mac sharing paths. Cloud adds a separate privacy and account problem. |
| History | Local history with Off, 1 day, 7 days, 30 days, and Forever. Support restore, delete, reveal in Finder, and "Do not keep this capture." | CleanShot's retention and Snagit's library are useful, but sensitive captures need an explicit escape hatch. |
| Shortcuts | One customizable global area shortcut plus optional direct shortcuts for Window, All Displays, Previous Area, and History. Do not take Apple's Shift-Command-3/4 defaults without warning. | Frequent actions deserve shortcuts, but collisions must be visible and reversible. |

## First-party implementation map

### Capture and display geometry

- Use [`SCScreenshotManager.captureImage(in:completionHandler:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage%28in%3Acompletionhandler%3A%29) on macOS 15.2 and later. Apple defines its rectangle in screen points as display-agnostic and explicitly says it supports multiple displays. This is the direct implementation of a cross-display selection.
- On macOS 26, [`captureScreenshot(rect:configuration:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/capturescreenshot%28rect%3Aconfiguration%3Acompletionhandler%3A%29) adds `SCScreenshotConfiguration`, including PNG, JPEG, or HEIC output, destination URL, cursor choice, SDR/HDR, dimensions, and source/destination rectangles.
- For macOS 14 through 15.1, enumerate [`SCShareableContent`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent) and its [`SCDisplay`](https://developer.apple.com/documentation/screencapturekit/scdisplay) values. Intersect the selection with each display, capture each piece with `SCScreenshotManager.captureImage(contentFilter:configuration:)`, then composite them into one bitmap in virtual-desktop coordinates.
- Do not start new work on [`CGWindowListCreateImage`](https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage). Apple marks it deprecated, and ScreenCaptureKit is its replacement for screenshots.
- Keep selection geometry in global screen points. Use [`NSScreen.screens`, `frame`, and backing-coordinate conversion`](https://developer.apple.com/documentation/appkit/nsscreen) instead of assuming every display has scale 2 or origin 0. Mixed Retina scaling, negative display origins, vertically offset monitors, and gaps between monitors all need tests.
- Build one borderless AppKit overlay window per `NSScreen`, backed by one shared selection model. Use [`NSWindow.CollectionBehavior`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) so overlays can join Spaces and appear with full-screen apps. Hide every overlay before the final capture.
- Use `SCShareableContent` window frames for hover-based window selection. This avoids requesting Accessibility access just to identify a window.

### Editor and rendering

- Represent each annotation as a model object in image coordinates. Render lines, arrows, rectangles, ellipses, and pencil strokes with Core Graphics paths or [`CAShapeLayer`](https://developer.apple.com/documentation/quartzcore/cashapelayer). Render editable text with AppKit text controls, then flatten it during export.
- Crop with [`CGImage.cropping(to:)`](https://developer.apple.com/documentation/coregraphics/cgimage/cropping%28to%3A%29). Convert the editor's view-space crop to bitmap pixels once, in a tested coordinate-transform function.
- Apply regional blur and pixelation through Core Image masks using [`CIGaussianBlur`](https://developer.apple.com/documentation/coreimage/cigaussianblur) and [`CIPixellate`](https://developer.apple.com/documentation/coreimage/cipixellate). Blackout should replace the selected pixels, not cover them with an exportable vector layer.
- Register every create, move, resize, style, crop, and delete action with [`UndoManager`](https://developer.apple.com/documentation/foundation/undomanager). Preserve normal Command-Z and Shift-Command-Z behavior.
- Export a flattened bitmap by drawing the cropped base image, raster effects, and vector/text annotations into one Core Graphics context. An editable project should be a separate file type and must state that it retains unredacted source pixels.

### Clipboard, save, drag, and history

- Write PNG data or `NSImage` to [`NSPasteboard.general`](https://developer.apple.com/documentation/appkit/nspasteboard). The general pasteboard participates in Universal Clipboard.
- Use [`NSSavePanel`](https://developer.apple.com/documentation/appkit/nssavepanel) and `allowedContentTypes` for Save As. Use Uniform Type Identifiers such as [`UTType.png`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttypepng), JPEG, and HEIC.
- Use `NSFilePromiseProvider` for drag-out so the shelf can behave like a file without saving a permanent copy first.
- Store local history under Application Support. Keep the image file and a small metadata record with creation date, dimensions, source app/window when available, and retention deadline. SwiftData is adequate for the index. Deleting history must remove both metadata and image files.

### Shortcuts and permissions

- SwiftUI `keyboardShortcut` and AppKit menu key equivalents work only while the app participates in command routing. They are not system-wide hotkeys. For a global capture shortcut, use the system `RegisterEventHotKey` function from HIToolbox or a small, audited wrapper around it. Avoid a global `NSEvent` key monitor. Apple says key monitoring requires Accessibility trust and can only observe, not stop, the original event. [`NSEvent.addGlobalMonitorForEvents`](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29)
- Add `NSScreenCaptureUsageDescription`. Preflight with [`CGPreflightScreenCaptureAccess`](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29) and request with [`CGRequestScreenCaptureAccess`](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess%28%29). Explain the need before triggering the system dialog, show the exact System Settings path after denial, and handle the quit-and-reopen case.
- Do not request Accessibility permission for normal screenshots, global hotkeys, or editor input. Ask for it only if a later scrolling-capture feature sends events to another app. Shottr and Snagit both use this narrower permission boundary.
- Treat capture denial and revocation as normal states. The menu must remain usable and show a clear repair action instead of silently producing a blank desktop.

## Accessibility requirements

Apple says standard AppKit controls include accessibility behavior by default. Custom `NSView` controls need role-specific protocols, properties, actions, and notifications. [`Accessibility for AppKit`](https://developer.apple.com/documentation/appkit/accessibility-for-appkit), [`NSAccessibilityProtocol`](https://developer.apple.com/documentation/appkit/nsaccessibilityprotocol)

- Build the shelf, toolbar, inspectors, settings, and history from standard controls where possible.
- Give every icon-only button a short localized accessibility label, help text when useful, and a visible tooltip. Expose selected state for tools such as Pencil or Blur.
- Make every editor action reachable by keyboard. Show focus rings, keep menu commands available, and never depend on hover, drag, color, or a timed auto-close as the only path.
- Expose the canvas as an image with dimensions and an optional description. Expose each annotation as a selectable element with role, frame, label, and actions for move, resize, edit, and delete. Post accessibility notifications after selection and geometry changes.
- Follow Apple's macOS control guidance of 28 by 28 points by default and never below 20 by 20 points. Preserve sufficient spacing between adjacent tools. [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- Respect standard shortcuts and offer customization only for frequent app-specific commands. [Apple keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards)
- Test with VoiceOver, Full Keyboard Access, Increase Contrast, Reduce Transparency, Reduce Motion, larger text, light and dark appearances, and color filters.

## End-to-end test matrix

Automate pure geometry, editor state, undo, export, history retention, and image comparison tests. Run permission and real-display cases as signed end-to-end tests because macOS TCC approval cannot be granted silently by a unit test.

### Capture

- One display at 1x and 2x scale.
- Two displays side by side, vertically stacked, and offset.
- Mixed 1x and 2x displays, a secondary display left of the main display, and a changed main display.
- Region entirely on each display, crossing every seam, crossing a gap in the virtual desktop, and covering all displays.
- Window capture on each display, a window straddling displays, hidden or minimized windows, menu bar, Dock, Stage Manager, separate Spaces, and a full-screen app.
- Display connected, disconnected, or rearranged while capture mode is open.
- First run allowed, denied, dismissed, later allowed, and permission revoked while the app is running.
- Freeze mode with menus, hover states, animation, and a playing video frame.

### Editor and export

- Crop before and after annotations. Verify annotation coordinates and stroke widths at every zoom level.
- Pencil, text editing, arrow direction, shape resize, multi-select, delete, undo, and redo.
- Blur, pixelate, and blackout at image edges and after crop. Reopen PNG, JPEG, and HEIC exports and inspect pixels to confirm redacted source pixels are gone.
- Copy and paste into Preview, Notes, Mail, and a browser upload field. Drag to Finder and Mail. Save over an existing file and cancel Save As.
- Very large cross-display and scrolling-size images. Watch peak memory, export time, and history thumbnail generation.
- Editable project round trip. Show a privacy warning and confirm flattened exports contain no editable source layers.

### UX and accessibility

- Complete area capture to clipboard using only the keyboard after invoking the global shortcut.
- Complete capture and basic annotation using VoiceOver and Full Keyboard Access.
- Verify focus order, accessible names, tool selected states, menu equivalents, Escape behavior, and no shortcut collision with macOS Screenshot.
- Verify the shelf remains reachable but does not steal typing focus from the prior app. Test auto-close with keyboard and VoiceOver focus active.
- Verify denied permissions, empty history, failed saves, and low-disk-space errors have a next action and never lose the only copy of a capture.

## Scope order

The first releasable slice should include cross-display area capture, window capture, all-display capture, a post-capture shelf, crop, pencil, text, arrows, shapes, blur, pixelate, blackout, clipboard, quick save, drag-out, undo/redo, local history, configurable shortcuts, and the permission repair flow.

Pinning, scrolling capture, OCR, presentation backgrounds, editable project files, cloud sharing, screen recording, and video editing can follow. They are valuable, but they should not delay a fast, reliable screenshot-to-clipboard path.
