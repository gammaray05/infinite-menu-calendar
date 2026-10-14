# InfiniteCalendar

A native, offline macOS menu bar calendar with continuous bidirectional week scrolling. Swift, SwiftUI and AppKit; macOS 14+; Apple Silicon. No external dependencies, events, accounts, networking, permissions or telemetry.

## Download and install

In GitHub **Actions → Build Release DMG**, open the latest successful run and download **InfiniteCalendar-macOS-AppleSilicon** under Artifacts. Extract the ZIP, open `InfiniteCalendar.dmg`, and drag the app into Applications. GitHub requires sign-in for artifact downloads. See [installation instructions](INSTALL.md), including first-launch approval for this ad-hoc signed, non-notarized build.

## Architecture

- `Sources/CalendarCore/CalendarEngine.swift`: Foundation calendar arithmetic, DST-aware days and a bounded 313-week coordinate window with seven real dates per row and no duplicated or missing cells at month boundaries.
- `CalendarScrollView.swift`: native NSScrollView and a virtual document view drawing only visible weeks. At either edge it rebuilds around the visible week and compensates the clip origin by the exact pixel offset. Native wheel and momentum events continue over the entire view, including day numbers. Date metadata is bounded; there is no growing view hierarchy.
- `AppDelegate.swift`: NSStatusItem, transient NSPopover, settings window, Escape handling, day/timezone/locale refresh and remembered scroll position. No primary window and no Dock icon.
- `Views.swift`: fixed SwiftUI month and weekday headers and settings; colors, themes, sizes, local language, week numbers and SMAppService login registration.
- `Preferences.swift`: local UserDefaults persistence; system calendar and timezone, regional first weekday and calendar language. Calendars with leap months are handled by Foundation month intervals rather than a fixed twelve-month assumption.

The menu bar shows today’s number in a rounded badge that follows the system menu bar appearance. The popover has a fixed month title, fixed weekday names and six visible weeks by default (Normal); Compact shows five weeks and Extended seven. The title follows the month at the center of the visible grid; dates flow continuously through month and year changes. The active month uses full foreground contrast; adjacent months use 38% text opacity. Active-month weekend numbers use 72% opacity when weekend highlighting is enabled. Increase Contrast raises these values. Month emphasis fades smoothly over 180 ms, including interrupted or reversed scrolling, and switches immediately with Reduce Motion. The menu bar badge is an 20 × 16-point rounded badge with an 11-point bold day number. Existing saved Normal/Extended sizes are migrated once to their new Compact/Normal names; subsequent user choices are preserved.

Hover animations run for 120 ms only while changing hovered days. Reduce Motion disables hover and popover animation. Today navigation animates nearby movement and jumps directly over distant dates. VoiceOver exposes the visible dates with full localized labels. Arrow keys navigate dates; Page Up/Down scroll; Home returns to today.

## Build with Xcode (optional)

Open `InfiniteCalendar.xcodeproj`, select the `InfiniteCalendar` scheme, choose My Mac, and Build / Run. The project is included and needs no project-generation dependencies. The Swift package can also be opened in Xcode. To regenerate the included project after adding source files, run `python3 scripts/generate_project.py`.

```sh
swift test --configuration release
bash scripts/build-release.sh
```

The release script invokes Xcode's Release compiler for arm64, creates the native app icon, signs the bundle ad hoc, validates it, creates the compressed DMG, and verifies the image. GitHub Actions additionally mounts the image, checks its contents, launches a copied app and checks process survival. The DMG and SHA-256 checksum are retained as an artifact for 90 days. Push to `main` or choose **Run workflow** to rebuild.

## Validation scope

Automated tests cover leap years including century rules, Monday/Sunday alignment, four/five/six-week months, DST across four timezones, December/January, Gregorian/Hebrew/Islamic/Buddhist/Japanese calendars, 1,000 coordinate recentrings, large scroll jumps, continuous date coverage, and the viewport-driven month title. Native integration tests also validate 40 bidirectional recentrings, day hit targets, compact panel height, weekday alignment, readable weekend colors, midnight day-number changes, compact badge rendering, adjacent-month colors, smooth and reversed transitions, Reduce Motion, VoiceOver labels, appearance rendering and scroll restoration. CI validates compilation, packaging, signatures and basic process launch. Trackpad feel, VoiceOver interaction, multi-monitor behavior and login registration require interactive testing on a Mac; automated process launch does not certify these experiences. Foundation's representable date range is finite, but navigation is not limited to a fixed user-facing date range.

Notarized distribution requires an Apple Developer ID certificate and notarization credentials; this repository's default workflow uses no signing secrets.
